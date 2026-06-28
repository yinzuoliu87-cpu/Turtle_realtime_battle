extends Node3D
const HpBarScene := preload("res://scripts/scenes/hp_bar.gd")   # 回合制版好看血条 (自定义 _draw, 复用)
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
# 技能放招 = Botworld 真相(用户2026-06-28实测沙蝎: 充能条不断走→满放大招→再走; 躲避CD5s/大招CD13s/普攻0.5s):
#   【逐技各自固定时间冷却】(按秒, 与打没打中无关); "大招"=冷却很长的技, 充能条=该技冷却进度.
#   各技 cost(∝强度) 换算冷却秒数 → 龟盾CD短常放, 气波/弹幕/大招CD长少放. (非"靠伤害攒龟能"=我之前错的)
const SKILL_COST_DEFAULT := 95.0           # 技能强度档 (→换算冷却秒数; 见 SKILL_COST)
const SKILL_CD_FACTOR := 0.075             # cost→冷却秒数 (70≈5.3s·95≈7s·140≈10.5s·170≈12.8s; 对齐Botworld沙蝎)
const SKILL_GCD := 0.4                      # 同龟两次放技最小间隔 (防多技同帧连爆)
const SEP_RADIUS := 56.0                    # 单位软分离半径 (像素口径; 防扎堆, 调大点更散)
const HP_MULT := 3.0                       # HP 倍率 (节奏旋钮, 同 2D)
const SHIELD_CAP_MULT := 1.5
const RAGE_MAX := 100.0                    # 怒气满 (熔岩变身)
const STACK_DOT_TICK := 1.0                # 各类层数 DoT 每秒结算一次
const BUFF_SEC := 5.0                      # buff/控制/DoT 通用秒数 (规格 "N秒", 待 F5 调)
const CTRL_SEC := 1.5                      # 眩晕/冻结/嘲讽 默认秒数

# 28 龟战斗属性 (1:1 复用): id → [melee, move_spd(px/s), atk_interval(s), atk_range(px)]
const STATS := {
	"basic": [true, 105.0, 0.85, 70.0], "stone": [true, 70.0, 1.1, 70.0], "bamboo": [true, 105.0, 0.85, 70.0],
	"angel": [false, 105.0, 0.85, 230.0], "ice": [false, 105.0, 0.85, 230.0], "ninja": [true, 145.0, 0.6, 70.0],
	"two_head": [true, 145.0, 0.85, 70.0], "ghost": [false, 145.0, 0.6, 340.0], "diamond": [true, 70.0, 1.1, 70.0],
	"fortune": [true, 105.0, 0.85, 70.0], "dice": [false, 145.0, 0.6, 230.0], "rainbow": [true, 105.0, 0.85, 70.0],
	"gambler": [false, 145.0, 0.85, 230.0], "hunter": [false, 145.0, 0.6, 340.0], "pirate": [false, 105.0, 0.85, 230.0],
	"candy": [false, 105.0, 0.85, 230.0], "bubble": [false, 70.0, 1.1, 230.0], "line": [false, 145.0, 0.6, 340.0],
	"lightning": [false, 145.0, 0.6, 340.0], "phoenix": [false, 105.0, 0.85, 230.0], "lava": [true, 145.0, 0.85, 70.0],
	"cyber": [false, 105.0, 0.85, 230.0], "crystal": [true, 70.0, 1.1, 70.0], "chest": [true, 105.0, 1.1, 70.0],
	"space": [false, 145.0, 0.85, 340.0], "hiding": [true, 70.0, 1.1, 70.0], "headless": [true, 145.0, 0.85, 70.0],
	"shell": [true, 105.0, 1.1, 70.0],
}
const DEFAULT_STAT := [true, 105.0, 0.85, 70.0]
const LEFT_DEMO := ["stone", "basic", "lightning"]
const RIGHT_DEMO := ["diamond", "ninja", "ghost"]

# 普攻表 (1:1 复用): id → [scale, hits]
const BASIC_ATK := {
	"basic": [0.7, 2], "stone": [0.7, 2], "bamboo": [0.21, 3], "angel": [1.4, 3],
	"ice": [0.5, 6], "ninja": [1.0, 1], "two_head": [1.0, 1], "ghost": [0.65, 1],
	"diamond": [0.7, 1], "fortune": [0.5, 2], "dice": [0.9, 1], "rainbow": [0.7, 2],
	"gambler": [0.45, 3], "hunter": [0.55, 3], "pirate": [0.35, 4], "candy": [1.1, 1],
	"bubble": [0.5, 3], "line": [0.5, 3], "lightning": [1.15, 5], "phoenix": [0.9, 1],
	"lava": [1.0, 1], "cyber": [0.15, 5], "crystal": [0.5, 2], "chest": [1.5, 3],
	"space": [0.4, 3], "hiding": [1.0, 1], "headless": [0.65, 2], "shell": [0.6, 2],
}
const DEFAULT_BASIC := [1.0, 1]

# ============================================================================
#  2.5D 坐标 / 渲染常量
# ============================================================================
const AVATAR_DIR := "res://assets/sprites/avatars/"   # 头像兜底 (全身图缺失才退回)
const SPRITE_DIR := "res://assets/sprites/"           # pets.json img 相对此根
const TARGET_BODY_H := 2.3                 # 立绘目标世界高度 (米) — 全身图按帧高归一到此, 龟 ≈ 2.3m
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
var _settled := false

var _cam: Camera3D
var _ui_layer: CanvasLayer                # 血条/龟能 overlay + 标题 + 结算 (贴在 3D 之上)
var _world: Node3D                        # 3D 内容挂载点 (SubViewport 内)
var _sub: SubViewport
var _projectiles: Array = []              # 飞行中的 3D 投射物 {node, from, to, tgt, dmg, magic, src, t, dur}

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
	var left := _resolve_left()
	var right := _resolve_right()
	for i in range(left.size()):
		# XZ 落点: 左队靠左 (ARENA 内), 三龟纵向分布. 与 2D _spawn_teams 同口径像素坐标.
		var pos := Vector2(ARENA.position.x + 150, ARENA.position.y + 100 + i * 160)
		_units.append(_make_unit(str(left[i]), "left", pos))
	for i in range(right.size()):
		var pos := Vector2(ARENA.end.x - 150, ARENA.position.y + 100 + i * 160)
		_units.append(_make_unit(str(right[i]), "right", pos))
	_inject_equipment()       # 装备注入 (玩家队读 persistent_equipped; demo队塞测试装备) — 须在被动之前
	_apply_spawn_passives()   # 登场被动 (开战即生效: 忍术暴击/怨灵诅咒/冰寒减攻/召唤等)
	_eq_apply_all_stats()     # 开战: 全装备纯属性 / 永久 flag 加到携带者 (spawn 被动之后, 不被覆盖)

func _resolve_left() -> Array:
	var ldr := _season_leaders()
	return ldr if ldr.size() >= 1 else LEFT_DEMO.duplicate()

func _resolve_right() -> Array:
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
	var hp := float(d.get("hp", 450)) * HP_MULT

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
	contact.modulate = Color(1, 1, 1, CONTACT_BASE_A)
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
	ring.modulate = Color(1, 1, 1, 0.7)
	ring.position = _world_pos(pos, 0.015)
	_world.add_child(ring)

	# --- HP / 龟能 overlay (CanvasLayer 上, 每帧 unproject 定位) ---
	var bar := _make_status_bar(side, _unit_level(side))
	_ui_layer.add_child(bar["root"])

	return {
		"id": id, "name": str(d.get("name", id)), "rarity": str(d.get("rarity", "C")), "side": side,
		"pos": pos, "vel": Vector2.ZERO,
		"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
		"hp": hp, "maxHp": hp,
		"atk": float(d.get("atk", 40)), "def": float(d.get("def", 12)), "mr": float(d.get("mr", 12)),
		"base_atk": float(d.get("atk", 40)), "base_def": float(d.get("def", 12)), "base_mr": float(d.get("mr", 12)),
		"crit": float(d.get("crit", 0.25)), "crit_dmg": 1.5, "pierce": 0.0, "lifesteal": 0.0,
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
func _make_blob_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.58))
	grad.add_point(0.45, Color(0, 0, 0, 0.42))
	grad.add_point(0.78, Color(0, 0, 0, 0.12))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128; gt.height = 128
	return gt

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
func _make_ring_texture(col: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 0.0))
	grad.add_point(0.7, Color(col.r, col.g, col.b, 0.0))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.5))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 96; gt.height = 96
	return gt

# 状态条: 复用回合制版 HpBar 组件 (自定义 _draw: 黑边/暗红槽/玻璃高光/逐行渐变填充/护盾段/受击红trail+白闪/刻度).
#   + 左侧等级牌 (棕底金字 Panel, 回合制 turtle-hud 同款) + 下方龟能条 (实时资源, HpBar 不画).
#   level: 玩家龟读 GameState.season_level; 召唤体无牌. 返回各组件引用供 _update_overlay 刷新.
const BAR_W := 88.0      # HpBar 宽 (turtle-hud BAR_W)
const BAR_H := 5.0       # HpBar 高
func _make_status_bar(side: String, level: int = 0) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(BAR_W, 22)
	root.size = Vector2(BAR_W, 22)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# --- 等级牌 (棕底金字, 在血条左侧) ---
	var lv_badge: Panel = null
	if level > 0:
		var badge_fs := 10
		lv_badge = Panel.new()
		var lv_sb := StyleBoxFlat.new()
		lv_sb.bg_color = Color("#2a1d12")           # 棕色 (turtle-hud)
		lv_sb.set_border_width_all(1)
		lv_sb.border_color = Color(0, 0, 0, 0.55)
		lv_sb.set_corner_radius_all(0)
		lv_badge.add_theme_stylebox_override("panel", lv_sb)
		lv_badge.custom_minimum_size = Vector2(badge_fs + 12, BAR_H + 6)
		lv_badge.size = Vector2(badge_fs + 12, BAR_H + 6)
		lv_badge.position = Vector2(-(badge_fs + 14), 6.0)
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
		if not _over:
			_t += delta
			for u in _units.duplicate():
				if not u["alive"]:
					continue
				_tick_unit(u, delta)
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

	var tgt = _acquire_target(u)
	if tgt == null:
		# 无敌 → 龟能照回 (但没目标不放技)
		_regen_energy(u, delta, stunned, null)
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	var dist := to_t.length()
	var rng: float = u["atk_range"]

	if not stunned:
		var spd: float = u["move_spd"] * (0.6 if _t < u["slow_until"] else 1.0)
		# 移动: 近战追到射程 / 远程维持射程并风筝 (1:1 复用 2D 逻辑); no_move 召唤体(糖果炸弹/海盗船)定点
		if not u.get("no_move", false):
			var intent := Vector2.ZERO
			if dist > rng:
				intent = to_t.normalized()
			elif not u["melee"] and dist < rng * 0.7:
				intent = -to_t.normalized()
			elif u["melee"] and dist > rng * 0.6:
				intent = to_t.normalized() * 0.45   # 近战射程内留点向心拉力, 分离把队伍摊成弧(非推飞)
			intent += _separation(u)   # 分离力始终全开(不再到射程砍0.25) → 近战散开成弧, 不扎堆叠一起
			if intent.length() > 0.01:
				# 用合力大小调速(封顶满速): 力相互抵消时缓停, 不再永远满速冲 → 摊稳不抖
				u["vel"] = intent.limit_length(1.0) * spd
				u["pos"] += u["vel"] * delta
				u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
				u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
		# 普攻 (按攻速计时; no_basic 召唤体只靠周期特殊技/掉血)
		if dist <= rng and not u.get("no_basic", false):
			u["atk_cd"] -= delta
			if u["atk_cd"] <= 0.0:
				_basic_attack(u, tgt)
				u["atk_cd"] = u["atk_interval"]

	_regen_energy(u, delta, stunned, tgt)

# 龟能回满 → 放主动 (麻痹时不回, 体现控制价值; 召唤体/被动选项 永不放主动)
func _regen_energy(u: Dictionary, delta: float, stunned: bool, tgt) -> void:
	# Botworld式: 逐技各自固定时间冷却(走时间, 与打没打中无关); 冷却好且有目标→放
	if _is_passive_pick(u):
		return
	var cds: Dictionary = u["skill_cd"]
	if cds.is_empty():                                   # 懒初始化: 各技起始冷却错峰(别一开局全放)
		for s in u.get("active_skills", []):
			cds[str(s)] = _skill_cd(str(s)) * randf_range(0.25, 0.7)
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - delta)        # 冷却走时间 (麻痹也走, 只是放不出→下面gate)
	if stunned or tgt == null:
		return
	_cast_active(u, tgt)

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
func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	_anticipate(u)                  # Phase4: 普攻预备(缩)+挥出(伸) 前后摇形变
	_play_action(u, "attack")       # 有动作帧的龟(basic/ghost/ninja)播普攻动画, 其余靠 juice 形变
	var spec: Array = BASIC_ATK.get(u["id"], DEFAULT_BASIC)
	var scale: float = spec[0]
	var hits: int = spec[1]
	# 复杂普攻特判 (基于当前金币/暴击/HP)
	match u["id"]:
		"fortune":  scale = 0.5 + 0.06 * u["gold"]                       # 币越多越疼
		"dice":     scale = 0.9 + u["crit"] * 0.55                       # 暴击率加成
		"space":    scale = 0.4 + 0.06 * (u["hp"] / 100.0)              # 随当前HP (近似)
		"lava":
			if u.get("volcano", false):                                  # 火山形态: 烈焰重击式平A (更重·单段)
				scale = 1.6; hits = 1
		"crystal":  pass
	var per := _atk_dmg(u, scale, tgt)
	for i in range(hits):
		if not tgt["alive"]:
			break
		if u["melee"]:
			_apply_damage_from(u, tgt, per, Color("#ffe08a"))
			if i == 0:
				_flash(tgt); _melee_lunge(u, tgt)
		else:
			_fire_bolt_from(u, tgt, per, Color("#ffe08a"))
	# 普攻 on-hit 被动钩子 (墨迹/电击/结晶叠层 + 猎杀斩杀 等)
	_on_basic_hit(u, tgt)

# 伤害公式 (1:1 复用 2D _atk_dmg): base×scale ×暴击 ×(100/(100+resist-pierce))
func _atk_dmg(u: Dictionary, scale: float, tgt: Dictionary, magic: bool = false) -> int:
	var base: float = u["atk"] * scale
	if u.get("_vs_fire_bonus", 0.0) > 0.0 and (str(tgt["id"]) == "lava" or str(tgt["id"]) == "phoenix"):
		base *= 1.0 + float(u["_vs_fire_bonus"])   # 寒冰免疫(iceBurnImmune): 对熔岩/凤凰 +40%
	_last_atk_crit = randf() < u["crit"]      # §AUDIO: 记最近一次是否暴击 (供 _apply_damage_from 选暴击音)
	if _last_atk_crit:
		base *= u["crit_dmg"]
	var resist: float = float(tgt["mr"]) if magic else float(tgt["def"])
	resist = maxf(0.0, resist - u["pierce"])
	return maxi(1, int(round(base * (100.0 / (100.0 + resist)))))

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

func _fire_bolt_from(src, tgt: Dictionary, dmg: int, col: Color, from = null) -> void:
	var start2d: Vector2 = from if from != null else (src["pos"] if src != null else tgt["pos"])
	var p := Sprite3D.new()
	p.texture = _make_bolt_texture(col)
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.pixel_size = 0.014
	p.shaded = false
	p.transparent = true
	var world_from := _world_pos(start2d, 1.0)   # 从胸口高度出
	p.position = world_from
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "dmg": dmg, "col": col,
		"src": src, "t": 0.0, "dur": 0.16,
	})

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
			continue
		keep.append(pr)
	_projectiles = keep

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
		_float_text(u["pos"] + Vector2(0, -40), "闪避", Color("#cfe6ff"))
		_eq_on_dodge(u)          # on-dodge 钩子 (幽灵墨鱼046: 闪避→永久护盾)
		return
	# 靶向器055: 被标记目标受伤 +20%
	if _t < u.get("eq_marked_until", 0.0):
		dmg = int(dmg * 1.2)
	var was_crit := _last_atk_crit          # §AUDIO: 先抓暴击态 (下方 hook 里嵌套 _atk_dmg 会改写它)
	var d := float(dmg)
	var shield_before: float = u["shield"]
	if not raw and u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	u["hp"] = maxf(0.0, u["hp"] - d)
	_float_text(u["pos"] + Vector2(randf_range(-26.0, 26.0), -40.0 + randf_range(-10.0, 6.0)), str(dmg), col)   # 抖开: 多段/AOE 出伤飘字不重叠成糊团
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
		src["rage"] = minf(RAGE_MAX, src["rage"] + float(dmg) * 0.25)
	if u["id"] == "lava":
		u["rage"] = minf(RAGE_MAX, u["rage"] + float(dmg) * 0.20)
	# 星能 (星际造伤62%)
	if src["id"] == "space":
		src["star_energy"] = minf(src["maxHp"] * 0.40, src["star_energy"] + float(dmg) * 0.62)
	# 储能 (龟壳受伤转储能, 上限50%最大HP)
	if u["id"] == "shell":
		u["store_energy"] = minf(u["maxHp"] * 0.50, u["store_energy"] + float(dmg))
	# 双头坚韧 (常驻被动): 每受一段攻击 +1护甲+1魔抗 (各上限20)
	if u["id"] == "two_head":
		var th: int = int(u.get("two_tough", 0))
		if th < 20:
			th += 1; u["two_tough"] = th
			u["base_def"] += 1.0; u["base_mr"] += 1.0; _recalc_stats(u)
	# 石头龟坚壁: 受伤反弹 (5%+1%DEF+0.5%MR)
	if u["id"] == "stone" and src["alive"] and src["side"] != u["side"]:
		var reflect: float = float(dmg) * 0.05 + u["def"] * 0.01 + u["mr"] * 0.005
		if reflect >= 1.0:
			_raw_lose(src, reflect)
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
		var pct: float = 0.30 if u["id"] == "phoenix" else 0.25
		u["hp"] = u["maxHp"] * pct
		u["dots"] = []
		u["dot_stacks"] = {}
		_sfx_simple("rebirth")              # §AUDIO: 首死复活音 (天使圣光/凤凰涅槃, 低频不节流)
		_float_text(u["pos"] + Vector2(0, -64), "复活!", Color("#ffd93d"))
		if u["id"] == "phoenix":                          # 涅槃: 对全体敌灼烧
			for o in _enemies_of(u):
				_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
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
func _float_text(pos2d: Vector2, text: String, col: Color) -> void:
	if _cam == null:
		return
	# 2D 版 pos2d 含头顶像素偏移; 3D 里统一抬到 ~2.2 米头顶 (billboard 头顶居中, x 偏移忽略)
	var head := _world_pos(pos2d, 2.2)
	if _cam.is_position_behind(head):
		return
	var screen: Vector2 = _cam.unproject_position(head)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	l.position = screen
	_ui_layer.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", screen.y - 28.0, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(l.queue_free)

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

# ═══ 选3 多技能轮转 (用户2026-06-28拍板: 保留选3, 让3技在战斗真生效) ═══
# 被动型技 (开局生效, 不进主动轮转; 在 _apply_spawn_passives 里按是否被选施加)
const PASSIVE_SKILL_TYPES := {"iceBurnImmune": true}

# loadout(选3) 里所有"非普攻"技 type (physical/magic 是普攻=自动, 排除)
func _chosen_skill_types(id: String, use_loadout: bool) -> Array:
	var d: Dictionary = _data_by_id.get(id, {})
	var pool: Array = d.get("skillPool", [])
	var ds: Array = (GameState.loadouts.get(id, d.get("defaultSkills", [0, 1, 2])) if use_loadout else d.get("defaultSkills", [0, 1, 2]))
	var out: Array = []
	for i in ds:
		var ii := int(i)
		if ii < 0 or ii >= pool.size():
			continue
		var t := str((pool[ii] as Dictionary).get("type", ""))
		if t == "" or t == "physical" or t == "magic":
			continue
		out.append(t)
	return out

# 进主动轮转的技 (= 选中非普攻技 减去 被动型)
func _resolve_active_skills(id: String, use_loadout: bool) -> Array:
	var out: Array = []
	for t in _chosen_skill_types(id, use_loadout):
		if not PASSIVE_SKILL_TYPES.has(t):
			out.append(t)
	return out

# 实装了的技能 type 集 (与 _do_skill 的 match 保持同步; 用于轮转跳过未实装的, 不浪费龟能/不空放 juice)
const _IMPL_SKILLS := {
	# 签名招 (既有 _sk_* 实装, 按技能 type 分派)
	"turtleShieldBash": true, "bambooHeal": true, "angelBless": true, "iceFrost": true,
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
}

# 各技 龟能 cost (∝ 技能强度; 便宜→放得勤, 贵→攒久才放). 解决"龟盾≠气波 不能同冷却".
#   档位: 轻盾/治/buff~70 · 普通伤害/控~95 · 全体/多段/强~120-140 · 变身/梭哈/大招~150-170. 缺省 95. (F5调)
const SKILL_COST := {
	# 签名招
	"turtleShieldBash": 70.0, "bambooHeal": 90.0, "angelBless": 75.0, "iceFrost": 120.0,
	"ninjaImpact": 95.0, "ghostStorm": 95.0, "diamondFortify": 70.0, "diceAllIn": 120.0,
	"gamblerBet": 100.0, "hunterStealth": 90.0, "pirateCannonBarrage": 130.0, "bubbleShield": 120.0,
	"lineLink": 70.0, "lightningSurgeBuff": 90.0, "phoenixShield": 75.0, "twoHeadFear": 95.0,
	"fortuneDice": 70.0, "crystalBarrier": 75.0, "chestCount": 90.0, "starMeteor": 130.0,
	"twoHeadSwitch": 150.0, "lavaSurge": 150.0, "cyberBeam": 100.0, "hidingDefend": 70.0, "shellAbsorb": 100.0,
	# 通用
	"shield": 70.0, "heal": 70.0,
	# 数据驱动伤害
	"basicBarrage": 140.0, "bambooLeaf": 90.0, "bambooSmack": 75.0, "angelEquality": 125.0,
	"iceSpike": 120.0, "ninjaShuriken": 95.0, "ninjaBomb": 100.0, "twoHeadMagicWave": 100.0,
	"ghostTouch": 95.0, "ghostPhantom": 95.0, "diamondCollide": 95.0, "fortuneStrike": 90.0,
	"diceAttack": 95.0, "rainbowStorm": 125.0, "gamblerCards": 100.0, "gamblerDraw": 80.0,
	"hunterShot": 100.0, "hunterBarrage": 135.0, "candyBarrage": 115.0, "lineSketch": 90.0,
	"lightningStrike": 95.0, "lightningBarrage": 140.0, "phoenixBurn": 90.0, "phoenixScald": 80.0,
	"lavaBolt": 90.0, "lavaQuake": 115.0, "crystalSpike": 90.0, "crystalBurst": 115.0,
	"chestStorm": 115.0, "starBeam": 70.0, "soulReap": 120.0, "shellStrike": 80.0,
	# Batch2 特殊
	"chestSmash": 120.0, "fortuneAllIn": 170.0, "starWormhole": 150.0, "lineFinish": 95.0,
	"cyberDeploy": 135.0, "bubbleBind": 100.0, "hidingCommand": 85.0, "shellCopy": 140.0, "diceFate": 90.0,
}

func _skill_cost(stype: String) -> float:
	return float(SKILL_COST.get(stype, SKILL_COST_DEFAULT))

# 该技冷却秒数 = 强度档 × 系数 (龟盾~5s · 普通~7s · 弹幕~10s · 大招~13s, 对齐 Botworld)
func _skill_cd(stype: String) -> float:
	return _skill_cost(stype) * SKILL_CD_FACTOR

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
func _cast_active(u: Dictionary, tgt: Dictionary) -> void:
	if _t < float(u.get("skill_gcd_until", 0.0)):     # 连放最小间隔(防多技同帧爆)
		return
	var skills: Array = u.get("active_skills", [])
	if skills.is_empty():
		return
	var cds: Dictionary = u["skill_cd"]
	var best := ""
	var best_cost := -1.0
	for s in skills:
		var st := str(s)
		if not _IMPL_SKILLS.has(st):
			continue
		if st == "fortuneAllIn" and u.get("allin_used", false):
			continue
		if float(cds.get(st, 0.0)) > 0.0:             # 还在冷却
			continue
		var c := _skill_cost(st)
		if c > best_cost:                             # 取强度最高的就绪技 (大招优先)
			best_cost = c; best = st
	if best == "":
		return                                        # 没有就绪的技 → 继续普攻等冷却
	if _cast_skill(u, tgt, best):
		cds[best] = _skill_cd(best)                   # 重置该技冷却
		u["skill_gcd_until"] = _t + SKILL_GCD
		_eq_on_cast(u, tgt)
	else:
		cds[best] = _skill_cd(best)                   # 放失败(如梭哈已用)→也置冷却避免每帧重试

# 放单个技 (按 type): 实装→juice+VFX+效果 返 true; 未实装→返 false (轮转跳过, 不空放).
func _cast_skill(u: Dictionary, tgt: Dictionary, stype: String) -> bool:
	if not _IMPL_SKILLS.has(stype):
		return false
	if stype == "fortuneAllIn" and u.get("allin_used", false):
		return false                                  # 梭哈一场限一次, 用过则轮转跳过不空放
	_anticipate(u)                  # 放大招前预备(缩)→挥出(伸) 形变
	_shake(JUICE_SHAKE_HEAVY)       # 大招释放 = 轻震屏
	# §SKILLVFX: 逐技 type→icon 真贴图(pets.json skillPool[].icon); 无图回退龟签名 VFX, 再无则静默(留 _skill_ring/飘字)
	var on_tgt: bool = _COPYABLE_SKILLS.has(stype) or _SKILL_VFX_ON_TARGET.get(u["id"], false)
	var vfx_at: Vector2 = tgt["pos"] if (on_tgt and tgt != null and tgt != u) else u["pos"]
	var vfx_name: String = _skill_vfx_name(stype)
	_play_skill_vfx(vfx_name if vfx_name != "" else str(u["id"]), vfx_at, 1.3)
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
		"iceFrost":             _sk_ice_frost(u)
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
		"lavaSurge":            _sk_lava_cast(u, tgt)
		"cyberBeam":            _sk_cyber_cannon(u, tgt)
		"hidingDefend":         _sk_hiding_defend(u)
		"shellAbsorb":          _sk_shell_absorb(u, tgt)
		# ── 通用 (多龟共享 type) ──
		"shield":               _sk_gen_shield(u)
		"heal":                 _sk_gen_heal(u)
		# ── 数据驱动伤害技 (系数取自 detail 公式; N=物理 M=魔法 T=真实) ──
		"basicBarrage":         _sk_dmg(u, tgt, {"phys": 3.1, "hits": 10, "name": "弹幕!", "color": Color("#ffe08a")})
		"bambooLeaf":           _sk_dmg(u, tgt, {"phys": 0.63, "hp": 0.18, "hits": 3, "name": "竹叶斩!", "color": Color("#39d353")})
		"bambooSmack":          _sk_dmg(u, tgt, {"phys": 1.0, "hits": 1, "rider": "atkdn", "name": "竹击!", "color": Color("#39d353")})
		"angelEquality":        _sk_dmg(u, tgt, {"phys": 2.0, "true": 0.5, "hits": 2, "name": "平等审判!", "color": Color("#ffe9a8")})
		"iceSpike":             _sk_dmg(u, tgt, {"phys": 0.7, "magic": 0.7, "hits": 6, "rider": "slow", "name": "冰锥!", "color": Color("#9be7ff")})
		"ninjaShuriken":        _sk_dmg(u, tgt, {"phys": 0.96, "true": 0.64, "hits": 1, "name": "飞镖!", "color": Color("#cfd8e8")})
		"ninjaBomb":            _sk_dmg(u, tgt, {"phys": 1.1, "hits": 1, "aoe": true, "name": "烟雾弹!", "color": Color("#b0b0c0")})
		"twoHeadMagicWave":     _sk_dmg(u, tgt, {"phys": 0.8, "true": 0.8, "hits": 4, "name": "魔法波!", "color": Color("#c0a0ff")})
		"ghostTouch":           _sk_dmg(u, tgt, {"phys": 0.4, "true": 0.9, "hits": 1, "rider": "curse", "name": "幽灵之触!", "color": Color("#c77dff")})
		"ghostPhantom":         _sk_dmg(u, tgt, {"magic": 1.5, "hits": 1, "name": "幻影!", "color": Color("#c77dff")})
		"diamondCollide":       _sk_dmg(u, tgt, {"phys": 0.8, "mr": 0.9, "hits": 1, "rider": "stun", "name": "撞击!", "color": Color("#9bdcff")})
		"fortuneStrike":        _sk_dmg(u, tgt, {"phys": 1.0, "hits": 2, "name": "财运一击!", "color": Color("#ffd93d")})
		"diceAttack":           _sk_dmg(u, tgt, {"phys": 0.9, "hits": 3, "name": "骰子攻击!", "color": Color("#ffe08a")})
		"rainbowStorm":         _sk_dmg(u, tgt, {"magic": 0.8, "true": 0.4, "hits": 4, "aoe": true, "name": "棱镜风暴!", "color": Color("#ff8ad8")})
		"gamblerCards":         _sk_dmg(u, tgt, {"phys": 1.35, "hits": 3, "name": "发牌!", "color": Color("#ffd93d")})
		"gamblerDraw":          _sk_dmg(u, tgt, {"phys": 1.0, "hits": 2, "name": "抽牌!", "color": Color("#ffd93d")})
		"hunterShot":           _sk_dmg(u, tgt, {"phys": 1.65, "hits": 3, "name": "精准射击!", "color": Color("#a8ffb0")})
		"hunterBarrage":        _sk_dmg(u, tgt, {"true": 2.4, "hits": 10, "name": "狩猎弹幕!", "color": Color("#a8ffb0")})
		"candyBarrage":         _sk_dmg(u, tgt, {"phys": 1.0, "hits": 4, "aoe": true, "name": "糖果弹幕!", "color": Color("#ff9ed6")})
		"lineSketch":           _sk_dmg(u, tgt, {"phys": 1.5, "hits": 3, "name": "速写!", "color": Color("#dddddd")})
		"lightningStrike":      _sk_dmg(u, tgt, {"magic": 1.15, "hits": 5, "name": "闪电打击!", "color": Color("#7ee8ff")})
		"lightningBarrage":     _sk_dmg(u, tgt, {"magic": 2.2, "hits": 20, "name": "雷暴!", "color": Color("#7ee8ff")})
		"phoenixBurn":          _sk_dmg(u, tgt, {"magic": 0.9, "hits": 1, "rider": "burn", "name": "灼焰!", "color": Color("#ff7a3c")})
		"phoenixScald":         _sk_dmg(u, tgt, {"magic": 0.7, "hits": 1, "rider": "burn", "name": "灼烧!", "color": Color("#ff7a3c")})
		"lavaBolt":             _sk_dmg(u, tgt, {"magic": 0.9, "hits": 1, "rider": "burn", "name": "熔岩弹!", "color": Color("#ff7a3c")})
		"lavaQuake":            _sk_dmg(u, tgt, {"magic": 0.6, "hits": 1, "aoe": true, "rider": "slow", "name": "地震!", "color": Color("#ff9d5c")})
		"crystalSpike":         _sk_dmg(u, tgt, {"magic": 1.0, "hits": 2, "name": "水晶刺!", "color": Color("#9bdcff")})
		"crystalBurst":         _sk_dmg(u, tgt, {"magic": 0.7, "true": 0.1, "hits": 3, "aoe": true, "name": "水晶爆!", "color": Color("#9bdcff")})
		"chestStorm":           _sk_dmg(u, tgt, {"phys": 1.0, "hits": 5, "aoe": true, "name": "宝箱风暴!", "color": Color("#ffd93d")})
		"starBeam":             _sk_dmg(u, tgt, {"magic": 0.4, "hits": 3, "name": "星光束!", "color": Color("#c0a0ff")})
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
	_float_text(u["pos"] + Vector2(0, -64), "龟盾!", Color("#ffd93d"))
	var lost: float = (tgt["maxHp"] - tgt["hp"]) * 0.20
	var raw: float = u["atk"] * 0.7
	var dmg := _atk_dmg(u, 0.7, tgt) + int(lost)
	_apply_damage_from(u, tgt, dmg, Color("#ffe08a"))
	_grant_shield(u, (raw + lost) * 0.80)
	_knockback(u, tgt, 60.0)

func _sk_stone_armor(u: Dictionary) -> void:                     # 石头龟·岩石护甲 ✅
	_float_text(u["pos"] + Vector2(0, -64), "岩石护甲!", Color("#c9a36b"))
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.24 + o["maxHp"] * 0.05)

func _sk_bamboo_heal(u: Dictionary) -> void:                     # 竹叶龟·自然恢复 ✅
	var allies := _allies_of(u, false)
	if allies.is_empty():
		_heal(u, u["maxHp"] * 0.15)
	else:
		_heal(u, u["maxHp"] * 0.10)
		for o in allies:
			_grant_shield(o, o["maxHp"] * 0.12)
	_float_text(u["pos"] + Vector2(0, -64), "自然恢复!", Color("#39d353"))

func _sk_angel_bless(u: Dictionary) -> void:                     # 天使龟·祝福 ✅
	var ally = _lowest_hp_ally(u)
	if ally == null:
		ally = u
	_grant_shield(ally, u["atk"] * 1.2)
	_buff(ally, "def", 0.2, true)
	_buff(ally, "mr", 0.2, true)
	_float_text(ally["pos"] + Vector2(0, -64), "祝福!", Color("#ffe9a8"))

func _sk_ice_frost(u: Dictionary) -> void:                       # 寒冰龟·冰霜 ✅
	_float_text(u["pos"] + Vector2(0, -64), "冰霜!", Color("#9be7ff"))
	for o in _enemies_of(u):
		_buff(o, "mr", -0.25, true)
		for i in range(10):
			_apply_damage_from(u, o, _atk_dmg(u, 0.1, o, true), Color("#bfe9ff"))
		_skill_ring(o["pos"], Color(0.6, 0.9, 1.0, 0.5), 50.0)

func _sk_ninja_impact(u: Dictionary, tgt: Dictionary) -> void:   # 忍者龟·冲击 ✅
	_float_text(u["pos"] + Vector2(0, -64), "冲击!", Color("#9be7ff"))
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
	_float_text(u["pos"] + Vector2(0, -64), "灵魂风暴!", Color("#c77dff"))
	var cursed: bool = _has_dot(tgt, "curse")
	if cursed:
		_apply_damage_from(u, tgt, _atk_dmg(u, 2.5, tgt, true), Color("#e0b0ff"))
	else:
		for i in range(2):
			_apply_damage_from(u, tgt, _atk_dmg(u, 1.25, tgt, true), Color("#c77dff"))
		_add_dot(tgt, "curse", tgt["maxHp"] * 0.05, BUFF_SEC)

func _sk_diamond_unbreak(u: Dictionary) -> void:                 # 钻石龟·坚不可摧 ✅
	_float_text(u["pos"] + Vector2(0, -64), "坚不可摧!", Color("#9bdcff"))
	_grant_shield(u, u["maxHp"] * 0.20)
	_buff(u, "def", 0.2, true); _buff(u, "mr", 0.2, true)

func _sk_dice_allin(u: Dictionary) -> void:                      # 骰子龟·孤注一掷 ✅
	_float_text(u["pos"] + Vector2(0, -64), "孤注一掷!", Color("#ffd93d"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 1.2, o), Color("#ffe08a"), 0.30)

func _sk_rainbow_shield(u: Dictionary) -> void:                  # 彩虹龟·棱镜护盾 ✅
	_float_text(u["pos"] + Vector2(0, -64), "棱镜护盾!", Color("#ff8ad8"))
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.65)

func _sk_gambler_wild(u: Dictionary, tgt: Dictionary) -> void:   # 赌神龟·万能牌 ✅
	_float_text(u["pos"] + Vector2(0, -64), "万能牌!", Color("#ffd93d"))
	for i in range(2):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#ffe08a"))
	_grant_shield(u, u["atk"] * 0.25)
	_heal(u, u["maxHp"] * 0.05)
	_buff(tgt, "atk", -0.15, true)

func _sk_hunter_hide(u: Dictionary) -> void:                     # 猎人龟·隐蔽 ✅
	_float_text(u["pos"] + Vector2(0, -64), "隐蔽!", Color("#a8ffb0"))
	var tgt = _nearest_enemy(u)
	if tgt != null:
		_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ffe08a"))
	_buff(u, "dodge", 0.25, true)
	_grant_shield(u, u["atk"] * 0.6)

func _sk_pirate_volley(u: Dictionary) -> void:                   # 海盗龟·火炮齐射 ✅
	_float_text(u["pos"] + Vector2(0, -64), "火炮齐射!", Color("#ffb05c"))
	for o in _enemies_of(u):
		for i in range(6):
			_apply_damage_from(u, o, _atk_dmg(u, 0.17, o) + int(o["maxHp"] * 0.017), Color("#ffd07a"))

func _sk_bubble_shield(u: Dictionary, _tgt: Dictionary) -> void: # 泡泡龟·泡泡盾 ✅(简化:无延迟爆裂)
	var ally = _lowest_hp_ally(u)
	if ally == null: ally = u
	_grant_shield(ally, u["atk"] * 1.8)
	_float_text(ally["pos"] + Vector2(0, -64), "泡泡盾!", Color("#aef1ff"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 2.0, o, true), Color("#cdebff"))

func _sk_line_link(u: Dictionary) -> void:                       # 线条龟·连笔 ✅
	_float_text(u["pos"] + Vector2(0, -64), "连笔!", Color("#cccccc"))
	var picked := 0
	for o in _enemies_of(u):
		if picked >= 2: break
		_apply_damage_from(u, o, _atk_dmg(u, 0.8, o), Color("#dddddd"))
		_add_stack(o, "ink", 1, 5)
		picked += 1

func _sk_lightning_surge(u: Dictionary, tgt: Dictionary) -> void: # 闪电龟·涌动 ✅
	_float_text(u["pos"] + Vector2(0, -64), "涌动!", Color("#7ee8ff"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.23, tgt, true), Color("#bff0ff"))
	_add_stack(tgt, "electric", 2, 6)
	_buff(u, "atk", 0.5, true)

func _sk_phoenix_lavashield(u: Dictionary) -> void:              # 凤凰龟·熔岩盾 ✅(反击留TODO)
	_float_text(u["pos"] + Vector2(0, -64), "熔岩盾!", Color("#ff7a33"))
	_grant_shield(u, u["atk"] * 0.75)

func _sk_headless_fear(u: Dictionary, tgt: Dictionary) -> void:  # 无头龟·恐吓 ✅
	_float_text(u["pos"] + Vector2(0, -64), "恐吓!", Color("#a0a0ff"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ffe08a"))
	_buff(tgt, "atk", -0.20, true)

func _sk_fortune_dice(u: Dictionary) -> void:                    # 财神龟·骰子 ✅
	_float_text(u["pos"] + Vector2(0, -64), "骰子+金币!", Color("#ffd93d"))
	u["gold"] += randi_range(2, 6)
	_heal(u, u["maxHp"] * 0.08)

func _sk_crystal_bulwark(u: Dictionary) -> void:                 # 水晶龟·水晶壁垒 ✅
	_float_text(u["pos"] + Vector2(0, -64), "水晶壁垒!", Color("#c0a8ff"))
	_grant_shield(u, u["atk"] * 0.9)
	for o in _allies_of(u):
		_buff(o, "def", 0.15, true); _buff(o, "mr", 0.15, true)

func _sk_chest_inventory(u: Dictionary) -> void:                 # 宝箱龟·清点财宝 ✅
	_float_text(u["pos"] + Vector2(0, -64), "清点财宝!", Color("#ffcf5c"))
	_heal(u, u["maxHp"] * 0.05)
	var bonus: float = 1.0 + minf(u["dmg_dealt"] / 2000.0, 1.0)
	_grant_shield(u, u["atk"] * 0.6 * bonus)

func _sk_space_meteor(u: Dictionary) -> void:                    # 星际龟·流星暴击 ✅
	_float_text(u["pos"] + Vector2(0, -64), "流星暴击!", Color("#b08cff"))
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
	_float_text(u["pos"] + Vector2(0, -64), "焦糖铠!", Color("#ffb0d0"))
	_grant_shield(u, u["atk"] * 0.8)
	_heal(u, u["maxHp"] * 0.10)

# 双头龟·选一套 (demo 默认套1). 每次攒满龟能 → 切形态 + 放新形态这套招.
func _sk_two_head(u: Dictionary, tgt: Dictionary) -> void:       # 双头龟 ✅ 选一套+切换形态
	var set_id: String = u.get("two_set", "1")
	u["two_form"] = "ranged" if u.get("two_form", "melee") == "melee" else "melee"
	var to_ranged: bool = u["two_form"] == "ranged"
	u["melee"] = not to_ranged
	u["atk_range"] = 300.0 if to_ranged else 70.0
	u["atk_interval"] = 1.1 if not to_ranged else 0.8
	if not to_ranged:
		match set_id:
			"1", "3":
				_float_text(u["pos"] + Vector2(0, -64), "近战·锤击!", Color("#ffb05c"))
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.4, tgt), Color("#ffb05c"))
				_grant_shield(u, u["atk"] * 0.5)
			"2":
				_float_text(u["pos"] + Vector2(0, -64), "近战·吸收!", Color("#ffb05c"))
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.3, tgt), Color("#ffb05c"), 0.35)
	else:
		match set_id:
			"1":
				_float_text(u["pos"] + Vector2(0, -64), "远程·精神干扰!", Color("#b0c0ff"))
				tgt["shield"] *= 0.5
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt, true), Color("#c0d0ff"))
				_buff(tgt, "atk", -0.20, true)
			"2":
				_float_text(u["pos"] + Vector2(0, -64), "远程·魔法波!", Color("#b0c0ff"))
				for i in range(4):
					if not tgt["alive"]: break
					_apply_damage_from(u, tgt, _atk_dmg(u, 0.6, tgt, i % 2 == 0), Color("#c0d0ff"))
			"3":
				_float_text(u["pos"] + Vector2(0, -64), "远程·灵能冲击!", Color("#b0c0ff"))
				for o in _enemies_of(u):
					_apply_damage_from(u, o, _atk_dmg(u, 0.5, o, true) + int(o["maxHp"] * 0.15), Color("#c0d0ff"))

# 熔岩龟·选一套 (demo 默认套A). 龟能满→放【当前形态】(小/火山)这套对应招. 攒怒变身在 _tick_periodic_passive.
func _sk_lava_cast(u: Dictionary, tgt: Dictionary) -> void:      # 熔岩龟·选一套各自触发 ✅
	var set_id: String = u.get("lava_set", "A")
	var volcano: bool = u.get("volcano", false)
	match set_id:
		"A":
			if volcano: _lava_volcano_erupt(u)
			else:       _lava_quake(u)
		"B":
			if volcano: _lava_flame_strike(u, tgt)
			else:       _lava_magma_surge(u, tgt)
		"C":
			if volcano: _lava_magma_stomp(u)
			else:       _lava_spray(u)
		_:
			_lava_quake(u)

func _lava_quake(u: Dictionary) -> void:                         # 小·地裂: 全体魔+削魔抗
	_float_text(u["pos"] + Vector2(0, -64), "地裂!", Color("#ff7a33"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.7, o, true), Color("#ff9d5c"))
		_buff(o, "mr", -0.2, true)

func _lava_volcano_erupt(u: Dictionary) -> void:                 # 火山·火山爆发: 全体五段+灼烧+回血
	_float_text(u["pos"] + Vector2(0, -64), "火山爆发!", Color("#ff5a2a"))
	for o in _enemies_of(u):
		for i in range(5):
			if not o["alive"]: break
			_apply_damage_from(u, o, _atk_dmg(u, 0.5, o, true), Color("#ff7a33"))
		_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
	_heal(u, u["maxHp"] * 0.12)
	_skill_ring(u["pos"], Color(1.0, 0.4, 0.1, 0.5), 130.0)

func _lava_magma_surge(u: Dictionary, tgt: Dictionary) -> void:  # 小·岩浆涌动: 单体魔+永久护盾
	_float_text(u["pos"] + Vector2(0, -64), "岩浆涌动!", Color("#ff7a33"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.4, tgt, true), Color("#ff9d5c"))
	_grant_shield(u, u["atk"] * 0.8)

func _lava_flame_strike(u: Dictionary, tgt: Dictionary) -> void: # 火山·烈焰重击: 单体物+吸血
	_float_text(u["pos"] + Vector2(0, -64), "烈焰重击!", Color("#ff5a2a"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 2.2, tgt), Color("#ff7a33"), 0.30)

func _lava_spray(u: Dictionary) -> void:                         # 小·熔岩喷射: 全体+灼烧
	_float_text(u["pos"] + Vector2(0, -64), "熔岩喷射!", Color("#ff7a33"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.6, o, true), Color("#ff9d5c"))
		_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)

func _lava_magma_stomp(u: Dictionary) -> void:                   # 火山·岩浆践踏: 全体+40%眩晕+回血
	_float_text(u["pos"] + Vector2(0, -64), "岩浆践踏!", Color("#ff5a2a"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.9, o, true), Color("#ff7a33"))
		if randf() < 0.40:
			_freeze(o, CTRL_SEC)
	_heal(u, u["maxHp"] * 0.10)

func _sk_cyber_cannon(u: Dictionary, tgt: Dictionary) -> void:   # 赛博龟·能量大炮 ⚠
	_float_text(u["pos"] + Vector2(0, -64), "能量大炮!", Color("#7ee8ff"))
	_dash_to(u, tgt, 80.0)
	for i in range(2):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#9bf0ff"))
	var drones: int = u["summons"].size()
	if drones > 0:
		_apply_damage_from(u, tgt, int(u["atk"] * 0.2 * drones), Color("#d0ffff"), 0.0, true)

func _sk_hiding_defend(u: Dictionary) -> void:                   # 缩头乌龟·防御 ⚠
	_float_text(u["pos"] + Vector2(0, -64), "防御!", Color("#9be7ff"))
	_grant_shield(u, u["maxHp"] * 0.20)
	_buff(u, "def", 0.2, true)

func _sk_shell_absorb(u: Dictionary, tgt: Dictionary) -> void:   # 龟壳·吸收 ⚠
	var steal: float = tgt["maxHp"] * 0.10
	_raw_lose(tgt, steal)
	_heal(u, steal)
	_float_text(u["pos"] + Vector2(0, -64), "吸收!", Color("#b0ffd0"))

func _sk_burst(u: Dictionary, tgt: Dictionary) -> void:          # 兜底重击
	_float_text(u["pos"] + Vector2(0, -64), "重击!", Color("#ff9d5c"))
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
	_float_text(u["pos"] + Vector2(0, -64), str(opts.get("name", "技能!")), col)
	var targets: Array = _enemies_of(u) if opts.get("aoe", false) else ([tgt] if tgt != null else [])
	var vh: int = clampi(int(opts.get("hits", 1)), 1, 8)     # 视觉段数封顶(防 20 连击刷屏); 总伤=系数×ATK 不变
	var phys: float = float(opts.get("phys", 0.0))
	var magic: float = float(opts.get("magic", 0.0))
	var tru: float = float(opts.get("true", 0.0))
	var hp_flat: float = float(opts.get("hp", 0.0)) * u["maxHp"]
	var mr_flat: float = float(opts.get("mr", 0.0)) * u["mr"]
	for e in targets:
		if e == null or not e.get("alive", false):
			continue
		for i in range(vh):
			var dmg := 0
			if phys > 0.0:
				dmg += _atk_dmg(u, phys / vh, e, false)
			if magic > 0.0:
				dmg += _atk_dmg(u, magic / vh, e, true)
			dmg += int((hp_flat + mr_flat) / vh)
			if dmg > 0:
				_apply_damage_from(u, e, dmg, col)
			if tru > 0.0:
				_apply_damage_from(u, e, int(u["atk"] * tru / vh), col, 0.0, true)   # raw=真实(无视防/魔抗)
		_apply_rider(u, e, str(opts.get("rider", "")))
		_skill_ring(e["pos"], Color(col.r, col.g, col.b, 0.4), 46.0)

func _apply_rider(u: Dictionary, e: Dictionary, rider: String) -> void:
	if rider == "" or e == null or not e.get("alive", false):
		return
	match rider:
		"burn":  _apply_dot_stacks(e, "burn", maxi(1, roundi(u["atk"] * 0.5)), u)
		"stun":  e["stun_until"] = maxf(float(e.get("stun_until", 0.0)), _t + CTRL_SEC)
		"slow":  e["slow_until"] = maxf(float(e.get("slow_until", 0.0)), _t + BUFF_SEC)
		"curse": _add_dot(e, "curse", e["maxHp"] * 0.05, BUFF_SEC)
		"atkdn": _buff(e, "atk", -0.15, true)
		"mrdn":  _buff(e, "mr", -0.20, true)

# 通用护盾 (stone/rainbow/candy 的 shield 技): 全队上盾
func _sk_gen_shield(u: Dictionary) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "护盾!", Color("#9bdcff"))
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.3 + o["maxHp"] * 0.06)

# 通用治疗 (stone/pirate 的 heal 技): 奶最低血友军
func _sk_gen_heal(u: Dictionary) -> void:
	var ally = _lowest_hp_ally(u)
	if ally == null:
		ally = u
	_heal(ally, ally["maxHp"] * 0.16 + u["atk"] * 0.5)
	_float_text(ally["pos"] + Vector2(0, -64), "治疗!", Color("#39d353"))

# ── Batch2 特殊技 (bespoke; 按 pets.json brief/detail 实装) ──

# 财神·梭哈: 一场限一次, 消耗全部金币, 每枚 0.18×ATK物理 + 0.18×ATK真实 (cd999)
func _sk_fortune_allin(u: Dictionary, tgt) -> void:
	if tgt == null or u.get("allin_used", false):
		return
	u["allin_used"] = true
	var coins: int = int(u["gold"])
	u["gold"] = 0.0
	_float_text(u["pos"] + Vector2(0, -64), "梭哈! %d币" % coins, Color("#ffd93d"))
	if coins <= 0:
		return
	_apply_damage_from(u, tgt, int(u["atk"] * 0.18 * coins), Color("#ffe08a"))
	_apply_damage_from(u, tgt, int(u["atk"] * 0.18 * coins), Color("#fff0a0"), 0.0, true)   # 真实
	_skill_ring(tgt["pos"], Color(1.0, 0.85, 0.2, 0.6), 70.0)

# 星际·虫洞: 永久+魔法穿透; 沿目标方向直线四段 1.5×ATK×(1+10%×已过秒) 魔法 + 击飞
func _sk_star_wormhole(u: Dictionary, tgt) -> void:
	if tgt == null:
		return
	u["pierce"] += 8.0                              # 永久魔穿 (规格 6+0.5×lv, 局内无等级→取≈8)
	_float_text(u["pos"] + Vector2(0, -64), "虫洞!", Color("#c0a0ff"))
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	var mult: float = 1.5 * (1.0 + 0.1 * _t)        # 随战斗时间变强
	for o in _enemies_of(u):
		if o == tgt or _on_line(u["pos"], dir, o["pos"], 70.0):
			for i in range(4):
				if not o["alive"]:
					break
				_apply_damage_from(u, o, _atk_dmg(u, mult / 4.0, o, true), Color("#c0a0ff"))
			_knockback(u, o, 55.0)
			_skill_ring(o["pos"], Color(0.75, 0.6, 1.0, 0.5), 50.0)

# 线条·收尾: 引爆敌身墨迹(每层额外伤害)然后清空 (lineLink/普攻叠的 ink)
func _sk_line_finish(u: Dictionary) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "收尾!", Color("#dddddd"))
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
	var scale: float = 0.8 + 0.35 * maxi(0, best_ink)   # 每层墨迹 +0.35×ATK
	_apply_damage_from(u, best, _atk_dmg(u, scale, best), Color("#eeeeee"))
	if best_ink > 0:
		_consume_stacks(best, "ink")
	_skill_ring(best["pos"], Color(0.9, 0.9, 0.9, 0.5), 48.0)

# 赛博·部署: 立即放3个浮游炮 (与被动「浮游炮」同型, 上限10)
func _sk_cyber_deploy(u: Dictionary) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "部署浮游炮!", Color("#7ee8ff"))
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
	_float_text(tgt["pos"] + Vector2(0, -64), "束缚!", Color("#aef1ff"))
	tgt["stun_until"] = maxf(float(tgt.get("stun_until", 0.0)), _t + CTRL_SEC)
	tgt["bind_until"] = _t + CTRL_SEC
	tgt["bind_shred"] = 2.0
	tgt["bind_acc"] = 0.0
	_skill_ring(tgt["pos"], Color(0.5, 0.9, 1.0, 0.5), 50.0)

# 缩头·出击令: 命令本体随从立即额外出手一次
func _sk_hiding_command(u: Dictionary) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "出击!", Color("#a8ffb0"))
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
	_float_text(u["pos"] + Vector2(0, -64), "复制!", Color("#cfd8e8"))
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
	u["shield"] = minf(u["shield"] + amt, u["maxHp"] * SHIELD_CAP_MULT)
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.4), 44.0)
	_sfx_shield_gain()                       # §AUDIO: 得盾音 (节流; 群体上盾不刷屏)

# silent=true: 吸血等高频被动回血不出治疗音 (防刷屏), 主动治疗/技能回血出音
func _heal(u: Dictionary, amt: float, silent: bool = false) -> void:
	if amt <= 0.0: return
	u["hp"] = minf(u["maxHp"], u["hp"] + amt)
	_float_text(u["pos"] + Vector2(0, -40), "+" + str(int(amt)), Color("#39d353"))
	if not silent:
		_sfx_heal()                          # §AUDIO: 治疗音 (节流)

func _freeze(u: Dictionary, sec: float = CTRL_SEC) -> void:
	u["stun_until"] = maxf(u["stun_until"], _t + sec)
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
				new_val = floori(stacks * 2.0 / 3.0)
				if _t < u.get("true_fire_until", 0.0):
					_raw_lose(u, float(dmg))
				else:
					_apply_damage(u, dmg, Color("#7aa8ff"))
			"poison":
				dmg = stacks
				new_val = floori(stacks * 3.0 / 4.0)
				_apply_damage(u, dmg, Color("#7ee87e"))
			"bleed":
				dmg = stacks
				new_val = floori(stacks * 3.0 / 4.0)
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

func _apply_spawn_passives() -> void:
	for u in _units.duplicate():
		match u["id"]:
			"ninja":
				u["crit"] += 0.30; u["crit_dmg"] += 0.20; u["pierce"] += 8.0
				_buff(u, "dodge", 0.25, false, 9999.0)
			"ghost":
				for o in _enemies_of(u):
					_add_dot(o, "curse", o["maxHp"] * 0.05, BUFF_SEC)
			"ice":
				for o in _enemies_of(u):
					_buff(o, "atk", -0.20, true, BUFF_SEC * 1.5)
					o["slow_until"] = _t + BUFF_SEC * 1.5
			"headless":
				u["lifesteal"] += 0.22
			"dice":
				u["pierce"] += u["def"] + u["mr"]
				u["base_def"] = 0.0; u["base_mr"] = 0.0; _recalc_stats(u)
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
					"label": "糖果炸弹", "col_size": 20.0, "hp_w": 24.0,
					"no_basic": true, "no_move": true, "self_decay": 0.08,
					"death_aoe": 1.5,
				})
			"hiding":
				_spawn_hiding_minion(u)
			"crystal":
				_spawn_summon(u, "crystalball", u["maxHp"] * 0.50, u["atk"], {
					"label": "水晶球", "col_size": 20.0, "hp_w": 26.0, "melee": false,
					"move_spd": 90.0, "atk_range": 320.0, "no_basic": true,
					"special": "ray", "special_cd": 2.5, "special_scale": 1.0,
				})
			"lava":
				u["lava_set"] = "A"
			"two_head":
				u["two_set"] = "1"; u["two_form"] = "melee"
	# 选3 被动技 (开局生效, 不进主动轮转): 寒冰免疫灼烧 + 对熔岩/凤凰 +40%
	for u in _units:
		if "iceBurnImmune" in _chosen_skill_types(u["id"], u["side"] == "left"):
			u["_burnImmune"] = true
			u["_vs_fire_bonus"] = 0.4

func _on_basic_hit(u: Dictionary, tgt: Dictionary) -> void:
	if not tgt["alive"]:
		return
	match u["id"]:
		"line":
			_add_stack(tgt, "ink", 1, 5)
		"lightning":
			var lv := _add_stack(tgt, "electric", 1, 8)
			if lv >= 8:
				_consume_stacks(tgt, "electric")
				_apply_damage_from(u, tgt, int(u["atk"] * 0.82), Color("#bff0ff"), 0.0, true)
		"crystal":
			var cv := _add_stack(tgt, "crystal", 1, 4)
			if cv >= 4:
				_consume_stacks(tgt, "crystal")
				_apply_damage_from(u, tgt, int(tgt["maxHp"] * 0.19), Color("#c9b0ff"), 0.0, true)
				_buff(tgt, "mr", -0.2, true)
	# 猎人猎杀: 攻击后斩杀<14%HP敌
	if u["id"] == "hunter" and tgt["alive"] and tgt["hp"] < tgt["maxHp"] * 0.14:
		_float_text(tgt["pos"] + Vector2(0, -56), "斩杀!", Color("#ff6b6b"))
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
	# --- 熔岩变身: 怒气满100 → 变火山N秒 ---
	if u["id"] == "lava" and u["rage"] >= RAGE_MAX and not u.get("volcano", false):
		u["rage"] = 0.0
		u["volcano"] = true
		u["volcano_until"] = _t + 6.0
		_buff(u, "atk", 0.6, true, 6.0); _buff(u, "def", 0.4, true, 6.0); _buff(u, "mr", 0.4, true, 6.0)
		u["maxHp"] *= 1.3; u["hp"] *= 1.3
		_float_text(u["pos"] + Vector2(0, -70), "变身·火山龟!", Color("#ff5a2a"))
		for o in _enemies_of(u):
			_apply_damage_from(u, o, _atk_dmg(u, 1.0, o, true), Color("#ff7a33"))
			_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
			_heal(u, (o["maxHp"] - o["hp"]) * 0.08)
	if u.get("volcano", false) and _t >= u["volcano_until"]:
		u["volcano"] = false
		u["maxHp"] /= 1.3; u["hp"] = minf(u["hp"], u["maxHp"])
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
	# --- 石头坚壁: 每秒+护甲 (上限100%开局护甲) ---
	elif u["id"] == "stone":
		if u["_ptimer"] >= STACK_DOT_TICK:
			u["_ptimer"] = 0.0
			if u["def"] < u["base_def"] * 2.0:
				u["base_def"] += u["base_def"] * 0.02; _recalc_stats(u)
	# --- 竹叶生长: 每N秒充能 → 永久+ATK/HP ---
	elif u["id"] == "bamboo":
		if u["_ptimer"] >= 4.0:
			u["_ptimer"] = 0.0
			u["base_atk"] *= 1.06; u["maxHp"] *= 1.04; u["hp"] += u["maxHp"] * 0.08
			_recalc_stats(u)
	# --- 龟壳气场觉醒 + 储能消耗周期 ---
	elif u["id"] == "shell":
		if not u.get("awakened", false) and _t >= 10.0:
			u["awakened"] = true
			_buff(u, "atk", 0.12, true, 9999.0); _buff(u, "def", 0.12, true, 9999.0); _buff(u, "mr", 0.12, true, 9999.0)
			u["crit"] += 0.25; _recalc_stats(u)
			_float_text(u["pos"] + Vector2(0, -70), "气场觉醒!", Color("#b0ffe0"))
		u["_shelltimer"] = u.get("_shelltimer", 0.0) + delta
		if u["_shelltimer"] >= 3.0:
			u["_shelltimer"] = 0.0
			var se: float = u["store_energy"]
			if se >= 1.0:
				u["store_energy"] = 0.0
				for o in _enemies_of(u):
					_apply_damage_from(u, o, int(se * 0.40), Color("#b0ffe0"))
				_grant_shield(u, se * 0.80)
				_float_text(u["pos"] + Vector2(0, -64), "气场释放!", Color("#b0ffe0"))
				_skill_ring(u["pos"], Color(0.7, 1.0, 0.88, 0.5), 120.0)
	# --- 海盗船召唤: 开战~4秒后召唤一次 ---
	if u["id"] == "pirate" and not u.get("ship_summoned", false) and _t >= 4.0:
		u["ship_summoned"] = true
		_spawn_pirate_ship(u)
	# --- 财神聚宝盆: 每秒+2金币 ---
	if u["id"] == "fortune":
		u["_goldtimer"] = u.get("_goldtimer", 0.0) + delta
		if u["_goldtimer"] >= 1.0:
			u["_goldtimer"] = 0.0; u["gold"] += 2

# ============================================================================
#  死亡钩子 (1:1 搬自 2D 版 _on_unit_death; 装备 on-kill/on-death Phase 3b 不调)
# ============================================================================
func _on_unit_death(u: Dictionary, killer) -> void:
	# 召唤体死亡爆炸 (糖果炸弹: 全体敌均摊魔伤)
	if u.get("death_aoe", 0.0) > 0.0:
		var es := _enemies_of(u)
		if not es.is_empty():
			var per: float = u["maxHp"] * u["death_aoe"] / float(es.size())
			for o in es:
				_apply_damage_from(u, o, int(per), Color("#ff8ad8"), 0.0, true, true)
			_skill_ring(u["pos"], Color(1.0, 0.5, 0.8, 0.6), 120.0)
			_float_text(u["pos"] + Vector2(0, -40), "炸!", Color("#ff8ad8"))
	# 缩头本体死亡 → 同步杀掉其随从
	if u["id"] == "hiding":
		for o in _units:
			if o.get("is_summon", false) and o.get("summon_owner", null) == u and o["alive"]:
				o["hp"] = 0.0; o["alive"] = false
				_hide_summon_nodes(o)
	# 赛博龟阵亡 → 浮游炮组装成机甲
	if u["id"] == "cyber":
		_cyber_assemble_mech(u)
	# 财神聚宝盆: 任意单位死亡给所有存活对面财神金币
	for o in _units:
		if o["alive"] and o["id"] == "fortune" and o["side"] != u["side"]:
			o["gold"] += 2
	# 猎人猎杀: 击杀者是猎人 → 窃取属性+叠吸血
	if killer != null and killer["alive"] and killer["id"] == "hunter":
		killer["base_atk"] += u["base_atk"] * 0.14
		killer["lifesteal"] += 0.08
		_recalc_stats(killer)
		_float_text(killer["pos"] + Vector2(0, -64), "猎杀!", Color("#a8ffb0"))
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
	var hp: float = float(d.get("hp", 450)) * HP_MULT * 0.40
	var minion = _spawn_summon(u, "minion", hp, float(d.get("atk", 40)) * 0.8, {
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
		_float_text(u["pos"] + Vector2(0, -70), "召唤海盗船!", Color("#ffb05c"))

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
		"label": "机甲", "col_size": 40.0, "hp_w": 46.0, "melee": false,
		"move_spd": 130.0, "atk_interval": 1.0, "atk_range": 320.0,
		"special": "mech_blast", "special_cd": 2.5, "special_scale": 1.5,
	})
	if mech != null:
		mech["pos"] = u["pos"]
		_float_text(u["pos"] + Vector2(0, -70), "机甲组装!", Color("#7ee8ff"))
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
		spr.texture = _make_block_texture(Color(col.r, col.g, col.b, 0.9))
		spr.pixel_size = (col_size * WS) / 64.0
		spr.offset = Vector2(0.0, 32.0)
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
		"crit": float(behavior.get("crit", 0.0)), "crit_dmg": 1.5, "pierce": 0.0, "lifesteal": 0.0,
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
		# --- Phase4: squash/stretch 形变 + idle bob 高度微浮 (全从 base 起算, 不累积) ---
		var sq := _juice_scale_for(u)              # (sx, sy) 形变系数 (base=1,1)
		var bob := _juice_bob_for(u)               # idle 呼吸 Y 偏移 (米)
		# 立绘: XZ + Y(高度 + 落地基线抬升 + bob). billboard 自动朝镜头, 不翻 facing.
		spr.position = _world_pos(u["pos"], u["height"] + GROUND_LIFT + bob)
		var bs: Vector3 = u.get("spr_base_scale", Vector3.ONE)
		spr.scale = Vector3(bs.x * sq.x, bs.y * sq.y, bs.z)
		# 受击闪白: modulate 由 base 白 → 过曝白线性插值 (flash_t/JUICE_FLASH_SEC); 死亡淡出走 alpha 不冲突
		var fl: float = clampf(u.get("flash_t", 0.0) / JUICE_FLASH_SEC, 0.0, 1.0)
		spr.modulate = Color.WHITE.lerp(JUICE_FLASH_COLOR, fl)
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
			contact.modulate.a = CONTACT_BASE_A * cs
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
func _flash(u: Dictionary) -> void:
	if u == null or not u.get("alive", false):
		return
	u["flash_t"] = JUICE_FLASH_SEC
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
	# 冲击粒子: 只在重击/大招迸火花
	if (lvl == "heavy" or lvl == "big") and float(dmg) >= JUICE_PARTICLE_MIN_DMG:
		var p2d: Vector2 = at_pos if at_pos != null else tgt.get("pos", Vector2.ZERO)
		_impact_particles(p2d, tgt.get("height", 0.0))

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

# 血条/龟能 overlay: 每帧 unproject 单位头顶 → 屏幕像素 (跟随)
func _update_overlay() -> void:
	if _cam == null:
		return
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
				var base := _skill_cd(st)
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
		_show_banner(won)

func _show_banner(won: bool) -> void:
	if _settled:
		return
	_settled = true
	# §AUDIO: 结算 — 败方放 defeat 音 (灭队/失败); 胜方留给后续胜利音(暂无). BGM 淡出收尾.
	if not won:
		_sfx_simple("defeat")
	var a := _audio()
	if a != null:
		a.stop_bgm()
	var accent := Color("#ffd93d") if won else Color("#ff6b6b")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55); dim.size = Vector2(1280, 720)
	_ui_layer.add_child(dim)
	var big := Label.new()
	big.text = ("🏆 胜利!" if won else "💀 失败!")
	big.add_theme_font_size_override("font_size", 56)
	big.add_theme_color_override("font_color", accent)
	big.size = Vector2(1280, 80); big.position = Vector2(0, 300)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_layer.add_child(big)
	var sub := Label.new()
	sub.text = "[R 再战 · ESC 返回菜单]   (Phase 3 接赛季结算/奖励)"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color("#9fb6c9"))
	sub.size = Vector2(1280, 26); sub.position = Vector2(0, 392)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_layer.add_child(sub)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
#  DEV 自截图 (SELFSHOT=<秒>): 等战斗跑起来 + frame_post_draw 保证入帧缓冲
# ============================================================================
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
		var add: float = float(st["hp"]) * HP_MULT
		u["maxHp"] += add; u["hp"] += add
	if st.has("crit"):
		u["crit"] += float(st["crit"])
	if st.has("armorPen"):
		u["pierce"] += float(st["armorPen"])
	if st.has("magicPen"):
		u["pierce"] += float(st["magicPen"])
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
		"p2eq_017":   # 不沉之锚: 免击飞+免斩杀 (flag)
			u["_knock_immune"] = true
			u["eq_exec_immune"] = true
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
			"p2eq_002":   # 海带卷刀: 命中→施加流血层
				var bs: int = maxi(1, roundi([0.075, 0.1, 0.15][si] * src["atk"]))
				_apply_dot_stacks(tgt, "bleed", bs, src)
			"p2eq_003":   # 锋利鲨齿: 溅射相邻格
				var frac: float = [0.15, 0.28, 0.50][si]
				for o in _enemies_of(src):
					if o != tgt and (o["pos"] - tgt["pos"]).length() <= 70.0:
						_apply_damage_from(src, o, maxi(1, int(dmg * frac)), Color("#ffd07a"), 0.0, false, true)
			"p2eq_005":   # 双生匕首: 概率追击
				if randf() < [0.5, 0.75, 1.0][si]:
					_apply_damage_from(src, tgt, _atk_dmg(src, [0.7, 0.8, 1.0][si], tgt), Color("#ffe08a"), 0.0, false, true)
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
					_freeze(tgt, EQ_TICK)
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
		_bolt_line(prev, cur["pos"], Color("#bff0ff"))
		_apply_damage_from(src, cur, dmg, Color("#bff0ff"), 0.0, true, true)
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
	_float_text(src["pos"] + Vector2(0, -70), "烈焰爆发!", Color("#ff7a33"))
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
					if cur >= 20 and not bool(stt.get("harden_given", false)) and float(stt.get("harden_shield", 0.0)) > 0.0:
						stt["harden_given"] = true
						_grant_shield(u, float(stt["harden_shield"]))
			"p2eq_015":   # 荆棘海胆: 反伤真伤 + 施流血给攻击者
				if src.get("alive", false) and src["side"] != u["side"]:
					var refl: float = float(dmg) * float(stt.get("reflect_pct", 0.10))
					if refl >= 1.0:
						_raw_lose(src, refl)
					_apply_dot_stacks(src, "bleed", maxi(1, roundi(float(stt.get("reflect_bleed", 2.0)))), u)
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
						_apply_damage_from(u, o, dd, Color("#ffe08a"), 0.0, false, true); tot += dd
				_grant_shield(u, tot * [0.5, 0.75, 1.0][si])
			"p2eq_008":   # 双穿珊瑚刺: 对最远敌
				var far = null; var fd := -1.0
				for o in _enemies_of(u):
					var dd2: float = (o["pos"] - u["pos"]).length_squared()
					if dd2 > fd: fd = dd2; far = o
				if far != null:
					_apply_damage_from(u, far, _atk_dmg(u, [1.0, 1.2, 1.5][si], far), Color("#ffe08a"), 0.0, false, true)
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
			"p2eq_031":   # 迷你水晶球B: 对全体敌魔伤+叠层引爆
				for o in _enemies_of(u):
					_apply_damage_from(u, o, [20, 25, 30][si], Color("#c9b0ff"), 0.0, true, true)
					_eq_crystal_stack(u, o, si)
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
					_float_text(u["pos"] + Vector2(0, -70), "生长!", Color("#39d353"))
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
			"p2eq_050":   # 幽灵加特林: N发随机分布+永久减甲
				for _g in range([20, 30, 60][si]):
					var es2 := _enemies_of(u)
					if es2.is_empty(): break
					var o = es2[randi() % es2.size()]
					_apply_damage_from(u, o, _atk_dmg(u, [0.1, 0.12, 0.14][si], o), Color("#d0ffff"), 0.0, false, true)
					o["base_def"] = maxf(0.0, o["base_def"] - [1.0, 2.0, 3.0][si]); _recalc_stats(o)
			"p2eq_051":   # 激光手枪: 直线首敌+流血, 身后50%
				var dir4: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var first = _eq_first_in_line(u, dir4, 50.0)
				if first != null:
					_apply_damage_from(u, first, _atk_dmg(u, [1.5, 2.0, 2.8][si], first), Color("#ff8aa0"), 0.0, false, true)
					_apply_dot_stacks(first, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si])), u)
					for o in _enemies_of(u):
						if o != first and _on_line(first["pos"], dir4, o["pos"], 50.0):
							_apply_damage_from(u, o, _atk_dmg(u, [0.75, 1.0, 1.4][si], o), Color("#ff8aa0"), 0.0, false, true)
			"p2eq_053":   # 霰弹贝古: 扇形N发, 被8+发命中→眩晕
				var hitc: Dictionary = {}
				for _s in range([12, 14, 18][si]):
					var es3 := _enemies_of(u)
					if es3.is_empty(): break
					var o = es3[randi() % es3.size()]
					_apply_damage_from(u, o, _atk_dmg(u, 0.22, o), Color("#ffd07a"), 0.0, false, true)
					hitc[o] = int(hitc.get(o, 0)) + 1
				for o in hitc:
					if int(hitc[o]) >= 8: _freeze(o, EQ_TICK)
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

# 水晶叠层 (A/B共用)
func _eq_crystal_stack(src: Dictionary, o: Dictionary, si: int) -> void:
	var lv := _add_stack(o, "p2crystal", 1, 3)
	if lv >= 3:
		_consume_stacks(o, "p2crystal")
		_apply_damage_from(src, o, int(o["maxHp"] * [0.14, 0.17, 0.20][si]), Color("#c9b0ff"), 0.0, true, true)

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
	_bolt_line(u["pos"], low["pos"], Color("#ffe08a"))
	var killed := false
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 36.0):
			var before: bool = o["alive"]
			_apply_damage_from(u, o, _atk_dmg(u, [2.0, 3.0, 7.0][si], o), Color("#ffe08a"), 0.0, false, true)
			if before and not o["alive"]:
				killed = true
	if killed:
		_eq_sniper(u, si, depth + 1)

# ============================================================================
#  on-kill (击杀者视角) — 暴君之牙
# ============================================================================
func _eq_on_kill(killer: Dictionary, _victim: Dictionary) -> void:
	for e in killer.get("equips", []):
		if str(e["id"]) == "p2eq_004":   # 暴君之牙: 处决后回40血
			_heal(killer, 40.0)
			_float_text(killer["pos"] + Vector2(0, -64), "处决!", Color("#ff6b6b"))

# ============================================================================
#  on-death (阵亡者视角) — 复活海螺 / 黄铜齿轮 / 玩偶小熊
# ============================================================================
func _eq_on_death(u: Dictionary, _killer) -> void:
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_033":   # 复活海螺: 阵亡→原位变小虫 (复用 _spawn_summon, 3D 用色块 block)
				var worm = _spawn_summon(u, "worm", [150.0, 200.0, 300.0][si] * HP_MULT, [20.0, 30.0, 40.0][si], {"label": "海螺虫", "col_size": 30.0, "hp_w": 22.0})
				if worm != null:
					worm["pos"] = u["pos"]
					if is_instance_valid(worm["sprite"]): worm["sprite"].position = _world_pos(u["pos"], GROUND_LIFT)
					worm["eq_state"] = {}; worm["equips"] = []
					if si == 2:   # 3★: 标记每周期分裂
						worm["worm_split"] = true
				_float_text(u["pos"] + Vector2(0, -40), "复活海螺!", Color("#c0ffd0"))
			"p2eq_035":   # 黄铜齿轮: 死亡→每层折2深海币 (仅玩家左队计入)
				var gears: int = int(stt.get("gears", 0))
				if gears > 0 and u["side"] == "left":
					var gs = get_node_or_null("/root/GameState")
					if gs != null and gs.get("meta_deepsea_coins") != null:
						gs.set("meta_deepsea_coins", int(gs.get("meta_deepsea_coins")) + gears * 2)
			"p2eq_034":   # 玩偶小熊: 🚧 简化 — 阵亡时召唤大熊 (250生命/50攻击)
				var bear = _spawn_summon(u, "bear", 250.0 * HP_MULT, 50.0, {"label": "大熊", "col_size": 40.0, "hp_w": 30.0})
				if bear != null:
					bear["eq_state"] = {}; bear["equips"] = []

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
					_apply_damage_from(u, t, _atk_dmg(u, [0.6, 0.75, 1.0][si], t) + int([40, 60, 100][si] * u["crit"]), Color("#ffe08a"), 0.0, false, true)
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
					_apply_damage_from(u, t2, int(u["maxHp"] / HP_MULT * [0.05, 0.07, 0.10][si]), Color("#ffe08a"), 0.0, false, true)
			"p2eq_021":   # 守护贝母: 每周期连接攻击最高友军→给护盾+净化
				var best = null; var ba := -1.0
				for o in _allies_of(u):
					if o["atk"] > ba: ba = o["atk"]; best = o
				if best != null:
					_grant_shield(best, [40.0, 60.0, 90.0][si])
					best["dots"] = []; best["dot_stacks"] = {}
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
					_bolt_line(Vector2(o["pos"].x, ARENA.position.y), o["pos"], Color("#bff0ff"))
					_apply_damage_from(u, o, int(u["atk"]), Color("#bff0ff"), 0.0, true, true)
			"p2eq_027":   # 电棍: 每周期电击随机敌+眩晕, 消耗1层
				if int(stt.get("baton_charges", 0)) > 0:
					var es2 := _enemies_of(u)
					if not es2.is_empty():
						stt["baton_charges"] = int(stt["baton_charges"]) - 1
						var o = es2[randi() % es2.size()]
						_apply_damage_from(u, o, [30, 40, 50][si], Color("#bff0ff"), 0.0, true, true)
						_freeze(o, EQ_TICK)
			"p2eq_035":   # 黄铜齿轮: 每周期+N层
				stt["gears"] = int(stt.get("gears", 0)) + [1, 2, 3][si]
			"p2eq_017":   # 不沉之锚: ⚠简化 — 每周期击飞+眩晕最近敌
				var at = _nearest_enemy(u)
				if at != null:
					_apply_damage_from(u, at, int([0.4, 0.6, 3.0][si] * (u["def"] + u["mr"]) + at["maxHp"] * [0.15, 0.25, 0.70][si]), Color("#9be7ff"), 0.0, false, true)
					_knockback(u, at, 60.0); _freeze(at, EQ_TICK)
			"p2eq_036":   # 温泉蛋: 孵化进度, 满100→全队均摊护盾(一次)
				stt["incub"] = float(stt.get("incub", 0.0)) + 5.0
				if float(stt["incub"]) >= 100.0 and not bool(stt.get("incub_given", false)):
					stt["incub_given"] = true
					var allies := _allies_of(u)
					var per: float = float(stt.get("incub_shield", 300.0)) / maxf(1.0, float(allies.size()))
					for o in allies:
						_grant_shield(o, per)
					_float_text(u["pos"] + Vector2(0, -70), "孵化!", Color("#ffe9a8"))
			"p2eq_042":   # 涟漪药剂: 每周期全队回已损血
				for o in _allies_of(u):
					_heal(o, (o["maxHp"] - o["hp"]) * [0.03, 0.06, 0.10][si])
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
		var nw = _spawn_summon(u, "worm", u["maxHp"], u["atk"], {"label": "海螺虫", "col_size": 30.0, "hp_w": 22.0})
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
