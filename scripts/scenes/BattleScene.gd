extends Node2D

const Events := preload("res://scripts/engine/events.gd")   # 局中事件 (preload 直引, 不依赖全局 class 注册)
const Phase2Config := preload("res://scripts/engine/phase2_config.gd")   # 二阶段数值 (攻蛋回合数等)
const Minion := preload("res://scripts/engine/phase2_minion.gd")          # 深海小将 补位生成
const Phase2Schools := preload("res://scripts/engine/phase2_schools.gd")   # 11学派(装备套装羁绊) 计数/定义
const Phase2Types := preload("res://scripts/engine/phase2_types.gd")   # 12类型(职业)羁绊 计数/定义
const Phase2EquipRuntime := preload("res://scripts/engine/phase2_equip_runtime.gd")   # 二阶段装备战斗实装 (剑系)

## BattleScene — W4 MVP: 3v3 自动战斗
##
## 演示目标: 让 W3 验证过的 Damage.gd 公式在一个真实战斗循环里跑起来。
## 双方各 3 龟 (写死), 回合制, AI 自动选最低血敌人 + 用 0 号技能, 直到一方全灭。
##
## 不含 (W5+):
##   - 玩家选龟 / 选技能 / 选目标 UI
##   - 技能 type 派发 (除了普物理 / 普魔法 — calc_damage 已支持)
##   - DoT / buff / debuff
##   - 装备 / 被动 / 羁绊
##   - 特效 VFX (只有最简单飘字 + hop)


# ─── 默认阵容 (GameState 没数据时用, e.g. 直接 F6 跑 Battle.tscn 测试) ───
const DEFAULT_LEFT: Array[String] = ["basic", "phoenix", "shell"]
const DEFAULT_RIGHT: Array[String] = ["basic", "stone", "bamboo"]

const TURN_DELAY_MS: int = 400          # 每次出手后停 400ms (1:1 PoC endTurn delayedCall(400), BattleScene.ts:8163)
const HOP_DISTANCE: int = 30            # 出招前向前冲 30px
const HOP_DURATION: float = 0.15
const OVERTIME_START: int = 30          # 决胜局起点: 此回合后全龟每回合叠怒气(+30%伤害/层)+疲惫(治疗/护盾-50%)
const OVERTIME_HARD_CAP: int = 200      # 纯防引擎级死循环安全网 (怒气指数增伤实际几回合内必分胜负, 永不判平)
const _HOLY_SHIELD_COLOR := Color(1.0, 0.93, 0.62)   # 圣甲圣盾=白黄亮圣光色 (#fff0a0 调, 区别普通蓝盾 shieldglow)
const _HOLY_SHIELD_HEX := "#ffe88a"                  # 圣盾飘字金白色
# 飘字时长/距离 → 走 VisualConstants (跟 Phaser 同步)


# ─── 节点引用 ──────────────────────────────────────────────────
@onready var background: TextureRect = $Background
@onready var slots_root: Node2D = $Slots
@onready var battle_camera: Camera2D = $Camera2D
@onready var battle_log: RichTextLabel = $UI/LogPanel/BattleLog
@onready var title_label: Label = $UI/TopBar/Title
@onready var status_bar: Label = $UI/StatusBar
@onready var result_overlay: ColorRect = $UI/ResultOverlay
@onready var result_label: Label = $UI/ResultOverlay/Title
@onready var result_subtitle: Label = $UI/ResultOverlay/Subtitle
@onready var return_button: Button = $UI/ResultOverlay/ReturnButton


# ─── 运行时状态 ────────────────────────────────────────────────
var fighters: Array[Dictionary] = []     # 6 个 fighter dict (顺序 = 行动顺序: 左0,右0,左1,右1,左2,右2)
var slot_nodes: Array[Node2D] = []        # 跟 fighters 同索引的视图节点
var turn: int = 1
var finished: bool = false
var rule: String = ""                    # 本局规则之日 (GameState.battle_rule, "" = 无)
var battle_stats := BattleStats.new()    # 局内伤害/治疗/护盾/击杀统计 (结算面板用)
var auto_battle: bool = false            # 自动对战 (双方全 AI, 隐藏操作面板) — PoC _autoBattle
var auto_play_debug: bool = false        # headless 自测: 玩家回合自动点首技能/首目标 (验不崩, 非正式)
var _smoke_click: bool = false           # SMOKE_CLICK: 玩家回合【注入真实鼠标点击】(测真点击命中+伤害, 非emit信号)
var _prev_scale_aspect: int = -1         # 进战斗前的 content_scale_aspect (退出还原)
var _right_hud: Array = []               # [{node,margin}] 右锚 HUD (ENVELOP 下重排到真实右边缘)
var _targeting_active := false           # 选目标中 (右键/Esc 取消)
var _events_fired: Array = []            # 已触发的局中环境事件 id (整场互斥, 1:1 PoC alreadyFired)
var _gadget_deaths_left: int = 0        # 奇械[深海工坊]: 本场我方(左)累计失去的统领/小将数 (规格#544 死亡产装备触发计数)
var _gadget_tiers_fired: Dictionary = {} # 奇械: 已触发过的累计死亡档(cost) → true (每档一局仅产一次)
var _gadget_rng := RandomNumberGenerator.new()  # 奇械产装备掷货 RNG
var action_panel: CanvasLayer = null     # 玩家操作面板 (左队手动选技能/目标)
var _result_shown: bool = false          # 防 _show_result 多入口重复切场景 (有 await 后更需守卫)
var banner_layer: CanvasLayer = null     # 回合横幅层 (中央"第N回合" + 侧"我方/敌方回合")
var fx_layer: CanvasLayer = null         # 全屏特效层 (cut-in 闪屏) — 在 CanvasLayer 不随相机 zoom/pan
var hud_layer: CanvasLayer = null        # 浮层 HUD: GlobalToolbar(顶部图标行) + StatsRail(深海币+羁绊) + BenchRail(装备席). 不随相机.
# 装备席库存 (1:1 PoC benchInventory, BattleScene.ts:182/306-311): per-battle, 开战为空 (dungeon 跨关另带);
#   ★不是 GameState.inventory(那是 Godot 自创的全局持久累加器 → 开局塞满 = "那么多装备"根因)。
var bench_inventory: Array = []
var _bench_buff_items: Dictionary = {}   # bench_id → 单体增益 buff dict (1:1 PoC: 商店单体buff也进席, 玩家拖到龟/敌用)
var _buff_bench_seq: int = 0             # 生成唯一 bench_id (同 buff 可多件)
var _drag_pending_eid: String = ""       # 已按下待判定的库存件 (移动 ≥5px 才转拖拽, 否则=点击看详情 1:1 PoC)
var _drag_start: Vector2 = Vector2.ZERO  # 按下位置 (判 5px 阈值)
var _drag_eid: String = ""               # 真正拖拽中的装备 eid (落到左队龟即装上; 空=未拖拽)
var _drag_ghost: Control = null          # 跟随鼠标的拖拽残影
var _drag_layer: CanvasLayer = null      # 拖拽残影所在顶层
var _sell_hint: Control = null           # 云顶式拖卖: 拖装备到商店区时的「出售 +N币」高亮浮层
var _tutorial_guide: Node = null         # 教程步骤引导 (本局教程时启)
var _is_tutorial: bool = false           # 本局是否教程 (开局从 GameState.tutorial 一次性消费)
# 伤害统计面板 (1:1 PoC DmgStatsPanel.ts) — 4 tab × 双列 × stacked bar
var _dmg_stats_panel: PanelContainer = null
var _dmg_stats_tab: String = "dealt"
var _dmg_stats_cols: Array = []          # [我方 rows VBox, 敌方 rows VBox]
var _dmg_stats_tab_btns: Dictionary = {}
# 点龟详情面板 (1:1 PoC DetailPanel.ts) — 点战斗中任意龟弹出
var _detail_layer: CanvasLayer = null
var _detail_fighter_uid: int = -99
var _skill_card_layer: CanvasLayer = null   # 技能描述大卡(单例, 切换不叠)
var _detail_tiles: Array = []   # 详情面板可点技能 tile 注册 [{node,title,icon,body,detail}] — 大卡开着时点别的 tile 直接切换 (1:1 PoC)
var _skill_card_refresh: Dictionary = {}   # 当前打开的被动大卡 {body,base,f,pas,expanded} → _process 实时刷状态行
var _hover_token: int = 0   # 悬浮开卡令牌 (防过期/切tile)
var _hover_ring: CanvasLayer = null   # 蓄力进度圈浮层
var _picked_skill_idx: int = -1          # 玩家在面板点的技能 (signal 中转)
var _player_wants_back: bool = false     # 玩家点了「←换龟」(回选龟框重选, 不计行动)
var _ai_moved_once: bool = false         # 本局是否已有 AI 出过手: 首次保留长思考(~1.2s), 之后缩短(~0.7s) 避免每只都等满 1.7s
# 出手倒计时 (1:1 PoC startTurnTimer: 30s, ≤10s红, 0→自动AI出招). auto_play_debug/auto_battle 不启用(不扰headless)。
var _turn_timer_left: int = 0
var _turn_timer_active: bool = false
var _turn_timed_out: bool = false
var _turn_timer_gen: int = 0             # 代数: 清/重启时 +1, 让旧 tick 协程自然退出
var _turn_timer_paused_left: int = -1    # 决策态开 ⓘ 详情时暂停倒计时: 存剩余秒(>=0=暂停中), 关面板恢复 (防看信息误超时)
var _turn_timer_layer: CanvasLayer = null
var _turn_timer_bar: Control = null
var _turn_timer_fill: Panel = null
var _turn_timer_fill_sb: StyleBoxFlat = null
var _turn_timer_label: Label = null
var _picker_layer: CanvasLayer = null    # 选龟框 + 可动龟绿环 所在层
var _picker_active: bool = false         # 选龟框等待中 (玩家正要点发光龟出手) — 点龟身=出手, 抑制详情面板 (看信息走 ⓘ 钮)
var _picked_target_idx: int = -1         # 玩家点的目标 slot
# 点龟交互 (方案A, 用户 2026-06-25, 删长按): 决策态(_picker_active/_targeting_active) 点龟身=出手/选靶;
#   闲置态点龟身=弹详情面板; 看信息(任何态)=点龟头上的 ⓘ 信息钮 (_add_info_button)。

# 玩家可操作的模式 (1:1 PoC isPlayerTurn: 这些 mode 下左队=玩家手动)
const PLAYER_MODES := ["single", "dungeon", "custom", "boss", "boss-pick", "test", "pve", "duallane"]

signal _skill_chosen(skill_idx: int)     # ActionPanel → 玩家点了技能
signal _picker_picked(actor_idx: int)    # 选龟框 → 玩家选了出手龟
signal _target_chosen(target_idx: int)   # 目标圈 → 玩家点了目标
signal _shop_closed                      # 商店关闭 (跳过/超时)
signal _equip_picked(equip_id: String)   # 初始装备 modal → 玩家选了装备
var _shop_reroll_cost: int = 2           # 重投费 (每场重置)


# ─── 槽位坐标 (1:1 PoC POS_BY_SLOT, 16:9 background %) ──────────
# viewport 1280×720 = 16:9, 与背景图同比 → mapCoverPos 无裁切, 屏幕坐标 = (xPct/100×W, yPct/100×H).
# front(前排)靠中 x≈37, back(后排)靠边 x≈23; col 0/1/2 上中下 y=41/55/69. 右队 x 镜像 (100-xPct).
const VIEW_W: int = 1280
const VIEW_H: int = 720

# 朝向例外 (1:1 PoC BattleScene.ts:1907 FACING_RIGHT_ASSETS = {hiding, mech}): 多数龟资源默认朝左 →
#   左队翻转面朝右(向敌)、右队不翻转。但 hiding (隐龟召唤) / mech (赛博龟组装的机甲立绘) 资源默认朝右
#   → flip 逻辑反着 (左队翻转、右队不翻)。注: cyber 基础态是常规朝左 (不在此表), 仅其变身 mech 在表内
#   (mech 立绘由 _swap_avatar("mech") 换入, 同 PoC D4 ts:4537-4538)。
const FACING_RIGHT_ASSETS := ["hiding", "mech"]
const POS_BY_SLOT := {
	"front-0": Vector2(38, 41), "front-1": Vector2(37, 55), "front-2": Vector2(36, 69),
	"back-0":  Vector2(25, 41), "back-1":  Vector2(24, 55), "back-2":  Vector2(22, 69),
}

# (_slotKey, side) → 屏幕像素坐标. 右队水平镜像.
func _slot_to_coords(slot_key: String, side: String) -> Vector2:
	var pct: Vector2 = POS_BY_SLOT.get(slot_key, POS_BY_SLOT["front-1"])
	var x_pct: float = pct.x if side == "left" else (100.0 - pct.x)
	return Vector2(roundi(x_pct / 100.0 * VIEW_W), roundi(pct.y / 100.0 * VIEW_H))


func _ready() -> void:
	# 等 DataRegistry 加载完
	await get_tree().process_frame

	# inkLink 30% 分流可见化: damage.gd 分流时回调 → partner 飘字 + 战绩归功线条龟 (1:1 PoC setInkTransferHook)
	Damage.ink_transfer_hook = _on_ink_transfer
	tree_exiting.connect(func(): Damage.ink_transfer_hook = Callable())

	# 教程标记一次性消费 (与 mode 正交; 读出后清空, 不污染下一局) — 须在 _build_teams 前
	_is_tutorial = GameState.tutorial
	GameState.tutorial = false

	# 规则之日: TeamSelect 选好写进 GameState, 这里读出后清空 (PoC scene.start data.rule)
	# dungeon 用整局规则 dungeon_rule (跨关沿用, 不消费); 其余模式用 battle_rule (消费一次)
	rule = GameState.dungeon_rule if GameState.mode == "dungeon" else GameState.battle_rule
	GameState.battle_rule = ""
	GameState.reset_battle_economy()   # 清野生敌方钱包 (B 经济, 开局重置)

	_setup_bg()
	# 装备席跨关库存恢复 (dungeon stage>1, 1:1 PoC benchInventoryIds; 须在建装备席 HUD 前)
	if GameState.mode == "dungeon" and GameState.dungeon_stage > 1:
		bench_inventory = GameState.dungeon_carry_bench.duplicate()
	elif GameState.mode == "duallane":
		# 双路: 备战席与 GameState.bench_inventory【共享同一数组引用】。商店 buy_shop_item / try_merge_bench /
		#   equip_to_turtle 全是原地 append/remove_at 改 GameState.bench_inventory; 而 rail渲染/_bench_idx_of/装备
		#   读 BattleScene.bench_inventory。原来这是两个独立数组 → 买的货进了 GameState 那个, 这边永远空 →
		#   "整个没有图 + 装备不了"。共享引用后买入即进席、即可拖装, 且跨路自动带库存 (GameState autoload 不随场景销毁)。
		bench_inventory = GameState.bench_inventory
	# D5 训龟大师口哨: test 沙盒模式预置 1 个进席, 方便即时试吹 (正式获取=中立生物掉落 25%/装备掉落 5%, 待 neutral-Phase2 接)
	if GameState.mode == "test":
		bench_inventory.append("e_master_whistle")
	# 双路无头冒烟 (dev): DUALLANE_SMOKE=1 → 起 3v3 双路 + 双方AI + 跳演出停顿 自动跑到底, 验不崩.
	if OS.has_environment("DUALLANE_SMOKE_FINAL") and GameState.mode != "duallane":
		# 终极战场冒烟: 左2幸存(带血) vs 右0 → 右蛋立即登场 ×5/自损凿穿 (验终极build+egg×5路径)
		auto_battle = true; auto_play_debug = true
		GameState.reset_dual_lane(); GameState.mode = "duallane"; GameState.current_lane = "final"
		GameState.dual_survivors = {
			"left": [{"id": "basic", "hp": 300, "maxHp": 450, "level": 1}, {"id": "stone", "hp": 200, "maxHp": 600, "level": 1}],
			"right": []}
		var ehpf: int = Phase2Config.egg_hp(1)
		GameState.egg_hp = {"left": ehpf, "right": ehpf}; GameState.egg_hp_max = {"left": ehpf, "right": ehpf}
	elif OS.has_environment("DUALLANE_SMOKE") or OS.has_environment("SMOKE_CLICK"):
		auto_battle = true
		auto_play_debug = true   # 跳过 banner/演出真实计时, 让对战快速跑完到攻蛋
		_smoke_click = OS.has_environment("SMOKE_CLICK")   # 此模式: 玩家回合用注入真实点击代替 emit (测点击命中)
		if _smoke_click:
			auto_battle = false   # 左队必须保持【手动】(才会走选龟框→注入点击); 右队 side!=left 仍自动 AI
		if GameState.mode != "duallane":
			GameState.setup_dual_lane(["basic", "stone", "bamboo"], ["rainbow", "lightning", "phoenix"], 1)
	# 整局渲染探针 (dev): SHOT_BATTLE=1 → 强 test 模式(跳初始装备 gate) + 双 AI 自动跑 → 间隔截帧, 我方自验实战视觉.
	if OS.has_environment("SHOT_BATTLE"):
		GameState.mode = "test"
		auto_battle = true
		auto_play_debug = true
	_build_teams()
	battle_stats.register_all(fighters)   # 预登记 6 龟 (含召唤), 结算面板用
	_build_slot_views()
	_build_duallane_equip_displays()   # 双路: 龟周围展示已装备装备
	_create_action_panel()                # 玩家操作面板 (左队手动选技能/目标)
	banner_layer = CanvasLayer.new()      # 回合横幅层
	banner_layer.layer = 20
	add_child(banner_layer)
	fx_layer = CanvasLayer.new()          # 全屏特效层 (cut-in) — 比横幅高, 但 layer 仍是 CanvasLayer (不随相机)
	fx_layer.layer = 18                   # 在 banner(20) 之下、操作面板/UI 之下, 盖住世界层 (龟/VFX)
	add_child(fx_layer)
	_log_init()
	_style_top_chrome()   # 标题药丸 + 日志开关 (1:1 PoC BattleTopRow turn-banner + 📜 toggle)
	_create_battle_hud()  # 浮层 HUD: GlobalToolbar(图标行) + StatsRail(深海币+羁绊) + BenchRail(装备席)
	_enter_battle_envelop()   # 战斗 cover 铺满窗口 (1:1 PoC Scale.ENVELOP), 退出 _exit_tree 还原
	return_button.pressed.connect(_on_return_pressed)

	# BGM: boss 关用 boss 曲, 其他用 battle (跟 Phaser 同款)
	var is_boss := GameState.mode == "dungeon" and GameState.is_dungeon_boss_stage()
	Audio.play_bgm("boss" if is_boss else "battle", 0.9, 0.35)   # 1:1 PoC battle/boss BGM 0→0.35, 900ms Sine.easeIn

	# 动画逐帧比对探针 (dev only): SHOT_ANIM=<skill_idx> 强制 左0 用该技能打 SHOT_TARGET, 截一串帧→quit
	if OS.has_environment("SHOT_ANIM"):
		await _anim_probe()
		return
	# 选目标圈探针 (dev only): SHOT_RINGS=1 → 在右队画选目标圈 + 停, 供截图验对位/脉冲
	if OS.has_environment("SHOT_RINGS"):
		await get_tree().create_timer(0.3).timeout
		_show_target_rings([1, 3, 5], "enemy")
		return
	# 初始装备 modal 探针 (dev only): SHOT_EQUIP=1 → 弹 modal + 停, 供截图验
	if OS.has_environment("SHOT_EQUIP"):
		await get_tree().create_timer(0.3).timeout
		await _show_initial_equip_pick_modal()
		return
	# 信息面板截图探针 (dev only): SHOT_DETAIL=<fighter_idx> → 开该龟详情面板 + 截 res://_detail_shot.png → quit (须带显示器跑, 非--headless)
	if OS.has_environment("SHOT_DETAIL"):
		await _detail_shot_probe()
		return
	# VFX 截帧探针 (dev only): SHOT_VFX=<key> → 在 fighters[SHOT_TARGET] 上播该 VFX, 截一串帧 _gvfx_N.png → quit (须带显示器)
	if OS.has_environment("SHOT_VFX"):
		await _vfx_probe()
		return
	# 初始装备选择 (1:1 PoC: 第1回合开局我方3选1, 野生/PVP敌方随机1; dungeon仅stage1; test/boss跳过)
	await _maybe_run_initial_equip_phase()
	# P221 教程: 预置装备席(1装备+1消耗品供拖拽教学) + 启动步骤引导 (1:1 PoC setupTutorialGuide)
	if _is_tutorial:
		_setup_tutorial_guide()
	if OS.has_environment("SHOT_BUFF"):   # dev: 预置 5 单体 buff 进席, 验渲染
		for bd in ShopData.BUFF_POOL:
			if str(bd.get("kind", "")) == "single":
				var bid := "%s#%d" % [str(bd["id"]), _buff_bench_seq]
				_buff_bench_seq += 1
				_bench_buff_items[bid] = bd
				bench_inventory.append(bid)
		_rebuild_bench_rail()
	# 0.5s 后开打 (让玩家先看清布局)
	await get_tree().create_timer(0.5).timeout
	await _pirate_opening_barrage()   # 海盗龟开局轰击 (PoC battle-setup, 在第 1 回合前)
	if not _check_end():
		_battle_loop()
	else:
		_show_result()
	if OS.has_environment("SHOT_BATTLE"):
		_battle_shot_probe()


## 整局渲染探针 (dev, SHOT_BATTLE 才跑): 双 AI 自动战进行时, 按间隔连续截帧 res://_gbattle_NN.png → quit.
##   我方"自己 F5"用: 看实战中的技能动画/飘字/血条/死亡/召唤是否正常. 须带显示器(非 --headless).
func _battle_shot_probe() -> void:
	var n: int = int(OS.get_environment("SHOT_BATTLE_FRAMES")) if OS.has_environment("SHOT_BATTLE_FRAMES") else 18
	var iv: float = float(OS.get_environment("SHOT_BATTLE_IV")) if OS.has_environment("SHOT_BATTLE_IV") else 0.45
	var summon: String = OS.get_environment("SHOT_BATTLE_SUMMON") if OS.has_environment("SHOT_BATTLE_SUMMON") else ""
	for i in range(n):
		await get_tree().create_timer(iv).timeout
		if not is_instance_valid(self) or not is_inside_tree():
			return   # 战斗结束切场 → 本节点已释放, 停止截帧 (进程由外层 timeout 收尾)
		if summon == "bear" and i == 1 and fighters.size() > 0:
			_spawn_big_bear(fighters[0])   # 直接走真实召唤管线 → 验登场渲染/弹跳/sprite/无崩
		var vp := get_viewport()
		if vp == null:
			return
		vp.get_texture().get_image().save_png("res://_gbattle_%02d.png" % i)
	get_tree().quit()


## 动画逐帧探针 — 强制 fighters[0] 用技能, 在固定偏移截帧 res://_ganim_N.png (dev, SHOT_ANIM 才跑)
## 信息面板截图探针: 开 fighters[SHOT_DETAIL] 的详情面板, 等布局结算, 截图存盘 → quit. (须带显示器跑)
func _detail_shot_probe() -> void:
	await get_tree().create_timer(0.4).timeout
	var idx: int = int(OS.get_environment("SHOT_DETAIL"))
	if idx < 0 or idx >= fighters.size():
		idx = 0
	if OS.has_environment("SHOT_DETAIL_RICH"):   # 注入测试态: 状态徽章 + 装备 (验状态区/装备格渲染)
		var rf: Dictionary = fighters[idx]
		rf["buffs"] = [
			{"type": "atkUp", "value": 20, "duration": 3},
			{"type": "defDown", "value": 15, "duration": 2},
			{"type": "burn", "value": 4, "duration": 999},
			{"type": "stun", "duration": 1},
		]
		rf["_shockStacks"] = 3
		rf["_inkStacks"] = 2
		# 注入 stoneWall 被动 + 坚壁资源 → 验 HP 下资源条(wall-bar)渲染 (R10)
		rf["passive"] = {"type": "stoneWall", "maxDefInitPct": 100, "name": "磐石之躯"}
		rf["_stoneDefGained"] = 24
		rf["_initDef"] = int(rf.get("baseDef", rf.get("def", 20)))
		var eqs: Array = []
		for e in DataRegistry.all_equipment:
			if str(e.get("icon", "")).ends_with(".png"):
				eqs.append(str(e.get("id", "")))
			if eqs.size() >= 4:
				break
		rf["_equipped_ids"] = eqs
	var chest_mode: bool = OS.has_environment("SHOT_DETAIL_CHEST")
	if chest_mode:   # 注入宝箱龟 + 专属装备 → 验"只看专属装备"模式
		var cf: Dictionary = fighters[idx]
		cf["passive"] = {"type": "chestTreasure", "name": "宝藏", "thresholds": [80, 130, 240, 360, 590]}
		cf["_chestTreasure"] = 95
		cf["_chestTier"] = 1
		cf["_chestEquips"] = [
			{"id": "x1", "name": "海螺号角", "icon": "📯", "desc": "专属测试A"},
			{"id": "x2", "name": "测试盾", "icon": "", "desc": "专属测试B"},
		]
	_build_fighter_detail(fighters[idx], chest_mode)
	for _i in range(10):                       # 等 Control 容器多帧布局结算
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var popup_kind: String = OS.get_environment("SHOT_DETAIL_POPUP") if OS.has_environment("SHOT_DETAIL_POPUP") else ""
	if popup_kind == "equip":
		var pid := ""
		for e in DataRegistry.all_equipment:
			if str(e.get("icon", "")).ends_with(".png"):
				pid = str(e.get("id", "")); break
		if pid != "":
			_show_equip_popup(pid)
	elif popup_kind == "skill":
		_show_skill_desc_popup("龟盾", "", "[b]测试[/b] 技能描述文本", "")
	if popup_kind != "":
		for _i2 in range(8):
			await get_tree().process_frame
		await get_tree().create_timer(0.4).timeout
	var out_path: String = OS.get_environment("SHOT_DETAIL_OUT") if OS.has_environment("SHOT_DETAIL_OUT") else "res://_detail_shot.png"
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT_DETAIL] saved ", out_path, " fighter=", fighters[idx].get("name", "?"))
	get_tree().quit()


## VFX 截帧探针: 在 fighters[SHOT_TARGET] 上直接播某 VFX, 按偏移截帧 → quit. (须带显示器)
func _vfx_probe() -> void:
	await get_tree().create_timer(0.6).timeout
	var key: String = OS.get_environment("SHOT_VFX")
	var tgt: int = int(OS.get_environment("SHOT_TARGET")) if OS.has_environment("SHOT_TARGET") else 1
	if tgt < 0 or tgt >= slot_nodes.size():
		tgt = 1
	match key:
		"crystal":
			_play_screen_shake(0.30, 11.0)
			_flash_hit(tgt)
			_play_crystal_detonate(tgt)
		"fireball":
			_play_fireball(0, tgt if tgt >= 3 else 3)
		"projectile":
			_fire_projectile(0, tgt if tgt >= 3 else 3, "res://assets/sprites/equip/dungeon-dart.png", 30.0, 0.34)
		"firesweep":
			_play_fire_sweep(0, tgt if tgt >= 3 else 5)
		"crystalbeam":
			_play_crystal_beam(0, tgt if tgt >= 3 else 3)
		"chainbolt":
			_play_chain_bolt(0, tgt if tgt >= 3 else 3)
			_play_chain_bolt(tgt if tgt >= 3 else 3, 4)
			_play_chain_bolt(4, 5)
		"minicrystalbeam":
			_play_mini_crystal_beam(0)
		"egg":
			# 龟蛋待机动画验: 直接 _make_slot_view 渲染一只龟蛋单位 (3帧 idle), 跨帧截图比对是否 wobble (动) 而非整张 sheet (静).
			var egg_cfg := {
				"id": "egg", "name": "龟蛋基地", "emoji": "🥚", "rarity": "C", "side": "left",
				"img": "pets/egg.png", "sprite": {"frames": 3, "frameW": 79, "frameH": 80, "duration": 900},
				"_level": 1, "_maxEnergy": 0, "passive": null,
				"hp": 1000, "maxHp": 1000, "shield": 0, "_equipped_ids": [], "equipment": [],
			}
			var ev := _make_slot_view(egg_cfg, Vector2(640, 430))
			ev.scale = Vector2(2.2, 2.2)   # 放大看清像素帧差
			slots_root.add_child(ev)
		"floats":
			# 飘字居中验: 多只龟各冒不同位数数字 → 截首帧(飞行前)看是否水平居中于龟身 (PoC origin0.5)
			_spawn_float_text(0, 7, "damage", "physical", false)
			_spawn_float_text(1, 888, "damage", "magic", false)
			if slot_nodes.size() > 3:
				_spawn_float_text(3, 9999, "damage", "true", true)
		"hpdrain":
			# 血条掉血验: 直接砍半 fighters[tgt] HP → 触发红 delay trail (hold200ms→drain500ms) + 60ms白闪
			if tgt < fighters.size():
				var hf: Dictionary = fighters[tgt]
				var half: float = float(hf.get("maxHp", 100)) * 0.5
				hf["hp"] = int(half)
				_refresh_slot(tgt, half)
		"death":
			# 死亡演出验: 直接置死 tgt → _play_death (碎裂粒子+hop+倾倒+灰度+淡出)
			if tgt < fighters.size():
				fighters[tgt]["alive"] = false
				_play_death(tgt)
	var offsets: Array = [0.05, 0.30, 0.55, 0.80, 1.05] if key == "egg" \
		else [0.15, 0.45, 0.75, 1.05, 1.35] if key == "minicrystalbeam" \
		else [0.04, 0.1, 0.18, 0.28, 0.42, 0.5]
	var prev: float = 0.0
	for i in range(offsets.size()):
		var wait: float = float(offsets[i]) - prev
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		prev = float(offsets[i])
		get_viewport().get_texture().get_image().save_png("res://_gvfx_%d.png" % i)
	get_tree().quit()


func _anim_probe() -> void:
	await get_tree().create_timer(0.6).timeout   # 让布局稳定 (跳过开场)
	var sk: int = int(OS.get_environment("SHOT_ANIM"))
	var tgt: int = int(OS.get_environment("SHOT_TARGET")) if OS.has_environment("SHOT_TARGET") else 1
	_take_turn(0, sk, tgt)   # 不 await → 动画并发跑, 下面按偏移截帧
	var offsets: Array = [0.0, 0.12, 0.25, 0.4, 0.55, 0.75, 1.0, 1.3, 1.7, 2.2]
	var prev: float = 0.0
	for i in range(offsets.size()):
		var wait: float = float(offsets[i]) - prev
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		prev = float(offsets[i])
		get_viewport().get_texture().get_image().save_png("res://_ganim_%d.png" % i)
	get_tree().quit()


## 背景按模式路由 (1:1 PoC battle-setup.js:148-159 / BattleScene.ts:847-870)
##   boss → ruins / dungeon → 关卡键 / test → 随机9选1 / 其他(野生/自定义) → sakura
func _setup_bg() -> void:
	var bg_key := "bg-sakura"
	if GameState.mode == "dungeon":
		var stage: int = GameState.dungeon_stage
		bg_key = "bg-sakura" if stage <= 1 else \
			"bg-oasis" if stage == 2 else \
			"bg-cave-alt" if stage == 3 else \
			"bg-ice" if stage == 4 else "bg-ruins"
		if GameState.is_dungeon_boss_stage():
			bg_key = "bg-ruins"
	elif GameState.mode == "test":
		var maps := ["bg-sakura", "bg-cave-alt", "bg-firefly", "bg-forest",
			"bg-ice", "bg-oasis", "bg-ruins", "bg-shipwreck", "bg-underwater"]
		bg_key = maps[randi() % maps.size()]
	if OS.has_environment("SHOT_BG"):
		bg_key = OS.get_environment("SHOT_BG")   # dev: 强制背景 (与 PoC 对齐做像素 diff)
	var path := "res://assets/sprites/bg/%s.png" % bg_key
	if ResourceLoader.exists(path):
		background.texture = load(path)


func _on_return_pressed() -> void:
	# dungeon 胜(非BOSS) = 推进下一关(不是放弃, 不弹确认; GameState 自动顶 hp + 换敌)
	if GameState.mode == "dungeon":
		var player_alive := false
		for f in fighters:
			if f.get("side", "") == "left" and f.get("alive", false):
				player_alive = true
				break
		if player_alive and not GameState.is_dungeon_boss_stage():
			GameState.advance_stage()
			_setup_next_dungeon_stage()
			get_tree().change_scene_to_file("res://scenes/Battle.tscn")
			return
	# 其余 = 放弃退出(本局进度会丢) → 弹确认浮层 (1:1 PoC confirmSurrender; 修"点退出直接退、无确认")
	_show_surrender_confirm()


## 退出确认浮层 (1:1 PoC confirmSurrender): 取消/点遮罩=关, 确定=真退出。防误触丢整局。
func _show_surrender_confirm() -> void:
	var layer := CanvasLayer.new()
	layer.add_to_group("ui_modal")
	layer.layer = 220
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			layer.queue_free())   # 点遮罩 = 取消 (同 PoC)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.086, 0.118, 0.188, 0.98)
	csb.border_color = Color("#ff6b6b")
	csb.set_border_width_all(3)
	csb.set_corner_radius_all(10)
	csb.content_margin_left = 22; csb.content_margin_right = 22
	csb.content_margin_top = 18; csb.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", csb)
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)
	var title := Label.new()
	title.text = "⚠ 退出战斗"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color("#ff6b6b"))
	vb.add_child(title)
	var body := Label.new()
	body.text = "真的要放弃这场战斗吗？\n本局进度将丢失。"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color("#dddddd"))
	vb.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(func() -> void: layer.queue_free())
	row.add_child(cancel)
	var ok := Button.new()
	ok.text = "确定退出"
	ok.custom_minimum_size = Vector2(120, 40)
	ok.pressed.connect(func() -> void:
		layer.queue_free()
		_do_return_exit())
	row.add_child(ok)


## 确认后真正执行退出路由。
func _do_return_exit() -> void:
	if GameState.mode == "dungeon":
		GameState.reset_dungeon()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	if GameState.mode == "duallane":
		GameState.reset_dual_lane()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")   # 放弃整局 → 主菜单 (原落 TeamSelect 丢整局且更糟)
		return
	get_tree().change_scene_to_file("res://scenes/TeamSelect.tscn")   # single → 选龟


## 进下一关前: 给 GameState.right_team 随机抽 3 龟 (按 dungeon_stage 加难度)
## HP 继承靠 _build_teams 在 Battle._ready 里读 dungeon_carry_hp 实现.
func _setup_next_dungeon_stage() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Array = []
	for pet in DataRegistry.launch_pets:
		var pid: String = pet["id"]
		if not (pid in GameState.left_team):
			pool.append(pid)
	pool.shuffle()
	var new_right: Array[String] = []
	for i in range(3):
		new_right.append(pool[i % pool.size()])
	GameState.right_team = new_right


# ─── 初始化 ────────────────────────────────────────────────────

func _build_teams() -> void:
	# GameState 有数据(从 TeamSelect 来) → 用; 没有(直接跑 Battle 调试) → 用默认阵容
	var left_ids: Array[String] = GameState.left_team if GameState.has_team() else DEFAULT_LEFT
	var right_ids: Array[String] = GameState.right_team if GameState.has_team() else DEFAULT_RIGHT
	# 二阶段双路龟蛋 (壳): 按 current_lane 取该路 3 龟开打, 复用 3v3 机制.
	#   不足 3 用小将补位(MINION_FILL, 占位先补 basic). 龟蛋受击/路序/final 仍待接 (见 phase2_duallane).
	if GameState.mode == "duallane":
		if GameState.current_lane == "final":
			# 终极战场: 两路幸存者带血汇合 (不补小将; HP 在 _build_teams 末尾按快照覆盖)
			left_ids = []
			for s in GameState.dual_survivors.get("left", []):
				left_ids.append(str(s["id"]))
			right_ids = []
			for s in GameState.dual_survivors.get("right", []):
				right_ids.append(str(s["id"]))
		else:
			var ll: Array = GameState.lane_assign.get(GameState.current_lane, [])
			var rr: Array = GameState.enemy_lane_assign.get(GameState.current_lane, [])
			left_ids = []; left_ids.assign(ll.slice(0, 3))   # 该路统领 0-3 只, 不足由深海小将补位(见下)
			right_ids = []; right_ids.assign(rr.slice(0, 3))
	if GameState.mode == "test":
		right_ids = ["basic", "basic", "basic", "basic", "basic", "basic"]   # PoC ts:269 — 6 木桩占满 6 槽
	if _is_tutorial:
		# 1:1 PoC startTutorialBattle: 固定阵容 我方 Lv7 石头F1·小龟B0·竹叶B2 / 敌 Lv1 钻石F0·天使F2·忍者B1
		left_ids.assign(["stone", "basic", "bamboo"])
		right_ids.assign(["diamond", "angel", "ninja"])

	# 闯关难度缩放 (1:1 PoC DUNGEON_STAGES: 关1=0.85 / 关2=1.0 / 关3=1.1 / 关4=1.2 / 关5BOSS=3.0hp·1.25atk·1.4def)
	var enemy_hp_mult := 1.0
	var enemy_atk_mult := 1.0
	var enemy_def_mult := 1.0
	if GameState.mode == "dungeon":
		var st: int = GameState.dungeon_stage
		var hp_by := [0.85, 1.0, 1.1, 1.2, 3.0]
		var atk_by := [0.85, 1.0, 1.1, 1.2, 1.25]
		var def_by := [0.85, 1.0, 1.1, 1.2, 1.4]
		var si: int = clampi(st - 1, 0, 4)
		enemy_hp_mult = hp_by[si]; enemy_atk_mult = atk_by[si]; enemy_def_mult = def_by[si]
	elif GameState.mode == "boss-pick":
		enemy_hp_mult = 3.5; enemy_atk_mult = 1.2; enemy_def_mult = 1.4   # 指定 Boss 倍率 (PoC)
	# Boss 敌方标记 (1:1 PoC BattleScene.ts:1213-1216): boss/boss-pick 模式 或 dungeon 第5关 → 右队是 Boss
	var is_boss_enemy: bool = (GameState.mode in ["boss", "boss-pick"]) \
		or (GameState.mode == "dungeon" and GameState.is_dungeon_boss_stage())

	# 先各自建队, 再按 PoC 布阵规则赋 _slotKey (玩家手动/默认前排, 敌方 autoAssign)
	var left_fighters: Array = []
	var right_fighters: Array = []
	# 左队 (常规 3; 双路按该路统领数, 不足补小将) + HP 继承
	for i in range(left_ids.size()):
		var l_opts: Dictionary = {}
		if _is_tutorial:
			l_opts["level"] = 7   # 教程我方统一 Lv7
		else:
			l_opts["level"] = GameState.get_pet_level(left_ids[i])   # 玩家各自存档等级 (1:1 PoC resolveLevel petState.levels)
		if GameState.loadouts.has(left_ids[i]):
			l_opts["equipped_idxs"] = GameState.loadouts[left_ids[i]]
		var l: Dictionary = FighterFactory.create(left_ids[i], "left", l_opts)
		if GameState.mode == "dungeon":
			# 跨关重装上关身上装备 (★在 HP 结算前 → maxHp 含装备加成, 1:1 PoC :1487-1496, 修"装备每关全丢")
			var carried: Array = GameState.dungeon_carry_equips.get(l["id"], [])
			if not carried.is_empty():
				for eq_id in carried:
					EquipmentRuntime.on_attach(l, eq_id)
					if not l.has("_equipped_ids"):
						l["_equipped_ids"] = []
					(l["_equipped_ids"] as Array).append(eq_id)
				StatsRecalc.snapshot_base(l)
				StatsRecalc.recalc(l)
			# 跨关 HP 继承 (1:1 PoC BattleScene.ts:1480-1513 playerHpSnapshot):
			#   存活龟 → 回满血 (PoC:1505-1507 / JS dungeon.js:191); 阵亡龟 → 70% HP 复活 (PoC:1498-1503).
			if GameState.dungeon_dead_ids.has(l["id"]):
				l["hp"] = roundi(int(l["maxHp"]) * 0.7)   # PoC:1500 Math.round(maxHp*0.7)
				l["shield"] = 0                            # PoC:1501
				l["alive"] = true                          # PoC:1502
				if is_instance_valid(battle_log):
					battle_log.append_text("[color=#ffd166]✨ %s 跨关复活 (70%% HP)[/color]\n" % str(l.get("name", l["id"])))   # PoC:1503
			elif GameState.dungeon_carry_hp.has(l["id"]):
				# 存活龟: PoC 实际回满血 (snap.alive!=false → maxHp). carry_hp 仅作存活判定锚.
				l["hp"] = l["maxHp"]; l["shield"] = 0
		left_fighters.append(l)
	# 敌队 (右队大小可变 — BOSS 关 1 只, 否则 3) + 阶段倍率
	for i in range(right_ids.size()):
		var r_opts: Dictionary = {}
		if _is_tutorial:
			r_opts["level"] = 1   # 教程敌方统一 Lv1
		else:
			# 敌方等级 = 玩家队伍平均 (1:1 PoC effectiveSideLevel computeAvgFromSaved)
			var lv_sum := 0
			for lid in left_ids:
				lv_sum += GameState.get_pet_level(lid)
			r_opts["level"] = clampi(roundi(float(lv_sum) / maxf(1.0, left_ids.size())), 1, 10)
		var r: Dictionary = FighterFactory.create(right_ids[i], "right", r_opts)
		if enemy_hp_mult != 1.0:
			r["maxHp"] = roundi(r["maxHp"] * enemy_hp_mult); r["hp"] = r["maxHp"]
		if enemy_atk_mult != 1.0:
			r["baseAtk"] = roundi(r["baseAtk"] * enemy_atk_mult); r["atk"] = r["baseAtk"]
		if enemy_def_mult != 1.0:
			r["baseDef"] = roundi(r["baseDef"] * enemy_def_mult); r["def"] = r["baseDef"]
			r["baseMr"] = roundi(int(r.get("baseMr", r.get("def", 0))) * enemy_def_mult); r["mr"] = r["baseMr"]
		# Boss 标记: 放大立绘(_make_slot_view 读)/boss 血条尺寸/击杀+30/名字前缀 (1:1 PoC ts:1213-1216)
		if is_boss_enemy:
			r["_isBoss"] = true
			r["name"] = "BOSS " + str(r.get("name", r["id"]))
		if GameState.mode == "test":
			# 训练沙盒: 6 假人(练习靶). 高HP(99999)耐打但仍有限可击杀, 0 atk/def/mr/crit, 无技能/被动 → 不还手.
			#   AI skip 由 _isDummy 标记: _run_side_turn 的 can_act 过滤排掉(BattleScene.gd:1548) → 假人永不出手.
			#   不设 _untargetable: 假人须可被选作攻击目标(练技能/装备), 且计入 _is_combatant → 战斗不秒胜.
			#   (PoC applyEnemyModeMods test ts:328-338 用 2000HP 木桩; 这里改高HP假人, 沙盒久练不被速杀.)
			r["maxHp"] = 99999; r["hp"] = 99999
			r["_initHp"] = 99999   # fighter.create 在覆盖前已按 basic 龟 HP 烘焙 _initHp → 同步到假人值
			r["baseAtk"] = 0; r["atk"] = 0
			r["baseDef"] = 0; r["def"] = 0
			r["baseMr"] = 0; r["mr"] = 0
			r["crit"] = 0
			r["skills"] = []
			r["passive"] = null
			r["emoji"] = "🎯"
			r["name"] = "假人 %d" % (i + 1)
			r["_isDummy"] = true
		right_fighters.append(r)

	# 闯关累积加成 (RewardPick/ChoiceEvent 给的 TeamBonus stat 类) 应用到左队 base — PoC applyTeamBuff。
	#   ★装备类奖励不在此 (那是一次性进装备席, 见 RewardPick/ChoiceEvent → dungeon_carry_bench), 否则每关重复装。
	if GameState.mode == "dungeon" and not GameState.dungeon_bonuses.is_empty():
		for lf in left_fighters:
			for bonus in GameState.dungeon_bonuses:
				if bonus.get("kind", "") != "equip":   # equip 跳过 (一次性入席, 不每关 re-apply)
					_apply_team_bonus(lf, bonus)

	# 二阶段双路: 该路不足 3 名统领 → 自动补深海小将到各方 3 名 (设计 V3.2 §3; 终极战场不补小将)
	if GameState.mode == "duallane" and GameState.current_lane != "final":
		_fill_lane_minions(left_fighters, "left")
		_fill_lane_minions(right_fighters, "right")

	# 玩家侧: 有 TeamSelect 传槽就用, 否则默认前 N 槽 (3 龟 = front-0/1/2 全前排) — PoC defaultSlotKeys
	var left_slots: Array = GameState.left_slots if GameState.has_team() and not GameState.left_slots.is_empty() else SlotHelpers.default_slot_keys(left_fighters.size())
	if _is_tutorial:
		left_slots = ["front-1", "back-0", "back-2"]   # 1:1 PoC 教程固定站位
	_assign_slots(left_fighters, left_slots)
	# 敌方侧: test 模式固定 6 槽 (ts:270, 不能被 autoAssign 3v3 覆盖); 否则 autoAssign (effHp 降序 + 菱形阵)
	var right_slots: Array = ["front-0", "front-1", "front-2", "back-0", "back-1", "back-2"] if GameState.mode == "test" else SlotHelpers.auto_assign_slots(right_fighters)
	if _is_tutorial:
		right_slots = ["front-0", "front-2", "back-1"]   # 1:1 PoC 教程固定站位
	_assign_slots(right_fighters, right_slots)

	# 小将攻击系数随【最终槽位】重算 (1:1 设计文档§3: 前排挥砍1.4× / 后排射击1.5×).
	#   make_minion 按建时槽位烘焙 atkScale, 但 _assign_slots 之后槽位(尤其敌方 auto_assign 菱形阵)会变 →
	#   不重算则后排小将仍按前排 1.4× 出手, "后排射击 1.5×"从不生效 (小将审计 #1/#2).
	for _mf in left_fighters + right_fighters:
		if _mf.get("_isMinion", false):
			var _is_back: bool = str(_mf.get("_position", "front")) == "back"
			var _mscale: float = Minion.BACK_ATK_MULT if _is_back else Minion.FRONT_ATK_MULT
			_mf["_minionAtkMult"] = _mscale
			var _msk: Array = _mf.get("skills", [])
			if not _msk.is_empty() and _msk[0] is Dictionary:
				_msk[0]["atkScale"] = _mscale
				_msk[0]["name"] = "射击" if _is_back else ("整排挥砍" if _msk[0].get("eliteRowSplit", false) else "挥砍")
			# 立绘随【最终槽位】重选 (1:1 make_minion: elite→精英 / front→砍 / back→射): _assign_slots 后槽位变(敌方菱形阵)→
			#   不重选则 back 小将仍用 front 砍立绘 (小将前/后皮没跟槽位重算). 在 _make_slot_view 读 img 前改, 即生效.
			_mf["img"] = Minion.minion_img(_mf.get("_isElite", false), _is_back)

	# 按"左0,右0,左1,右1,..."交替入 fighters[] (右队可变: test 6 / boss 1 / 常规 3)
	var pair_n: int = maxi(left_fighters.size(), right_fighters.size())
	for i in range(pair_n):
		if i < left_fighters.size():
			fighters.append(left_fighters[i])
		if i < right_fighters.size():
			fighters.append(right_fighters[i])

	# 装备模型 (1:1 PoC): 龟开战【0 件初始装备】, 装备席 bench_inventory 开战也为空 (PoC BattleScene.ts:311)。
	#   装备来源 = 初始 3 选 1 + 战中商店 + 装备席(战中掉落/dungeon跨关). 不碰 GameState.inventory 自创累加器。

	# 二阶段装备: 逐星基础属性加到携带者 (snapshot 前, 让 recalc 折入) + 存 _p2_equips 供战斗钩子。
	for f in fighters:
		# side 命名空间 (2026-06-24): right 队龟身键带 "right::" 前缀, 防左右同名龟(都 basic)串读玩家装备。
		var _eqkey: String = GameState.p2eq_key(str(f.get("side", "left")), str(f.get("id", "")))
		var p2items: Array = GameState.equipped_p2.get(_eqkey, [])
		if p2items.is_empty():
			continue
		var p2list: Array = []
		for it in p2items:
			if not (it is Dictionary):
				continue
			var iid: String = str(it.get("id", ""))
			var ist: int = int(it.get("star", 1))
			Phase2EquipRuntime.apply_stats(f, iid, ist)
			# 010 激光长刃: 授予【横扫】主动技 (0龟能), 追加进携带者技能栏 (type=p2Sweep → SkillHandlers)
			if iid == "p2eq_010":
				if not f.has("skills"):
					f["skills"] = []
				(f["skills"] as Array).append({
					"type": "p2Sweep", "name": "⚡横扫", "energyCost": 0, "cd": 0, "cdLeft": 0, "hits": 1, "icon": "📏",
					"p2Star": ist, "target": "enemy",
					"brief": "横扫一列(3★全体)敌人; 只命中1则竖斩(+身后50%); 回复全程伤害%d%%" % [35, 80, 100][clampi(ist, 1, 3) - 1],
					"desc": "横扫一列(3★全体)敌人; 只命中1则竖斩(+身后50%); 回复全程伤害%d%%" % [35, 80, 100][clampi(ist, 1, 3) - 1],
				})
			p2list.append({"id": iid, "star": ist})
		f["_p2_equips"] = p2list

	# W7 v2: 装备 apply 改完 base 后 snapshot crit/armorPen/lifesteal, 再 recalc 一次
	#   (让 buff 系统从 base 重算; 此时无 buff, recalc 仅把 _lifestealPct 折入 lifestealPct 等)
	for f in fighters:
		StatsRecalc.snapshot_base(f)
	StatsRecalc.recalc_all(fighters)
	# 详情面板 增益绿/减益红 基线: 战斗开始(装备+recalc 后、局内 buff 前)快照各属性到 _initXxx。
	#   之后 buff/debuff/战中装备 偏离基线即着色。原 _initXxx 多数从未设 → 默认=当前值 → 永不着色("数字没变绿或红")。
	for f in fighters:
		f["_initAtk"] = int(f.get("atk", 0))
		f["_initDef"] = int(f.get("def", 0))
		f["_initMr"] = int(f.get("mr", f.get("def", 0)))
		f["_initCrit"] = float(f.get("crit", 0.0))
		f["_initArmorPen"] = int(f.get("armorPen", 0))
		f["_initMagicPen"] = int(f.get("magicPen", 0))
		f["_initLifesteal"] = roundi(float(f.get("lifestealPct", 0.0)) * 100.0)
		var _ov: float = maxf(0.0, float(f.get("crit", 0.0)) - 1.0)
		var _ovm: float = 1.5
		var _pp = f.get("passive")
		if _pp is Dictionary and float((_pp as Dictionary).get("overflowMult", 0.0)) > 0.0:
			_ovm = float((_pp as Dictionary).get("overflowMult", 1.5))
		f["_initCritDmg"] = roundi((1.5 + float(f.get("_extraCritDmgPerm", 0.0)) + _ov * _ovm) * 100.0)

	# 战斗开始一次性被动 (lavaEnhancedRage 满怒 / twoHead resilience+fusion / hiding 半血); fusion 改 base 后再 recalc
	_apply_start_passives()
	_spawn_summons()   # 缩头龟召唤随从 (读 _summonHpBase/hpPct), 追加进 fighters (随后建视图)
	_spawn_crystal_balls()   # 水晶龟 crystalBall: 登场召唤水晶球 (HP=本体50%, ATK=本体), 追加进 fighters
	_spawn_candy_bombs()     # 糖果龟 candyBombPassive: 登场召唤糖果炸弹 (HP=本体40%, 每回合衰减, 归零引爆)
	_spawn_candy_jars()      # 糖果龟 sweetTrap: 登场在己方席放糖果罐 (点击「打碎」按回合掉落)
	# 羁绊: 各队按 tags 激活协同 (改 baseAtk/crit/法穿/盾 + 设 _synergy* flag 供 consumer)
	#   ★二阶段双路: 移除老的乌龟羁绊 — 羁绊改为只存在于装备之间(套装, 见 Phase2Equip.detect_sets). 用户 2026-06-12.
	var left_team: Array = []
	var right_team: Array = []
	for f in fighters:
		if f.get("side", "") == "left":
			left_team.append(f)
		else:
			right_team.append(f)
	if GameState.mode != "duallane":
		Synergies.apply_team(left_team, right_team)
		Synergies.apply_team(right_team, left_team)
		_grant_luck_synergy(left_team, "left")    # 运气羁绊: 发物品到装备席 (1:1 PoC grantLuckSynergy:6034, 原flag从不消费)
		_grant_luck_synergy(right_team, "right")
	else:
		# 双路: 装备套装【学派】开场属性效果 (珊瑚+maxHP/深渊穿透); 每回合/受击/死亡类效果走后续钩子
		Phase2Schools.apply_team_start(left_team)
		Phase2Schools.apply_team_start(right_team)
		Phase2Types.apply_team_start(left_team)   # 12类型(职业)羁绊属性效果(同学派, 最终recalc前折入)
		Phase2Types.apply_team_start(right_team)
		_spawn_tentacles("left", left_team)       # 灵物[召唤]: 激活 → 1/2 无敌触手登场(每回合拍击+闪避追击, 规格#553)
		_spawn_tentacles("right", right_team)
		_hunt_pick_for_side("left")
		_hunt_pick_for_side("right")
	for f in fighters:
		StatsRecalc.snapshot_base(f)
	StatsRecalc.recalc_all(fighters)

	# 规则之日一次性应用 (狂暴 stat / 装备日发装 / 雷暴 crit) — PoC applyRuleStart, 在协同之后
	Rules.apply_rule_start(rule, left_team, right_team)
	# 规则改了 base/crit/装备 → 重新 snapshot(把规则后的值当新 base, 防 recalc 抹掉雷暴 crit)再算 + HP 同步
	for f in fighters:
		StatsRecalc.snapshot_base(f)
	StatsRecalc.recalc_all(fighters)
	for f in fighters:
		f["hp"] = f["maxHp"]
	# 终极战场: 幸存者带血进场 → 用快照 HP 覆盖满血 (须在上面 hp=maxHp 之后)
	if GameState.mode == "duallane" and GameState.current_lane == "final":
		_apply_survivor_hp()


## 终极战场: 把幸存者快照里的 HP 覆盖到对应 fighter (按 id; 龟在自己路唯一, id 不重).
func _apply_survivor_hp() -> void:
	for side in ["left", "right"]:
		var by_id: Dictionary = {}
		for s in GameState.dual_survivors.get(side, []):
			by_id[str(s["id"])] = s
		for f in fighters:
			if str(f.get("side", "")) == side and by_id.has(str(f.get("id", ""))):
				f["hp"] = mini(int(f["maxHp"]), int(by_id[str(f["id"])]["hp"]))


## 二阶段双路: 给某侧补深海小将到 3 名 (设计 V3.2 §3). arr 已有的是该路统领.
func _fill_lane_minions(arr: Array, side: String) -> void:
	var need: int = 3 - arr.size()
	if need <= 0:
		return
	var lv: int = maxi(1, int(GameState.dual_avg_level.get(side, 1)))   # 小将等级 = 选龟平均等级 (固定, 不随局内 buy经验 涨; 用户 Q1)
	var make_elite: bool = arr.size() == 0   # 空一路: 首个小将升「深海小将精英」
	for i in range(need):
		var slot := "front-%d" % ((3 - need) + i)
		arr.append(Minion.make_minion(lv, side, slot, make_elite and i == 0))


## 应用单条闯关加成到 fighter base (PoC RewardPickScene TeamBonus apply)
## 运气羁绊: 发物品到该侧装备席 (1:1 PoC grantLuckSynergy:6034; flag synergies.gd set 在 team[0] 但原从不消费=未实装).
##   tier2: 1 随机消耗品; tier3: 额外 1 随机装备(normal+unique). 左队进 bench_inventory; 右队仅清flag(无玩家装备席).
func _grant_luck_synergy(team: Array, side: String) -> void:
	var holder: Dictionary = {}
	for f in team:
		if int(f.get("_synergyLuckGrantConsumable", 0)) > 0 or int(f.get("_synergyLuckGrantEquip", 0)) > 0:
			holder = f
			break
	if holder.is_empty():
		return
	var side_name := "我方" if side == "left" else "敌方"
	if int(holder.get("_synergyLuckGrantConsumable", 0)) > 0:
		var pool: Array = []
		for e in DataRegistry.all_equipment:
			if e.get("category", "") == "consumable":
				pool.append(e)
		if not pool.is_empty():
			var eq = pool[randi() % pool.size()]
			if side == "left":
				bench_inventory.append(str(eq.get("id", "")))
			if is_instance_valid(battle_log):
				battle_log.append_text("[color=#ffd166]🎲 运气羁绊: %s获得消耗品「%s」[/color]\n" % [side_name, eq.get("name", "?")])
		holder["_synergyLuckGrantConsumable"] = 0
	if int(holder.get("_synergyLuckGrantEquip", 0)) > 0:
		var pool2: Array = []
		for e in DataRegistry.all_equipment:
			var c: String = e.get("category", "")
			if c == "normal" or c == "unique":
				pool2.append(e)
		if not pool2.is_empty():
			var eq2 = pool2[randi() % pool2.size()]
			if side == "left":
				bench_inventory.append(str(eq2.get("id", "")))
			if is_instance_valid(battle_log):
				battle_log.append_text("[color=#ffd166]🎲 运气羁绊: %s获得装备「%s」[/color]\n" % [side_name, eq2.get("name", "?")])
		holder["_synergyLuckGrantEquip"] = 0
	if side == "left":
		_rebuild_bench_rail()


func _apply_team_bonus(f: Dictionary, bonus: Dictionary) -> void:
	var kind: String = bonus.get("kind", "")
	var val: float = bonus.get("value", 0)
	match kind:
		"atk":
			f["baseAtk"] = roundi(f.get("baseAtk", 0) * (1.0 + val)); f["atk"] = f["baseAtk"]
		"hp":
			f["maxHp"] = int(f.get("maxHp", 0)) + int(val); f["hp"] = int(f.get("hp", 0)) + int(val)
		"crit":
			f["crit"] = f.get("crit", 0.0) + val
		"lifesteal":
			f["_lifestealPct"] = int(f.get("_lifestealPct", 0)) + int(val * 100)
		"shield":
			Buffs.grant_shield(f, int(val))
		"equip":
			var eid: String = bonus.get("equipId", "")
			if eid != "" and eid != "__unique_random__":
				EquipmentRuntime.on_attach(f, eid)
				if not f.has("_equipped_ids"):
					f["_equipped_ids"] = []
				(f["_equipped_ids"] as Array).append(eid)


# ─── 布阵 (1:1 PoC slot system, 逻辑在 SlotHelpers) ────────────

# 把 slot_keys 平行赋给 fighters: 写 _slotKey + _position(front/back 段)
func _assign_slots(team: Array, slot_keys: Array) -> void:
	for i in range(team.size()):
		var key: String = slot_keys[i] if i < slot_keys.size() else "front-0"
		team[i]["_slotKey"] = key
		team[i]["_position"] = "front" if key.begins_with("front") else "back"


## 朝向翻转判定 (1:1 PoC FACING_RIGHT_ASSETS, BattleScene.ts:1907-1910)。
##   实测: 全身 sprite sheet / 静态 body (pets/<id>.png) 资源**默认朝左**(基础/熔岩等已逐图核实) →
##   左队翻转(朝右向敌)、右队不翻(朝左向敌)。1:1 PoC: flipLeft=!FACING_RIGHT → left翻/right不翻。
##   FACING_RIGHT_ASSETS (hiding/mech 机甲) 默认朝右 → 反着: 右队翻、左队不翻。
##   (旧逻辑按"朝右头像"标定翻右队, 切全身 sheet 后资源变朝左 → 全反, 故此处改回 PoC 1:1)
func _should_flip_x(pet_id: String, side: String) -> bool:
	var faces_right: bool = pet_id in FACING_RIGHT_ASSETS
	if faces_right:
		return side == "right"
	return side == "left"


## 二阶段双路: 龟周围展示已装备的装备 (脚底下方一排 emoji). 用户 2026-06-12.
func _build_duallane_equip_displays() -> void:
	if GameState.mode != "duallane":
		return
	for i in range(mini(fighters.size(), slot_nodes.size())):
		var f: Dictionary = fighters[i]
		var node: Node2D = slot_nodes[i]
		if not is_instance_valid(node):
			continue
		# 专用容器(可重建): 装备图标挂这, 每次刷新先清空 → 战中装备后能重调显示新装备
		var box: Node2D = node.get_node_or_null("p2_equip_box")
		if box == null:
			box = Node2D.new(); box.name = "p2_equip_box"
			node.add_child(box)
		for c in box.get_children():
			c.queue_free()
		# box 重建 → 旧 mana fill 已 queue_free → 重置该 slot 的 staff_mana_bars 记录 (防刷新链命中已释放节点)
		node.set_meta("staff_mana_bars", {})
		if f.get("_isMinion", false) or f.get("_isEgg", false):
			continue
		# 读 fighter 的 _p2_equips (setup从equipped_p2载入+战中_equip_from_bench_to追加都在此);
		# 原读 GameState.equipped_p2 → 漏掉玩家战中拖装的(那存_p2_equips), 装了不显
		var items: Array = f.get("_p2_equips", [])
		if items.is_empty():
			continue
		var n := items.size()
		var spacing := 22.0
		var x0 := -(n - 1) * spacing / 2.0
		var sm = f.get("_staff_mana")   # 法器: 携带法器且法器激活时 apply_team_start 已开 _staff_mana[id]
		var staff_bars: Dictionary = {}
		for j in range(n):
			var it: Dictionary = items[j]
			var iid := str(it.get("id", ""))
			var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(iid, {})
			var st := int(it.get("star", 1))
			var glyph_x := x0 + j * spacing
			# PoC 装备有贴图 → 显 png(20×20), 无图回退 emoji。img 字段=phase2-equipment.json 按机制/id匹配PoC装备图。
			var _img_rel := str(ed.get("img", ""))
			var _img_full := "res://assets/sprites/%s" % _img_rel if _img_rel != "" else ""
			if _img_full != "" and ResourceLoader.exists(_img_full):
				var pic := TextureRect.new()
				pic.texture = load(_img_full)
				pic.custom_minimum_size = Vector2(20, 20)   # 槽位约束: PoC 装备图原生很大(如 600×600), 必约束否则爆
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				# 星级辨识(描边色): 2/3星 加细描边发光 (TextureRect 无字描边 → 用同色边框近似)
				if st >= 2:
					pic.self_modulate = Color(1, 1, 1, 1)
				pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(pic)
				# Node2D 父非容器: .size/.position 必在 add_child 后设 (add 的布局 pass 会覆盖 add 前的 .size → 否则取纹理原生大小)
				pic.position = Vector2(glyph_x - 10, 14)
				pic.size = Vector2(20, 20)
			else:
				var lbl := Label.new()
				lbl.text = str(ed.get("emoji", "📦"))
				lbl.add_theme_font_size_override("font_size", 18)
				# 星级辨识: 1★银/2★金/3★青 描边色 (装备图标外发光)
				lbl.add_theme_color_override("font_outline_color", Color("#cfd8e0") if st <= 1 else (Color("#ffd93d") if st == 2 else Color("#5af0ff")))
				lbl.add_theme_constant_override("outline_size", 0 if st <= 1 else 4)
				lbl.position = Vector2(glyph_x - 9, 16)
				lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(lbl)
			# 法器·法力进度条 (emoji 下沿 14×2px 蓝条, 满档变黄): 仅持激活法器(_staff_mana 含该 id)显示, 读法力≠龟能。
			#   meta 存 slot node → 复用 _refresh_staff_mana_for/_update_staff_mana_bars 刷新链 (累积/触发后自动刷)。
			if sm is Dictionary and (sm as Dictionary).has(iid):
				var mb_w := 14.0
				var mb_h := 2.0
				var mb_y := 38.0   # emoji(y=16, 18px) 下沿
				var mtrack := ColorRect.new()
				mtrack.color = Color(0.04, 0.07, 0.12, 0.9)
				mtrack.size = Vector2(mb_w, mb_h)
				mtrack.position = Vector2(glyph_x - mb_w / 2.0, mb_y)
				mtrack.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(mtrack)
				var mfill := ColorRect.new()
				mfill.color = Color(0.27, 0.55, 1.0)   # 蓝(未满)
				mfill.size = Vector2(mb_w, mb_h)
				mfill.mouse_filter = Control.MOUSE_FILTER_IGNORE
				mtrack.add_child(mfill)
				staff_bars[iid] = {"fill": mfill, "w": mb_w}
		if not staff_bars.is_empty():
			node.set_meta("staff_mana_bars", staff_bars)
			_update_staff_mana_bars(node, f)   # 立即按当前法力填充 (初始可能已>0)


func _build_slot_views() -> void:
	# 各 fighter 按真实 _slotKey 站位 (PoC 6 槽网格, 前排靠中/后排靠边)
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		# 灵物触手 = 场边单位 (规格#553"场边"): 不进 slot 网格, 走程序触手视图摆到屏幕侧边缘.
		if f.get("_isTentacle", false):
			var tnode := _build_tentacle_view(f)
			slots_root.add_child(tnode)
			slot_nodes.append(tnode)
			continue
		var pos := _slot_to_coords(f.get("_slotKey", "front-0"), f.get("side", "left"))
		var node := _make_slot_view(f, pos)
		node.z_index = int(pos.y)  # 画家序: 越靠下(越近)越在上层, 前排压后排
		slots_root.add_child(node)
		slot_nodes.append(node)
		# HUD sibling: 同 z + 紧跟 node 加入 (画在自己龟身之上), 但不随 body 动画位移/旋转
		var hud_n = node.get_meta("hud", null)
		if hud_n != null:
			hud_n.z_index = int(pos.y)
			slots_root.add_child(hud_n)


## 通用 spawn-a-combatant 管线: 战斗中途把一个新 fighter dict 推进战场 (进 fighters[] + 建 slot 视图 +
##   同步 slot_nodes[]/HUD + 登记 battle_stats). 龟蛋登场 / 034玩偶大熊召唤 / e_doll大熊召唤 共用此口.
##   注: 调用方负责填好 fighter dict 全字段 (用 _make_minion 风格的精简结构) + 设好 _slotKey/side.
##   返回新 fighter 的索引 (fighters[] 中). 入场弹跳/特效由调用方按需播 (此口只管落地+建视图+登记).
func _spawn_combatant(fighter: Dictionary) -> int:
	fighters.append(fighter)
	var idx: int = fighters.size() - 1
	var pos := _slot_to_coords(str(fighter.get("_slotKey", "front-1")), str(fighter.get("side", "left")))
	var node := _make_slot_view(fighter, pos)
	node.z_index = int(pos.y)
	slots_root.add_child(node)
	# slot_nodes[] 必须与 fighters[] 同索引 — append 在末尾即可 (上面刚 append fighter 到末尾)
	slot_nodes.append(node)
	var hud_n = node.get_meta("hud", null)
	if hud_n != null:
		hud_n.z_index = int(pos.y)
		slots_root.add_child(hud_n)
	battle_stats.register_all([fighter])   # 登记统计桶 (盖 _uid, 结算面板可列)
	return idx


# 脚底剪影阴影的柔边 shader (1:1 PoC shadow.setTintFill(0x000000)+preFX.addBlur)。
#   对当前帧 alpha 做 9-tap 高斯模糊 → 输出纯黑 + shadow_alpha, 并 ×COLOR.a 尊重父级 modulate(死亡淡出)。
#   只采 alpha 通道(剪影形状), 故色调恒为纯黑柔影, 与 PoC 一致。建一次缓存复用。
var _shadow_shader_cache: Shader = null
func _get_shadow_shader() -> Shader:
	if _shadow_shader_cache == null:
		_shadow_shader_cache = Shader.new()
		# 高斯 σ≈4.48 屏幕px — 由 PoC addBlur 真实实现推导 (FXBlurLow.frag 3-tap × pipeline steps4,
		#   offset=1.333×2≈2.667 → 单pass σ²≈5.0, 4pass σ²≈20 → σ≈4.48/轴)。单pass 13-tap 近似 4×可分离3-tap。
		#   权重 = 高斯 exp(-r²/2σ²): 中心1 / ±1σ轴 .6065 / ±2σ轴 .1353 / 对角(σ,σ) .3679, 归一 /5.439。
		# 密集 7×7 高斯 (49-tap, 步长 0.5σ 覆盖 ±1.5σ) — 替代原稀疏 13-tap(只 ±σ/±2σ 两环=鬼影/块状).
		#   1:1 PoC Phaser addBlur(FXBlurLow 3-tap × steps4 H+V separable, 平滑高斯 σ≈4.48). 单pass无法separable,
		#   故用密集 2D 高斯取样逼近其平滑度.
		_shadow_shader_cache.code = "shader_type canvas_item;\n" + \
			"uniform vec2 sigma_texels = vec2(1.0);\n" + \
			"uniform float shadow_alpha = 0.55;\n" + \
			"void fragment() {\n" + \
			"	vec2 stp = TEXTURE_PIXEL_SIZE * sigma_texels * 0.6;\n" + \
			"	float a = 0.0;\n" + \
			"	float wsum = 0.0;\n" + \
			"	for (int i = -5; i <= 5; i++) {\n" + \
			"		for (int j = -5; j <= 5; j++) {\n" + \
			"			float w = exp(-float(i*i + j*j) * 0.18);\n" + \
			"			a += texture(TEXTURE, UV + vec2(float(i), float(j)) * stp).a * w;\n" + \
			"			wsum += w;\n" + \
			"		}\n" + \
			"	}\n" + \
			"	a /= wsum;\n" + \
			"	COLOR = vec4(0.0, 0.0, 0.0, a * shadow_alpha * COLOR.a);\n" + \
			"}\n"
	return _shadow_shader_cache


## 把某帧剪影裁出 → 缩到屏幕显示尺寸 → 四周补 pad 透明边 → baked 成独立单帧纹理。
##   为什么: 1:1 PoC addBlur 是【屏幕空间·渲染后】模糊, 羽化向剪影【外】扩散。Godot 片元 shader
##   在纹理空间模糊, 会被精灵 quad(=纹理内容矩形)裁掉外扩羽化 → 边缘硬切; 且多帧 spritesheet
##   采样越界会窜到相邻帧。补 3σ 透明边 + 单帧化 → shader 羽化有空地扩散 + 不窜帧 = 复刻 PoC 软边。
##   在【显示分辨率】烤(非原生 500px) → blur 在近屏幕分辨率算(同 PoC), 省内存 + 不欠采样。
##   cache: frame→ImageTexture, 每帧只烤一次 (idle 动画复用)。
func _bake_padded_shadow_frame(sheet: Image, frame: int, fw: int, fh: int, hframes: int, disp_w: int, disp_h: int, pad_x: int, pad_y: int, cache: Dictionary) -> ImageTexture:
	if cache.has(frame):
		return cache[frame]
	var fx: int = (frame % maxi(1, hframes)) * fw
	var fy: int = (frame / maxi(1, hframes)) * fh
	var crop: Image = sheet.get_region(Rect2i(fx, fy, fw, fh))
	if disp_w != fw or disp_h != fh:
		crop.resize(maxi(1, disp_w), maxi(1, disp_h), Image.INTERPOLATE_BILINEAR)
	var out := Image.create(disp_w + 2 * pad_x, disp_h + 2 * pad_y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(crop, Rect2i(0, 0, disp_w, disp_h), Vector2i(pad_x, pad_y))
	var tex := ImageTexture.create_from_image(out)
	cache[frame] = tex
	return tex


func _make_slot_view(fighter: Dictionary, pos: Vector2) -> Node2D:
	var root := Node2D.new()
	root.position = pos
	# HUD 层(等级/血条/装备): 独立 sibling 节点, 不随 body 的 hop/juggle/death 旋转一起飞。
	#   1:1 PoC "只有 .st-body 做 hop/throw/knockback 动画 → 血条不跟着飞" (BattleScene.ts:216)。
	#   metas(hp_bar/hp_text)仍挂 root → 所有 getter 不变, 只是渲染父级换成不动的 hud。
	var hud := Node2D.new()
	hud.position = pos
	root.set_meta("hud", hud)

	# 头像 sprite — PoC makeView: SPRITE_SIZE 80 × baseScale(0.9×1.417=1.275 普通 / ×1.5=1.913 boss)
	#   → DISPLAY_BOX 高 = 102px 普通 / 153px boss, 锁高度按比例缩宽. NEAREST 滤镜(像素艺术不糊).
	#   站位: PoC bottom-anchored (ts:605 newSpriteY = c.y - SPRITE_HALF) — 槽坐标=脚底, sprite 中心抬 SPRITE_HALF.
	var is_boss: bool = fighter.get("_isBoss", false)
	var box: float = 153.0 if is_boss else 102.0   # 80 × baseScale (PoC DISPLAY_BOX)
	var sprite_half: float = floorf(box / 2.0)      # PoC SPRITE_HALF = floor(DISPLAY_BOX/2)
	var avatar := Sprite2D.new()
	avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # PoC line 1890: 像素艺术 NEAREST
	# ── PoC makeView 全身立绘 (BattleScene.ts:1854-1903): pets.json `img`=sheet 路径,
	#    `sprite{frames,frameW,frameH,duration}`=帧元数据. 18 龟有 sprite{} → 走 spritesheet idle 动画,
	#    10 龟无 sprite (ice/two_head/diamond/dice/rainbow/pirate/lightning/phoenix/lava/cyber) → 静态 body PNG.
	#    缩放 = fitToBox: box/frameH (锁高度, 宽按比例; PoC fitToBox 用 frameH 不是 min-fit). NEAREST 像素滤镜.
	var fid: String = fighter["id"]
	var pet: Dictionary = DataRegistry.pet_by_id.get(fid, {})
	# 合成单位(龟蛋等)未注册进 pet 表 → 退而用 fighter 自带 img/sprite。
	#   龟蛋待机动画 3帧 sheet 走此路才会动 (否则 img/sprite 取空 → 掉下方静态兜底 = 整张 237×80 sheet 压成一张 = 用户报"图片不是动画")。
	var from_registry: bool = not pet.is_empty()
	var img: String = str(pet.get("img", "")) if from_registry else str(fighter.get("img", ""))
	var sprite_meta = pet.get("sprite", null) if from_registry else fighter.get("sprite", null)
	var avatar_path := "res://assets/sprites/avatars/%s.png" % fid
	var idle_frames: int = 0
	var loop_dur: float = 0.0
	var img_full := "res://assets/sprites/%s" % img   # img 已是相对路径如 pets/stone.png
	if img != "" and ResourceLoader.exists(img_full):
		var tex: Texture2D = load(img_full)
		avatar.texture = tex
		var tw: int = tex.get_width()
		var thh: int = tex.get_height()
		if sprite_meta is Dictionary and (sprite_meta as Dictionary).has("frameW"):
			# 有 sprite{} 元数据 → spritesheet 全身立绘 idle 动画 (横向多帧)
			var meta: Dictionary = sprite_meta
			var fw: int = int(meta.get("frameW", tw))
			var fh: int = int(meta.get("frameH", thh))
			if fw <= 0:
				fw = tw
			if fh <= 0:
				fh = thh
			var hframes: int = maxi(1, int(floor(float(tw) / float(fw))))
			var vframes: int = maxi(1, int(floor(float(thh) / float(fh))))
			avatar.hframes = hframes
			avatar.vframes = vframes
			avatar.frame = 0
			# PoC BootScene:370 frameCount = min(sprite.frames, frameTotal-1)
			var frame_total: int = hframes * vframes
			var declared: int = int(meta.get("frames", frame_total))
			# PoC 龟 sheet 保留末帧 (frameTotal-1 quirk, BootScene:370); 合成单位(龟蛋)自带 sheet 无此约定 → 播全部声明帧 (3帧全循环)。
			idle_frames = maxi(1, mini(declared, frame_total - 1)) if from_registry else maxi(1, mini(declared, frame_total))
			# PoC BootScene:372-373 fps = max(4, round(frameCount*1000/max(200,durationMs))); 循环时长 = frameCount/fps
			var dur_ms: float = float(meta.get("duration", 800))
			var fps: float = maxf(4.0, roundf(float(idle_frames) * 1000.0 / maxf(200.0, dur_ms)))
			loop_dur = float(idle_frames) / fps
			var sf: float = box / float(fh)
			avatar.scale = Vector2(sf, sf)
		else:
			# 无 sprite{} → 静态 body PNG (整图当一帧, 锁高度缩放)
			var fh2: float = float(thh) if thh > 0 else box
			var sf2: float = box / fh2
			avatar.scale = Vector2(sf2, sf2)
		# 朝向 (1:1 PoC:1907-1910): 常规龟资源朝左 → 右队翻转; hiding/cyber 朝右 → 反着 (左队翻转)。
		if _should_flip_x(fid, fighter["side"]):
			avatar.scale.x = -absf(avatar.scale.x)
	elif ResourceLoader.exists(avatar_path):
		# 回退: 无 pet 数据/sheet 缺失 → avatars 头像
		var tex2: Texture2D = load(avatar_path)
		avatar.texture = tex2
		var th: float = tex2.get_height() if tex2.get_height() > 0 else box
		var scale_factor: float = box / th
		avatar.scale = Vector2(scale_factor, scale_factor)
		if _should_flip_x(fid, fighter["side"]):
			avatar.scale.x = -scale_factor
	# 无 pet 注册立绘 (如深海小将): 先试 fighter 自带 img(放进 assets 即自动启用), 再 emoji 兜底.
	if avatar.texture == null:
		var own_img := str(fighter.get("img", ""))
		var own_full := "res://assets/sprites/%s" % own_img
		if own_img != "" and ResourceLoader.exists(own_full):
			var ot: Texture2D = load(own_full)
			avatar.texture = ot
			var oth: float = ot.get_height() if ot.get_height() > 0 else box
			var osf: float = box / oth
			avatar.scale = Vector2(osf, osf)
			if _should_flip_x(fid, fighter["side"]):
				avatar.scale.x = -osf
		else:
			# emoji 兜底 (深海小将🐠/精英🦐): 大号 emoji Label 当身体 (占位, 真美术后替)
			var emo := Label.new()
			emo.text = str(fighter.get("emoji", "🐢"))
			emo.add_theme_font_size_override("font_size", 56)
			emo.position = Vector2(-34, -78); emo.size = Vector2(68, 68)
			emo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			emo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			emo.mouse_filter = Control.MOUSE_FILTER_IGNORE
			emo.pivot_offset = Vector2(34, 34)
			avatar.add_child(emo)
			# (小将 emoji 上下浮/呼吸 idle 已移除 — PoC 无此动画, 自创; 用户 2026-06-13)
	# sprite 中心抬 SPRITE_HALF → 脚底落在槽坐标 (root.position), 跟 PoC 1:1
	avatar.position = Vector2(0, -sprite_half)
	root.add_child(avatar)
	root.set_meta("avatar", avatar)
	avatar.set_meta("home", avatar.position)   # 受击击退 _hit_knockback 归位锚点 (PoC tv.homeX/Y)
	avatar.set_meta("home_scale", avatar.scale)   # 施法 tell 脉冲归位锚点 (PoC view.homeScaleX/Y 防累积变形)
	# (深海小将立绘 idle 上下浮已移除 — PoC 无此动画, 自创; 用户 2026-06-13)
	# 脚底剪影影子 (1:1 PoC makeView shadow BattleScene.ts:1912-1930 + applyShadowTransform:3982-3996):
	#   同纹理副本黑剪影压扁躺地 (size1.1/flatten0.6/rot24°/alpha.55/lift9/offsetX22/flipY)。
	#   龟"站地上"的接地锚点 — 缺它 → 龟悬空 = 用户报"站位明显错误"+"没影子"。
	var shadow: Sprite2D = null
	if avatar.texture != null:
		shadow = Sprite2D.new()
		shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # 配模糊 shader: 软边采样 (非 NEAREST 硬边)
		# 黑剪影+柔边: 1:1 PoC shadow.setTintFill(0x000000)+addBlur(0,2,2,1)+alpha.55。
		#   shader 对 alpha 做高斯模糊 → 纯黑, ×0.55, ×父级 modulate.a (死亡淡出仍生效)。
		shadow.modulate = Color(1, 1, 1, 1)   # 真正的黑/alpha 交给 shader, modulate 留白不二次压暗
		var sh_mat := ShaderMaterial.new()
		sh_mat.shader = _get_shadow_shader()
		shadow.material = sh_mat
		# scale: 内容已烤到【显示分辨率】(见下 _bake_padded_shadow_frame), 故 scale 不再含 avatar.scale,
		#   只留 PoC 的 ×1.1 放大 / Y 压扁 0.6 / flipY(×-1)。abs → 影子不随龟左右翻转 (1:1 PoC Math.abs(scaleX))。
		var sh_scale := Vector2(1.1, 1.1 * 0.6 * -1.0)
		shadow.scale = sh_scale
		# σ=4.48 屏幕px (由 PoC addBlur 真实实现推导: FXBlurLow 3-tap × steps4 H+V → σ²≈20)。
		#   内容烤在显示分辨率 → sigma_texels = 4.48/|scale| → ×|scale| 回到屏幕恒为 σ4.48 (与龟大小无关)。
		var sig := Vector2(4.48 / maxf(0.01, absf(sh_scale.x)), 4.48 / maxf(0.01, absf(sh_scale.y)))
		sh_mat.set_shader_parameter("sigma_texels", sig)
		shadow.rotation = deg_to_rad(24.0)
		# 1:1 PoC applyShadowTransform: setScale(abs(scaleX)…) + setFlipX(sprite.flipX) — 剪影形状随龟左右朝向【镜像】。
		#   龟用 negative scale.x 翻转(774行), 这里 abs scale 去了翻转 → 须用 flip_h 标志(UV镜像)补回; flip_h 不动
		#   scale 符号/不反转旋向 → 与 PoC 完全等价(数学: R·S·diag(-1,1))。原只 abs 漏 flip → 朝左龟影子显右朝剪影=错。
		shadow.flip_h = avatar.scale.x < 0.0
		# 1:1 PoC 实时路径(resize:617 / moveViewToSlot:2949): shadow.y = c.y - round(12×baseScale) = 抬 15普/23boss。
		#   (makeView 初值 lift9 是创建瞬时, 一经 resize/换槽即被覆盖 → 实际在屏值是 12×baseScale。boss 差更大 9→23。)
		var base_scale_for_lift: float = (0.9 * 1.417 * 1.5) if is_boss else (0.9 * 1.417)
		shadow.position = Vector2(avatar.position.x + 22.0, -round(12.0 * base_scale_for_lift))   # 脚底(root原点)右移22 抬 round(12×baseScale)
		# ── 烤【带 3σ 透明边】的单帧剪影纹理 → shader 羽化向外扩散有空地 + 不窜帧 (见 _bake_padded_shadow_frame) ──
		var sheet_img: Image = avatar.texture.get_image()
		if sheet_img != null:
			if sheet_img.is_compressed():
				sheet_img.decompress()
			sheet_img.convert(Image.FORMAT_RGBA8)
			var hf: int = maxi(1, avatar.hframes)
			var vf: int = maxi(1, avatar.vframes)
			var fw: int = avatar.texture.get_width() / hf
			var fh: int = avatar.texture.get_height() / vf
			# 显示分辨率 = 帧原始尺寸 × avatar 显示缩放 (让 blur 在近屏幕分辨率算, 同 PoC)
			var disp_w: int = maxi(1, int(round(float(fw) * absf(avatar.scale.x))))
			var disp_h: int = maxi(1, int(round(float(fh) * absf(avatar.scale.y))))
			# 透明边 = 3σ (texel), 覆盖 shader ±5×0.6σ=3σ 的采样半径 → 羽化完整不被裁
			var pad_x: int = int(ceil(3.0 * sig.x)) + 2
			var pad_y: int = int(ceil(3.0 * sig.y)) + 2
			var cache: Dictionary = {}
			shadow.texture = _bake_padded_shadow_frame(sheet_img, avatar.frame, fw, fh, hf, disp_w, disp_h, pad_x, pad_y, cache)
			shadow.hframes = 1
			shadow.vframes = 1
			# 存料供 idle 序列帧动画复用 (逐帧懒烤进 cache)
			shadow.set_meta("pad_cache", cache)
			shadow.set_meta("pad_args", [sheet_img, fw, fh, hf, disp_w, disp_h, pad_x, pad_y])
		else:
			# get_image 失败兜底: 退回整 sheet + shader (会裁羽化但不崩)
			shadow.texture = avatar.texture
			shadow.scale = Vector2(absf(avatar.scale.x) * 1.1, absf(avatar.scale.y) * 1.1 * 0.6 * -1.0)
			sh_mat.set_shader_parameter("sigma_texels", Vector2(4.48 / maxf(0.01, absf(shadow.scale.x)), 4.48 / maxf(0.01, absf(shadow.scale.y))))
			shadow.hframes = avatar.hframes
			shadow.vframes = avatar.vframes
			shadow.frame = avatar.frame
		root.add_child(shadow)
		root.move_child(shadow, 0)   # 移到 avatar 下方 (先画 = 在龟身后)
		root.set_meta("shadow", shadow)
		shadow.set_meta("home", shadow.position)   # 受击击退时跟随 body 同步 x
	# idle 序列帧循环 (PoC anim-idle-<id>): tween 绑 avatar, 随其释放自动停; 同步驱动影子帧
	if idle_frames > 1 and loop_dur > 0.0:
		var n := idle_frames
		var sh := shadow
		var atw := avatar.create_tween().set_loops()
		atw.tween_method(func(v: float):
			var fr := int(v) % n
			avatar.frame = fr
			if is_instance_valid(sh):
				if sh.has_meta("pad_cache"):
					var c: Dictionary = sh.get_meta("pad_cache")
					var pa: Array = sh.get_meta("pad_args")
					# pa = [sheet_img, fw, fh, hf, disp_w, disp_h, pad_x, pad_y]
					sh.texture = _bake_padded_shadow_frame(pa[0], fr, pa[1], pa[2], pa[3], pa[4], pa[5], pa[6], pa[7], c)
				else:
					sh.frame = fr,
			0.0, float(n), loop_dur)

	# 点击命中区 → 弹详情面板 (1:1 PoC sprite.setInteractive→showFighterDetail, BattleScene.ts:1935-1939)
	get_viewport().physics_object_picking = true   # 启用 2D 物理拾取 (Area2D.input_event 需要)
	var hit := Area2D.new()
	hit.input_pickable = true
	var cshape := CollisionShape2D.new()
	var hrect := RectangleShape2D.new()
	hrect.size = Vector2(box, box)
	cshape.shape = hrect
	cshape.position = Vector2(0, -sprite_half)
	hit.add_child(cshape)
	root.add_child(hit)
	var fref: Dictionary = fighter
	# 点龟身 (方案A, 用户 2026-06-25, 删长按):
	#   决策态(选龟出手 _picker_active / 选目标 _targeting_active) = 出手/选靶 (交给那些区的专用 Area2D, 这里抑制不弹面板);
	#   闲置态 = 弹详情面板。
	#   决策态"看信息"改走龟身上的 ⓘ 信息钮 (_add_info_button), 不再靠长按。
	hit.input_event.connect(func(_vp: Node, ev: InputEvent, _idx: int) -> void:
		if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
			return
		# 有 modal 浮层(商店/详情/装备弹窗)时, 不让点击穿透到背后的龟 (1:1 PoC: 浮层挡点击)
		if not get_tree().get_nodes_in_group("ui_modal").is_empty():
			return
		# 决策态: 出手/选靶交给选龟区/选靶环的专用 Area2D, 龟身点击抑制详情面板 (不误弹); 闲置态弹面板。
		if not _should_open_detail(_picker_active or _targeting_active):
			return
		_show_fighter_detail(fref))

	# 名字/HP数字/ATK 文字 — PoC makeView ts:1959-1966 全 setAlpha(0): 这些是自创,
	#   真实显示(scene-turtle-dom .st-hp-row)只有【等级徽章 + 88×10 血条】, 无名字/HP数字/ATK.
	#   保留节点(_refresh_slot 引用 hp_text)但 modulate.a=0 隐藏, 1:1 PoC.
	var name_label := Label.new()
	name_label.text = "%s [%s]" % [fighter["name"], fighter["rarity"]]
	name_label.position = Vector2(-70, -100)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.modulate.a = 0.0
	root.add_child(name_label)

	# ── HP 条 = scene-turtle-dom .st-hp-row (龟头顶上方): 等级徽章 + 88×10 血条 ──
	#   PoC .scene-turtle 整体 transform:scale(baseScale 1.275/boss1.913) → 血条按 baseScale 同步放大,
	#   竖向锚: HP row 落在 sprite 头顶上方 (foot - box - hp_row_h - 间隙), 跟 setCanvasPos naturalHeight 数学一致.
	# HP 条尺寸 1:1 PoC turtle-hud.ts (88×5 border2 / boss 160×8×3, **未缩放**; 见 docs/BATTLE-RENDER-MAP.md)
	var bar_w := 160.0 if is_boss else 88.0
	var bar_h := 8.0 if is_boss else 5.0
	var bar_x := -bar_w / 2.0
	var bar_y := -(box + bar_h + 6.0)   # 血条底沿落在头顶上方 (box=立绘高=脚到头) + 间隙
	# 等级徽章 (turtle-hud levelText 10px #ffd93d / boss13, 棕底#2a1d12, bar左)
	var badge_fs: int = 13 if is_boss else 10
	var lv_badge := Panel.new()
	var lv_sb := StyleBoxFlat.new()
	lv_sb.bg_color = Color("#2a1d12")                    # 1:1 PoC turtle-hud.ts:185 backgroundColor:#2a1d12
	lv_sb.set_border_width_all(0)                        # PoC Phaser text bg = 纯矩形无边框 (原自创金边)
	lv_sb.set_corner_radius_all(0)                       # PoC bg 不圆角 (原自创 corner_radius 3)
	lv_badge.add_theme_stylebox_override("panel", lv_sb)
	lv_badge.size = Vector2((badge_fs + 12), bar_h + 4)
	lv_badge.position = Vector2(bar_x - (badge_fs + 14), bar_y - 2)
	var lv_lbl := Label.new()
	lv_lbl.text = "%d" % int(fighter.get("_level", 1))   # 引擎字段是 _level (非 level → 原恒显1)
	lv_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_size_override("font_size", badge_fs)
	lv_lbl.add_theme_color_override("font_color", Color("#ffd93d"))
	lv_lbl.add_theme_font_override("font", _get_panel_font(true))   # 1:1 PoC turtle-hud.ts:184 fontStyle:'bold'
	lv_badge.add_child(lv_lbl)
	hud.add_child(lv_badge)

	# HP 条 = 自定义 HpBar (1:1 PoC turtle-hud.ts: 玻璃管渐变 + 100/500刻度 + 多段盾白/金/青/紫 + 受击红trail/60ms白闪/横抖)
	var hp_bar := HpBar.new()
	hp_bar.setup(fighter.get("side", "left") == "left", is_boss)
	hp_bar.position = Vector2(bar_x, bar_y)
	hud.add_child(hp_bar)
	root.set_meta("hp_bar", hp_bar)
	hp_bar.update_state(fighter)

	# 资源条 (HP条下方): 龟能=蓝 — 仅有龟能(_maxEnergy)的龟显示
	# 注: 熔岩龟怒气(_lavaRage)由 hp_bar 怒气特殊条渲染(_compute_special_bars), 此处不再建能量条 → 避免两条橙 (docs/ledgers/信息面板细节修复批.md ③)
	var res_max := 0
	var res_field := "_energy"
	var res_color := Color(0.27, 0.62, 1.0)   # 蓝色龟能
	if int(fighter.get("_maxEnergy", 0)) > 0:
		res_max = int(fighter.get("_maxEnergy", 0))
	if res_max > 0:
		var en_h := 4.0 if is_boss else 3.0
		var en_track := Panel.new()
		var en_tsb := StyleBoxFlat.new()
		en_tsb.bg_color = Color(0.04, 0.07, 0.12, 0.85)
		en_track.add_theme_stylebox_override("panel", en_tsb)
		en_track.position = Vector2(bar_x, bar_y + bar_h + 1.0)
		en_track.size = Vector2(bar_w, en_h)
		hud.add_child(en_track)
		var en_fill := ColorRect.new()
		en_fill.color = res_color
		en_fill.size = Vector2(bar_w, en_h)
		en_track.add_child(en_fill)
		root.set_meta("energy_fill", en_fill)
		root.set_meta("energy_w", bar_w)
		root.set_meta("res_field", res_field)
		root.set_meta("res_max", res_max)
		_update_energy_bar(root, fighter)

	# 装备图标列 (1:1 PoC turtle-hud refreshEquipBadges/layoutEquips:574-672)
	#   图标视图 add_child 到 hud, 但法器法力条 meta 须存 slot 节点(root) → _refresh_slot/_refresh_staff_mana_for 才命中 (对齐孵化器条范式)。
	_build_equip_column(root, hud, fighter, bar_x, bar_y, bar_w, bar_h)

	# 孵化器 (p2eq_036) 孵化进度条: 仅持孵化器者显示, meta 存 slot 节点(root) → _refresh_slot 自动刷新。
	_build_incubator_bar(root, hud, fighter, bar_x, bar_y, bar_w, bar_h)

	# (删 F10 状态图标行 — agent 逐行确认 PoC 战斗画面**不渲染**状态图标, turtle-hud refreshStatusIcons 短路+statusGroup永空; 只详情面板看. 自创已删, 见 docs/BATTLE-RENDER-MAP.md)

	# HP 数字 (自创, 隐藏; _refresh_slot 仍更新 .text)
	var hp_text := Label.new()
	hp_text.text = "%d / %d" % [fighter["hp"], fighter["maxHp"]]
	hp_text.position = Vector2(bar_x, bar_y - 16)
	hp_text.add_theme_font_size_override("font_size", 12)
	hp_text.modulate.a = 0.0
	hud.add_child(hp_text)
	root.set_meta("hp_text", hp_text)

	# ⓘ 信息钮 (方案A, 用户 2026-06-25): 龟头顶角上触屏友好(≥24px 命中区)小图标 — 任何时候点 = 弹该龟详情面板,
	#   只看信息、不触发出手/选靶 (mouse_filter STOP 吞事件, 不穿透到龟身 hit/选龟选靶区)。须在 bar_y 算好后挂。
	_add_info_button(hud, fref, box, bar_y)

	root.set_meta("home_pos", pos)
	return root


## ⓘ 信息钮 (方案A, 用户 2026-06-25): 龟头顶角上一个小图标 — 任何时候点 = 弹该龟详情面板 (不触发出手/选靶).
##   触屏友好: 命中区 28×28 (≥24px); 圆形深底白边白 ⓘ, 不挡龟脸 (落在 HP 条右上方).
##   mouse_filter STOP + set_input_as_handled → 事件吞掉不穿透到龟身 hit / 选龟选靶区 (只看信息不出手).
##   挂 hud (不随 body hop/juggle 位移 → ⓘ 稳定贴龟). hud 已含等级徽章+血条 (头顶上方那条).
func _add_info_button(hud: Node2D, fref: Dictionary, box: float, bar_y: float) -> void:
	var sz := 28.0   # 命中区 28px (≥24 触屏可点中)
	var info := Button.new()
	info.text = "i"
	info.focus_mode = Control.FOCUS_NONE
	info.mouse_filter = Control.MOUSE_FILTER_STOP   # 吞点击, 不穿透到龟身/选龟选靶区
	info.z_index = 200   # 命中区竞争预防(审计#8): 与龟身 picker Area2D(104×128)/选靶 ring(150×150) 几何相邻,
	#   提 z 到最前确保 ⓘ 先吃事件(Control GUI 本就先于 Area2D 拾取, 这里再加保险), 决策态点 ⓘ 不误触出手/选靶。
	info.size = Vector2(sz, sz)
	info.pivot_offset = Vector2(sz / 2.0, sz / 2.0)
	# 落点: 龟身右上 (HP 条右端外侧, 头顶高度) — 不挡脸, 跟出手发光环/血条不重叠。
	#   多抬 10px 安全间距(审计#8): 原 bar_y-sz-4 时 ⓘ 底沿(≈-117)几乎贴 picker 顶(≈-115)/压 ring 上沿 →
	#   触屏点 ⓘ 边缘易误落 picker/ring 出手。上移留清晰竖向间隙, 与龟身命中区脱开。
	info.position = Vector2(box * 0.30, bar_y - sz - 14.0)
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_font_override("font", _get_panel_font(true))
	info.add_theme_color_override("font_color", Color("#eaf2ff"))
	info.add_theme_color_override("font_hover_color", Color("#ffffff"))
	info.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	# 圆形深底白边 (TFT 风信息钮): normal/hover/pressed 三态
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#1b2940") if st == "normal" else (Color("#2c4570") if st == "hover" else Color("#3a5891"))
		sb.set_corner_radius_all(int(sz / 2.0))   # 圆形
		sb.set_border_width_all(2)
		sb.border_color = Color("#9fc3ff")
		info.add_theme_stylebox_override(st, sb)
	info.pressed.connect(func() -> void:
		# modal 浮层时不响应 (与龟身 hit 一致)
		if not get_tree().get_nodes_in_group("ui_modal").is_empty():
			return
		_show_fighter_detail(fref))
	hud.add_child(info)


## 灵物触手【场边】程序视图 (规格#553"场边"): 不进 slot 网格, 站屏幕侧边缘 (左队左/右队右).
##   程序画: 锥形触手身 (Line2D 根粗梢细 width_curve) + 根部吸盘环 + 微微卷曲的待机姿态. 拍击时由
##   _animate_tentacle_slap 重画 points 做 伸出→拍击→缩回. 设与普通 slot 视图同款 metas(home_pos/avatar/
##   hp_text/hud), 让 _refresh_all_slots/_flash_hit 等通用迭代不因缺 meta 报错 (触手 _untargetable 实不受刷).
func _build_tentacle_view(fighter: Dictionary) -> Node2D:
	var side: String = str(fighter.get("side", "left"))
	var order: int = int(fighter.get("_edgeOrder", 0))
	var total: int = int(fighter.get("_edgeTotal", 1))
	var base: Vector2 = _tentacle_base_pos(side, order, total)
	var root := Node2D.new()
	root.position = base
	root.z_index = 40   # 场边触手画在战场单位之上 (拍击线越过它们)

	var inward: float = 1.0 if side == "left" else -1.0   # 触手朝场内方向 (向敌)

	# 触手身 (Line2D 锥形: 根粗→梢细). 待机姿态=从根部微微伸入场内再回卷 (S形), 显出"触手"剪影.
	var line := Line2D.new()
	line.width = 26.0
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 1.0))    # 根部最粗
	wc.add_point(Vector2(0.7, 0.45))
	wc.add_point(Vector2(1.0, 0.12))   # 梢部最细 (锥形)
	line.width_curve = wc
	line.default_color = Color(0.42, 0.27, 0.62, 0.95)   # 幽紫触手肉色
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.points = _tentacle_idle_points(inward)
	root.add_child(line)
	root.set_meta("tentacle_line", line)
	root.set_meta("tentacle_inward", inward)

	# 根部吸盘环 (锚在场边, 表现"从场边伸出")
	var cup := Line2D.new()
	cup.points = _circle_points(15.0, 18)
	cup.closed = true
	cup.width = 4.0
	cup.default_color = Color(0.62, 0.40, 0.86, 0.9)
	root.add_child(cup)
	# 吸盘内点缀 (吸盘的小圆点, 加触手生物感)
	var dot := Polygon2D.new()
	dot.polygon = _circle_points(6.0, 12)
	dot.color = Color(0.30, 0.18, 0.46, 0.95)
	root.add_child(dot)

	# avatar 占位 (触手梢端): 让通用 get_meta("avatar") 不为空; VFX/特效会落在梢端处.
	var tip := Node2D.new()
	tip.position = line.points[line.points.size() - 1] if line.points.size() > 0 else Vector2.ZERO
	root.add_child(tip)
	tip.set_meta("home", tip.position)
	tip.set_meta("home_scale", Vector2.ONE)
	root.set_meta("avatar", tip)

	# 隐藏 hp_text (通用 _refresh_slot 无条件 get_meta("hp_text") → 必须存在, 否则迭代触手时报错).
	var hp_text := Label.new()
	hp_text.modulate.a = 0.0
	hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_text)
	root.set_meta("hp_text", hp_text)
	root.set_meta("home_pos", base)
	root.set_meta("hud", null)
	return root


## 触手待机姿态点列 (根 0,0 → 向场内伸出再回卷的 S 形). inward = +1 左队向右 / -1 右队向左.
func _tentacle_idle_points(inward: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(0, 0))
	pts.append(Vector2(inward * 18.0, -22.0))
	pts.append(Vector2(inward * 40.0, -30.0))
	pts.append(Vector2(inward * 56.0, -16.0))
	pts.append(Vector2(inward * 62.0, 6.0))
	return pts


## 装备图标列 (1:1 turtle-hud layoutEquips:633): 20×20暗框+14×14图标, 竖排 gap5, 龟外侧(左队右/右队左), 竖向居中血条.
##   视觉(框/图标/法力条) add_child 到 hud; 法器法力条 meta 存 slot_node(root) → _refresh_slot/_refresh_staff_mana_for 才命中 (对齐孵化器条)。
func _build_equip_column(slot_node: Node2D, hud: Node2D, fighter: Dictionary, bar_x: float, bar_y: float, bar_w: float, bar_h: float) -> void:
	var eq_ids: Array = (fighter.get("_equipped_ids", []) as Array).duplicate()
	var passive = fighter.get("passive", null)
	var chest_set := {}
	if passive is Dictionary and passive.get("type", "") == "chestTreasure":
		for ce in fighter.get("_chestEquips", []):
			var cid: String = str(ce.get("id", "")) if ce is Dictionary else str(ce)
			if cid != "":
				eq_ids.append(cid)
				chest_set[cid] = true
	if eq_ids.is_empty():
		return
	var box := 20.0
	var gap := 5.0
	var icon_sz := 14.0
	var is_left: bool = fighter.get("side", "left") == "left"
	var cx := (bar_x + bar_w + 6.0 + box / 2.0) if is_left else (bar_x - 6.0 - box / 2.0)
	var n := eq_ids.size()
	var center_y := bar_y + bar_h / 2.0
	var start_y := center_y - (float(n - 1) * (box + gap)) / 2.0
	for i in range(n):
		var eid: String = str(eq_ids[i])
		var cy := start_y + i * (box + gap)
		var bg := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.031, 0.047, 0.078, 0.78)        # 0x080c14 @.78
		sb.border_color = Color(1.0, 0.85, 0.25, 0.9) if chest_set.has(eid) else Color(1, 1, 1, 0.18)  # 宝箱金边
		sb.set_border_width_all(1)
		bg.add_theme_stylebox_override("panel", sb)
		bg.size = Vector2(box, box)
		bg.position = Vector2(cx - box / 2.0, cy - box / 2.0)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(bg)
		var edef: Dictionary = DataRegistry.equipment_by_id.get(eid, {})
		var irel: String = str(edef.get("icon", ""))
		if irel != "":
			var ifull := "res://assets/sprites/" + irel
			if ResourceLoader.exists(ifull):
				var ic := Sprite2D.new()
				ic.texture = load(ifull)
				ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var th: float = float(ic.texture.get_height()) if ic.texture.get_height() > 0 else icon_sz
				ic.scale = Vector2(icon_sz / th, icon_sz / th)
				ic.position = Vector2(cx, cy)
				hud.add_child(ic)
		# 法器·法力进度条 (图标下沿 14×2px 蓝条, 满档变黄): 仅法器(_staff_mana 含该 id)显示, 读法力≠龟能。
		if fighter.get("_staff_mana") is Dictionary and (fighter["_staff_mana"] as Dictionary).has(eid):
			var mb_w := 14.0
			var mb_h := 2.0
			var mb_y := cy + box / 2.0 - mb_h - 1.0   # 框底沿内侧
			var mtrack := ColorRect.new()
			mtrack.color = Color(0.04, 0.07, 0.12, 0.9)
			mtrack.size = Vector2(mb_w, mb_h)
			mtrack.position = Vector2(cx - mb_w / 2.0, mb_y)
			mtrack.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hud.add_child(mtrack)
			var mfill := ColorRect.new()
			mfill.color = Color(0.27, 0.55, 1.0)   # 蓝(未满)
			mfill.size = Vector2(mb_w, mb_h)
			mfill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mtrack.add_child(mfill)
			var bars: Dictionary = slot_node.get_meta("staff_mana_bars", {})
			bars[eid] = {"fill": mfill, "w": mb_w}
			slot_node.set_meta("staff_mana_bars", bars)   # meta 存 slot_node → 刷新链命中
	_update_staff_mana_bars(slot_node, fighter)


## 刷新某 slot 的法器法力条 (满档变黄)。法力读 _staff_mana[id], 满档 = _staffTier→100/80/60 (≠龟能)。
func _update_staff_mana_bars(node: Node, f: Dictionary) -> void:
	if node == null or not node.has_meta("staff_mana_bars"):
		return
	var bars: Dictionary = node.get_meta("staff_mana_bars", {})
	var sm = f.get("_staff_mana")
	if not (sm is Dictionary):
		return
	var cap: int = [100, 80, 60][clampi(int(f.get("_staffTier", 0)), 1, 3) - 1]
	for eid in bars.keys():
		var rec: Dictionary = bars[eid]
		var fill = rec.get("fill")
		if not is_instance_valid(fill):
			continue
		var cur: int = clampi(int((sm as Dictionary).get(eid, 0)), 0, cap)
		var full: bool = cur >= cap
		(fill as ColorRect).size.x = float(rec.get("w", 14.0)) * float(cur) / float(maxi(1, cap))
		(fill as ColorRect).color = Color(1.0, 0.84, 0.2) if full else Color(0.27, 0.55, 1.0)   # 满档变黄

## 按 fighter 找其 slot, 刷新法器法力条 (累积/触发后调)。
func _refresh_staff_mana_for(f: Dictionary) -> void:
	var i: int = fighters.find(f)
	if i >= 0 and i < slot_nodes.size() and is_instance_valid(slot_nodes[i]):
		_update_staff_mana_bars(slot_nodes[i], f)


## 持孵化器 (p2eq_036 或已有 _incubatorProgress) 判定。
func _has_incubator(f: Dictionary) -> bool:
	if f.has("_incubatorProgress"):
		return true
	for p2 in f.get("_p2_equips", []):
		if p2 is Dictionary and str(p2.get("id", "")) == "p2eq_036":
			return true
	return false


## 孵化器·孵化进度条 (仿法器法力条 14×2px): 龟头顶 HP 区下方加 🥚 + 0-100 进度条。
##   读 _incubatorProgress/100, 满档(到临时等级上限3 或本档满)变金。仅持孵化器者显示。
##   meta 存 slot_node (≠hud), 因 _refresh_slot 检 slot_node — 死亡加进度后随刷新链自动更新。
func _build_incubator_bar(slot_node: Node2D, hud: Node2D, f: Dictionary, bar_x: float, bar_y: float, bar_w: float, _bar_h: float) -> void:
	if not _has_incubator(f):
		return
	var ib_w := 14.0
	var ib_h := 2.0
	# 横向居中于 HP 条, 纵向落在头顶 HP 区上方一点 (与装备列错开)。
	var ib_x := bar_x + bar_w / 2.0 - ib_w / 2.0
	var ib_y := bar_y - 8.0
	# 🥚 小标 (进度条左侧)
	var egg_lbl := Label.new()
	egg_lbl.text = "🥚"
	egg_lbl.add_theme_font_size_override("font_size", 8)
	egg_lbl.position = Vector2(ib_x - 11.0, ib_y - 5.0)
	egg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(egg_lbl)
	var itrack := ColorRect.new()
	itrack.color = Color(0.05, 0.04, 0.02, 0.9)
	itrack.size = Vector2(ib_w, ib_h)
	itrack.position = Vector2(ib_x, ib_y)
	itrack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(itrack)
	var ifill := ColorRect.new()
	ifill.color = Color(0.85, 0.65, 0.25)   # 暖橙 (未满)
	ifill.size = Vector2(ib_w, ib_h)
	ifill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	itrack.add_child(ifill)
	slot_node.set_meta("incubator_bar", {"fill": ifill, "w": ib_w})
	_update_incubator_bar(slot_node, f)


## 刷新孵化器进度条 (满档变金)。进度读 _incubatorProgress (0-100), 临时等级到上限3时进度不再回卷→显满金。
func _update_incubator_bar(node: Node, f: Dictionary) -> void:
	if node == null or not node.has_meta("incubator_bar"):
		return
	var rec: Dictionary = node.get_meta("incubator_bar", {})
	var fill = rec.get("fill")
	if not is_instance_valid(fill):
		return
	var prog: int = clampi(int(f.get("_incubatorProgress", 0)), 0, 100)
	var at_cap: bool = int(f.get("_incubatorTempLevel", 0)) >= 3
	var full: bool = at_cap or prog >= 100
	var w: float = float(rec.get("w", 14.0))
	(fill as ColorRect).size.x = w if full else w * float(prog) / 100.0
	(fill as ColorRect).color = Color(1.0, 0.84, 0.2) if full else Color(0.85, 0.65, 0.25)   # 满档金


# ─── 战斗主循环 ────────────────────────────────────────────────

func _battle_loop() -> void:
	# Side-based 回合制 (1:1 PoC nextActor/processSideEnd/runRoundEnd):
	#   一 round = 左队整侧行动 → side-end(左) → 右队整侧 → side-end(右) → round-end → turn++
	#   左先手. DoT 在 side-end 对【对面】结算 (我打完→敌方烧). buff duration-- 在每龟 turn-begin.
	#   CD-- 每 round 一次. (玩家 picker / 中立抽干 / 召唤 side-end / 经济 等留待对应系统)
	while not finished and turn <= OVERTIME_HARD_CAP:
		# 决胜局: 超过 OVERTIME_START 回合, 任何龟行动前全龟叠 1 层怒气 + 上疲惫 (PoC 风格反拖延, 替代平局)
		if turn > OVERTIME_START:
			_apply_overtime_escalation()
		var title_prefix := ""
		if GameState.mode == "dungeon":
			var marker := " · BOSS" if GameState.is_dungeon_boss_stage() else ""
			title_prefix = "[闯关 第 %d/%d 关%s] " % [GameState.dungeon_stage, 5, marker]
		elif GameState.mode == "duallane":
			var lane_names := {"top": "上路", "bottom": "下路", "final": "终极战场"}
			title_prefix = "[%s] " % lane_names.get(GameState.current_lane, "")
		_set_title("%s第 %d 回合" % [title_prefix, turn])
		if OS.has_environment("DUALLANE_SMOKE") and GameState.mode == "duallane":
			print("[SMOKE] %s 第%d回合" % [GameState.current_lane, turn])
		# 经济: 二阶段双路用局内币+被动XP(grant_dual_round); 老模式用 PoC 回合经济(+10币利息) + 羁绊chip刷新.
		if GameState.mode == "duallane":
			GameState.grant_dual_round()   # 双方 +被动XP(2/回合 PASSIVE_XP) (升级强化蛋/小将随级; V2 局内无经济)
			# V2-TODO 阶段2/6: 奇械[深海工坊]每回合铸币已删 (局内无经济); 奇械效果待局外重定
			_resync_spawned_egg_hp()       # 升级强化了 egg_hp_max → 同步已登场蛋单位的 maxHp/hp (否则定格在spawn值)
			var _school_dmg: Array = Phase2Schools.on_round_begin(fighters, turn)   # 双路: 学派每回合效果 (玄甲全队盾 / 潮汐潮涌回血+每3回合大潮净化)
			await _render_school_round_damage(_school_dmg)   # 远古觉醒AOE / 军火弹幕: 静默扣血 → 飘字+刷血+AOE VFX(可见化) + (致死)并行死亡演出
			# 玄甲卫队[玄甲工坊]: 随机将 1/1/2 件「费用≤2/3/4 且非3星」装备临时玄甲化 (本回合按高一星结算效果, 下回合开始还原)。
			var _xuanjia: Array = Phase2Schools.apply_xuanjia_round(fighters, func(eid): return int(DataRegistry.phase2_equipment_by_id.get(eid, {}).get("cost", 1)))
			for _xb in _xuanjia:
				var _xf = _xb.get("fighter", null)
				if _xf is Dictionary and is_instance_valid(battle_log):
					battle_log.append_text("[color=#94a3b8]🛡 玄甲化「%s」→ %d★ (本回合)[/color]\n" % [str(DataRegistry.phase2_equipment_by_id.get(str(_xb.get("item_id", "")), {}).get("name", _xb.get("item_id", ""))), int(_xb.get("star", 1))])
			for _sf in fighters:   # 极地僵硬过期清除 (审计: 设计4回合叠加刷新, 原 _stiffnessStacks 永不消失)
				if int(_sf.get("_stiffnessStacks", 0)) > 0 and turn >= int(_sf.get("_stiffnessExpireTurn", 999999)):
					_sf["_stiffnessStacks"] = 0
					_sf.erase("_stiffnessExpireTurn")
					StatsRecalc.recalc(_sf)
			# V2 阶段1: 战斗内商店已删 (roll_shop_offer/ai_dual_shop/_ensure_battle_shop) — 装备/商店挪局外背包
			battle_log.append_text("[color=#ffd166]💠 局内 Lv%d (+%dXP) · 🥚我 %d / 敌 %d[/color]\n" % [int(GameState.dual_level.get("left", 1)), Phase2Config.PASSIVE_XP, int(GameState.egg_hp.get("left", 0)), int(GameState.egg_hp.get("right", 0))])
		else:
			var econ: Dictionary = GameState.on_battle_turn_economy()
			battle_log.append_text("[color=#ffd166]💰 回合收入 +%d 龟币 (利息 +%d) → %d[/color]\n" % [econ["player_gain"], econ["player_interest"], econ["coins"]])
			_refresh_battle_hud()   # 刷新深海币(我方/敌方) + 羁绊 chip
		battle_log.append_text("\n[color=#ffd166][b]── 第 %d 回合 ──[/b][/color]\n" % turn)
		# 回合横幅 3 变体 (1:1 PoC roundBanner ts:1845): 事件回合(3/6/9/12)/商店回合(t%4)/普通 各醒目文案+色+时长.
		var rb_event: bool = (turn == 3 or turn == 6 or turn == 9 or turn == 12)
		var rb_shop: bool = (turn % 4 == 0) and GameState.mode != "duallane"   # 双路商店每回合换货 → 不标"商店回合"横幅 (用户 2026-06-18)
		var rb_text: String; var rb_sub: String; var rb_col: String; var rb_dur: float
		if rb_event:
			rb_text = "⚠ 第 %d 回合 · 事件来袭" % turn; rb_sub = "Event Round"; rb_col = "#ffb01f"; rb_dur = 1.4
		elif rb_shop:
			rb_text = "🛒 第 %d 回合 · 商店" % turn; rb_sub = "Shop Round"; rb_col = "#7ec8ff"; rb_dur = 1.3
		else:
			rb_text = "第 %d 回合" % turn; rb_sub = "Round %d" % turn; rb_col = "#ffd93d"; rb_dur = 1.1
		_show_center_banner(rb_text, rb_sub, rb_col, rb_dur)   # 中央回合横幅
		if not auto_play_debug:
			await get_tree().create_timer(rb_dur + 0.26).timeout   # 1:1 PoC roundBanner await = dur + fade260 (横幅看得见再开打)
		SkillHandlers.current_turn = turn   # 供 starWormhole turnDmgPct 等读
		await _roll_battle_event(turn)   # 局中环境事件 (第3/6/9/12回合, 1:1 PoC events.ts) [Phase1: env事件]
		await _thunderstorm_tick()   # 雷暴后续: 被标记的后续回合每回合随机单位 40 真伤 (原 _thunderstormTurns 只标记从不消费)

		# 规则每回合开始 (下雨天: 全场 5×N 魔法 + 永久 -N 甲/抗) — PoC applyRulePerTurn, 在任何龟行动前
		Rules.apply_rule_per_turn(rule, fighters, turn)
		for ri in range(fighters.size()):
			var rf: Dictionary = fighters[ri]
			var rain_dmg: int = rf.get("_rainDmg", 0)
			if rain_dmg > 0:
				_spawn_float_text(ri, rain_dmg, "damage", "magic", false)
				_refresh_slot(ri)
				rf["_rainDmg"] = 0
			# 雨夜可能致死 → 先放死亡动画, 死掉的本回合不行动
			if not rf.get("alive", false) and slot_nodes[ri].modulate.a > 0.35:
				await _play_death(ri)
		# 元素羁绊 tier3: 每回合随机灼烧一名敌人 (老乌龟羁绊; 双路已移除羁绊系统 → 跳过)
		if GameState.mode != "duallane":
			_process_synergy_elem_burn_tick()
		# 终极战场: 已登场的败方龟蛋每回合自损 25% maxHP (_eggSelfLoss flag; round-begin 扣, 可致蛋摧毁)
		await _egg_self_loss_tick()
		_candy_bomb_decay_tick()   # 糖果炸弹每回合开始自损 decayPct% (归零→引爆 AOE)
		_pirate_ship_fire()         # 海盗船开炮 (回合顶, 在召唤前 → turn3召唤的船 turn4 才首发) — 1:1 PoC
		_pirate_ship_spawn_check()  # 海盗船 turn3 召唤 (pirateShipPassive 装备门控)
		_anchor_melt_tick()         # 017 不沉之锚: 每回合熔1件其它装备进锚 (给原属性×25/50/1000%)
		if _check_end():
			finished = true
			_show_result()
			break
		# 上/下路 攻蛋限轮: 蛋登场后只给 EGG_ATTACK_ROUNDS 回合凿蛋 (累计剩血带入下路), 超时本路结束 (终极=凿穿为止不限轮)
		if GameState.mode == "duallane" and GameState.current_lane != "final" and _egg_attack_rounds_done():
			finished = true
			_show_result()
			break

		for side in ["left", "right"]:
			if finished:
				break
			_show_side_banner(side)   # 侧回合横幅 (🐢我方 / 👹敌方)
			_update_turn_timeline(side)   # 顶部回合进度线 (当前节点 + 阵营 pill)
			if not auto_play_debug:
				await get_tree().create_timer(0.64).timeout   # 1:1 PoC beginSideTurn delayedCall(640) 演出停顿 (让横幅看得见再行动)
			await _run_side_turn(side)
			if finished:
				break
			# side-end: 对刚行动完那侧的【对面】结算 DoT (PoC processSideEnd:7276)
			await _side_end(side)
			if _check_end():
				finished = true
				_show_result()
				break
		if finished:
			break

		# round-end: CD 全场 -1 (per-round, PoC turn.js:43-45 — 绝不 per-actor 否则加速 N 倍)
		SkillHandlers.tick_cooldowns(fighters)
		_tick_hiding_shields()   # 缩头盾倒计时, 到期剩余盾×healPct% 转生命
		await _process_energy_wave()   # 龟壳气场: 每 N 回合储能波击全敌 + 气场盾 (PoC processEnergyWave)
		if _check_end():
			finished = true
			_show_result()
			break
		# 战中商店: 老模式每 4 回合 (4/8/12) 弹窗. 双路商店已改【每回合换货+AI买】(见 round-begin), 不在此处.
		if turn % 4 == 0 and GameState.mode != "duallane":
			_ai_auto_shop(turn / 4 - 1)   # 老模式: 老战中商店
			if not auto_battle and (GameState.mode in PLAYER_MODES):
				await _open_shop(turn / 4 - 1)
		turn += 1

	if not finished:
		# 决胜局怒气指数增伤理论上必分胜负; 极端安全网触顶则按当前存活/血量正常判胜负 (绝不判平, PoC 无平局)
		finished = true
		_show_result()


# 元素羁绊 tier3: 每回合随机灼烧一名敌人 (PoC processSynergyElemBurnTick / turn.js:71-83)
# 核心逻辑在 Synergies.process_elem_burn_tick (吃烈焰之日 burn_mult), 这里只飘字 + 日志
# 决胜局升级 (PoC 风格反拖延): OVERTIME_START 回合后, 每回合任何龟行动前 ——
#   · 全存活龟 +1 层怒气 (_overtimeRage), 每层使其造成伤害 +30% (Damage.calc_damage 读)
#   · 全存活龟获得疲惫 (_overtimeFatigue), 治疗/护盾效果 ×0.5, 持续到战斗结束 (Buffs.fatigue_amt/grant_shield 读)
# 怒气指数增伤保证战斗在数回合内分出胜负 → 取代平局。
func _apply_overtime_escalation() -> void:
	# 二阶段双路: 用「永恒buff」(每层造成&受到+50%, 仅统领) 取代单局决胜怒气/疲惫 (设计 V3.2)
	if GameState.mode == "duallane":
		_apply_eternal_buff()
		return
	var first := true
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("alive", false):
			continue
		if int(f.get("_overtimeRage", 0)) > 0:
			first = false
		f["_overtimeRage"] = int(f.get("_overtimeRage", 0)) + 1
		f["_overtimeFatigue"] = true
		_refresh_slot(i)
		_spawn_passive_text(i, "⚔ 怒气×%d" % int(f["_overtimeRage"]))
	var stacks: int = turn - OVERTIME_START   # 第 31 回合 = 1 层
	if first:
		_show_center_banner("决胜局!", "Sudden Death")
		battle_log.append_text("\n[color=#ff5d5d][b]⚔ 决胜局! 全场获得怒气(每层+30%伤害)与疲惫(治疗/护盾-50%)[/b][/color]\n")
	battle_log.append_text("[color=#ff8c8c]怒气层数 → %d (伤害 +%d%%)[/color]\n" % [stacks, stacks * 30])


## 永恒 buff (二阶段双路, 每场第30回合后): 存活统领每回合叠1层, 每层造成&受到各+50%; 仅统领(小将/蛋不吃).
func _apply_eternal_buff() -> void:
	var first := true
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("alive", false):
			continue
		if f.get("_isMinion", false) or f.get("_isEgg", false):
			continue   # 仅统领
		if int(f.get("_eternalStack", 0)) > 0:
			first = false
		f["_eternalStack"] = int(f.get("_eternalStack", 0)) + 1
		_refresh_slot(i)
		_spawn_passive_text(i, "♾ 永恒×%d" % int(f["_eternalStack"]))
	if first:
		_show_center_banner("永恒战场!", "Eternal", "#c77dff")
		battle_log.append_text("\n[color=#c77dff][b]♾ 永恒buff! 存活统领每回合叠层 (造成&受到各 +50%/层)[/b][/color]\n")


# 元素羁绊 tier3: 每回合随机灼烧一名敌人 (PoC processSynergyElemBurnTick / turn.js:71-83)
func _process_synergy_elem_burn_tick() -> void:
	var burns: Array = Synergies.process_elem_burn_tick(fighters, Rules.burn_mult(rule))
	for b in burns:
		var target: Dictionary = b["target"]
		var ti: int = fighters.find(target)
		if ti >= 0:
			_spawn_passive_text(ti, "🔥 +%d" % int(b["stacks"]))
			_refresh_slot(ti)
		battle_log.append_text("[color=#ff6600]🔥 元素羁绊: %s 烧 %s (+%d 层)[/color]\n" % [
			b["tagger"].get("name", "?"), target.get("name", "?"), int(b["stacks"])])


# 一整侧依次行动. 玩家侧多只可动 → 弹选龟框由玩家选出手顺序 (1:1 PoC nextActor/showTurtlePicker);
#   AI/中立/单只 → 自动按序。←换龟 在动作面板, 取消当前龟回选龟框重选。
#   turn-begin 每龟每侧回合只跑一次 (turn_begun 守卫), 防 ←换龟 反复重选刷被动/扣 buff (PoC :5238 守卫)。
func _run_side_turn(side: String) -> void:
	# 龟能回复: 第2回合起, 本阵营回合开始时每只存活龟回 最大龟能×40% (封顶到最大). 第1回合不回(用初始龟能). 设计文档.
	for ef in fighters:
		if ef.get("side", "") == side and ef.get("alive", false):
			if turn >= 2 and int(ef.get("_maxEnergy", 0)) > 0:
				var emx := int(ef.get("_maxEnergy", 0))
				ef["_energy"] = mini(emx, int(ef.get("_energy", 0)) + int(round(emx * 0.4)))
			_refresh_energy_for(ef)   # 资源条(龟能/怒气/变身倒计时)每回合刷一次
	var actors: Array = []
	for f in fighters:
		# 召唤物/机甲是"非行动者"(isNonActor): 不进主回合, 只在 side-end 自动行动
		# 龟蛋(_isEgg)是不行动的纯挨打单位 → 也排除出行动者 (设计: 蛋登场后正常挨打, 但永不出手)
		if f.get("side", "") == side and f.get("alive", false) \
				and not f.get("_isSummon", false) and not f.get("_isMech", false) \
				and not f.get("_isEgg", false):
			actors.append(f)
	# 首回合左队 cap 2 行动 (预热感, PoC 2162); boss 一侧每龟行动 2 次 (PoC 2133)
	var max_actions: int = actors.size()
	if turn == 1 and side == "left":
		max_actions = mini(2, actors.size())
	var is_boss := _is_boss_side(side)
	var acted := 0
	var acted_set: Dictionary = {}    # fighter idx → true (本侧回合已行动; 用 idx 不用 dict, 后者 hash 随血量变会错)
	var turn_begun: Dictionary = {}   # idx → true (turn-begin 已跑)
	while acted < max_actions and not finished:
		# 本侧未行动的可动龟 (排木桩)
		var can_act: Array = []
		for f in actors:
			if f.get("alive", false) and not f.get("_isDummy", false) and not acted_set.has(fighters.find(f)):
				can_act.append(f)
		if can_act.is_empty():
			break
		# AI/中立先自动出手 (不进选龟框); 全是玩家可控龟且 >1 才弹框选顺序
		var chosen: Dictionary = {}
		var ai_first: Array = can_act.filter(func(cf: Dictionary) -> bool: return not _is_player_controlled(cf))
		if not ai_first.is_empty():
			chosen = ai_first[0]
		else:
			_start_turn_timer()   # 玩家决策(选龟框→面板→选靶)开始 → 启 30s 倒计时(已在跑不重启)
			if can_act.size() > 1:
				chosen = await _show_turtle_picker(can_act)
				if chosen.is_empty():
					chosen = can_act[0]
			else:
				chosen = can_act[0]
		var idx: int = fighters.find(chosen)
		# ▶ 行动者起手日志 (1:1 PoC BattleScene.ts:2333 `▶ {name} 行动`)
		if is_instance_valid(battle_log):
			battle_log.append_text("▶ %s 行动\n" % chosen.get("name", "?"))
		# per-actor turn-begin: reset flags + buff duration-- + recalc + 装备 onTurnBegin + 熔岩变身 (每龟每侧只一次)
		if not turn_begun.has(idx):
			await _actor_turn_begin(idx)
			turn_begun[idx] = true
		_play_turn_foot_ring(idx)   # 行动龟脚底回合圈 (绿我方/红敌方 展开淡出, 1:1 PoC startActorTurn)
		# 眩晕: 消耗本次行动跳过 (boss 整侧回合跳掉两次行动 — PoC 2149-2156)
		if Buffs.is_stunned(chosen):
			acted_set[idx] = true; acted += 1
			await _do_stun_skip(idx)
			continue
		# 混乱(confused, 用户新状态): 全技能置灰不可选 → 强制基础攻击随机敌人 (胡乱攻击)
		if Buffs.has(chosen, "confused"):
			acted_set[idx] = true; acted += 1
			await _do_confused_action(idx)
			continue
		var reps := 2 if is_boss else 1
		var went_back := false
		for _r in range(reps):
			if finished or not chosen.get("alive", false):
				break
			# 玩家控制: 左队 + 非自动战 + 可玩模式 → 手动选技能/目标 (可 ←换龟); 否则 AI
			if _is_player_controlled(chosen):
				_player_wants_back = false
				await _player_take_turn(idx, can_act.size() > 1)
				if _player_wants_back:
					went_back = true   # ←换龟: 不计行动, 回选龟框重选
					break
			else:
				# AI 出手前延迟: 首次出手保留长思考(派发0.5+思考1.2≈1.7s, 让玩家看清第一手), 之后缩短到 ≈0.7s
				#   避免每只 AI 都等满 1.7s = 整体节奏拖沓(用户报"AI出手偏慢"). headless 自测(auto_play_debug)跳过保持快.
				if not auto_play_debug:
					if not _ai_moved_once:
						await get_tree().create_timer(0.5).timeout   # 首手: 派发延迟 500ms
						await get_tree().create_timer(1.2).timeout   # 首手: AI 思考 1200ms (= 1.7s)
						_ai_moved_once = true
					else:
						await get_tree().create_timer(0.7).timeout   # 后续手: 缩短思考 700ms (保守缩, 仍可见"在思考")
				await _take_turn(idx)
			if not auto_play_debug:
				await get_tree().create_timer(TURN_DELAY_MS / 1000.0).timeout
			if _check_end():
				finished = true
				_show_result()
				break
		if went_back:
			continue
		acted_set[idx] = true; acted += 1
	_clear_turn_timer()   # 本侧回合结束 → 收掉计时条(兜底; 正常每次出手已由 _take_turn 清)


# ─── 玩家操作层 (1:1 PoC ActionPanel + 玩家回合状态机) ────────────

# 技能分类 (PoC onPlayerSkillPicked 的 5 个白名单, 1:1)
const SKILL_SELF_CAST := ["fortuneDice", "fortuneBuyEquip", "phoenixShield", "hidingDefend",
	"hidingCommand", "cyberDeploy", "diamondFortify", "diceFate", "chestCount", "bambooHeal",
	"volcanoArmor", "crystalBarrier", "shellCopy"]
const SKILL_AUTO_ENEMY := ["mechAttack", "wormBite"]
const SKILL_AOE := ["hunterBarrage", "ninjaBomb", "lightningBarrage", "iceFrost", "basicBarrage",
	"starMeteor", "starGravityWarp", "diceAllIn", "angelSmite", "diceFlashStrike"]
const SKILL_ALLY := ["heal", "shield", "bubbleShield", "angelBless", "bubbleHeal",
	"crystalResHeal", "phoenixPurify"]


## 玩家是否手动控这只龟 (PoC isPlayerTurn: 非自动战 + 左队 + 可玩模式)
func _is_player_controlled(f: Dictionary) -> bool:
	# 双路: 玩家操控自己这侧【全部】单位 — 统领 + 补位小将/精英小将 都可控 (用户 2026-06-13)。
	#   小将仅"不进终极战场"(snapshot_lane_survivors:299 已排除 _isMinion), 战中与统领一样由玩家操作。
	return not auto_battle and f.get("side", "") == "left" and (GameState.mode in PLAYER_MODES)


## 出手倒计时 30s (1:1 PoC startTurnTimer:2056). 已在跑则不重启(跨选龟框→面板→选靶 一段连续决策).
##   headless 自测/自动战不启用(autoplay 0.05s 就出手, 且避免扰 953 测时序)。
func _start_turn_timer() -> void:
	if auto_play_debug or auto_battle or finished:
		return
	if _turn_timer_active:
		return
	_turn_timed_out = false
	_turn_timer_left = 30
	_turn_timer_active = true
	_turn_timer_gen += 1
	_show_turn_timer_bar(_turn_timer_left, 30)
	_turn_timer_tick(_turn_timer_gen)


func _turn_timer_tick(gen: int) -> void:
	while _turn_timer_active and _turn_timer_gen == gen and not finished:
		await get_tree().create_timer(1.0).timeout
		if _turn_timer_gen != gen or not _turn_timer_active or finished:
			return
		_turn_timer_left -= 1
		_show_turn_timer_bar(maxi(0, _turn_timer_left), 30)
		if _turn_timer_left <= 0:
			_auto_act_on_timeout()
			return


## 清计时器 (玩家真出手 / ←换龟出框 / 结束). gen+1 让正在跑的 tick 退出。
func _clear_turn_timer() -> void:
	_turn_timer_active = false
	_turn_timer_gen += 1
	_turn_timer_paused_left = -1   # 清计时 → 作废任何暂停态 (回合换人, 旧暂停值不再有效)
	_turn_timed_out = false        # 清计时 → 同步清超时态, 防未来某路径不调 _start_turn_timer 时泄漏上只超时态
	_hide_turn_timer_bar()


## 暂停倒计时 (决策态开 ⓘ 详情面板时): 存剩余秒、停 tick (gen+1), 但保留条可见(标暂停态). 仅在计时正跑时生效。
##   防"看龟信息时计时照走 → 误超时自动出招". 关面板 _resume_turn_timer 从存值续跑。
func _pause_turn_timer() -> void:
	if not _turn_timer_active or _turn_timer_paused_left >= 0:
		return   # 没在跑 / 已暂停 → 不重复存 (防覆盖真实剩余值)
	_turn_timer_paused_left = _turn_timer_left
	_turn_timer_active = false
	_turn_timer_gen += 1   # 让正在跑的 tick 协程自然退出 (不再 -1)


## 恢复倒计时 (关 ⓘ 详情面板时): 从暂停存值续跑. 无暂停态=no-op。
func _resume_turn_timer() -> void:
	if _turn_timer_paused_left < 0:
		return
	if finished or auto_play_debug or auto_battle or _turn_timed_out:
		_turn_timer_paused_left = -1
		return   # 局已结束/已超时转AI → 不复活计时
	_turn_timer_left = _turn_timer_paused_left
	_turn_timer_paused_left = -1
	_turn_timer_active = true
	_turn_timer_gen += 1
	_show_turn_timer_bar(maxi(0, _turn_timer_left), 30)
	_turn_timer_tick(_turn_timer_gen)


## 超时: 释放当前 await → 交 AI 自动出招 (1:1 PoC _autoActOnTimeout:2077).
##   只有一个 await 在等(选龟框/技能面板/选靶), emit 其余无订阅=no-op。_turn_timed_out 让重入面板直接转AI。
func _auto_act_on_timeout() -> void:
	_turn_timer_active = false
	_turn_timed_out = true
	_hide_turn_timer_bar()
	if is_instance_valid(battle_log):
		battle_log.append_text("[color=#ffd166]⏰ %s 超时！自动出招[/color]\n" % (_timeout_actor_name if _timeout_actor_name != "" else "当前龟"))
	if _targeting_active:
		_target_chosen.emit(-1)   # 取消选靶 → 重入 _player_take_turn → _turn_timed_out 转 AI
	else:
		_picker_picked.emit(-1)   # 在选龟框 → 放行(caller 取 can_act[0])
		_player_wants_back = false
		_skill_chosen.emit(-1)    # 在技能面板 → _player_take_turn:1111 skill_idx<0 → _take_turn(AI)


func _show_turn_timer_bar(left: int, max_v: int) -> void:
	if _turn_timer_bar == null:
		_turn_timer_layer = CanvasLayer.new()
		_turn_timer_layer.layer = 35
		add_child(_turn_timer_layer)
		# 1:1 PoC .poc-turn-timer-bar (BattleTopRow.ts:226-231): 280×13, 圆角7, 2px白边.22, bg rgba(8,12,20,.85), 居中 top146
		var vp := get_viewport_rect().size
		var bar := Panel.new()
		bar.position = Vector2((vp.x - 280.0) / 2.0, 158.0)   # 1:1 PoC: 容器#poc-battle-top-row fixed top:12 + bar top:146 = 158 (原146漏了容器12偏移)
		bar.size = Vector2(280.0, 13.0)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.85)
		bsb.border_color = Color(1, 1, 1, 0.22)
		bsb.set_border_width_all(2)
		bsb.set_corner_radius_all(7)
		bar.add_theme_stylebox_override("panel", bsb)
		# fill: 1:1 PoC .ttb-fill (BattleTopRow.ts:234-237): 圆角5, 内嵌(去2px边) 276×9
		var fill := Panel.new()
		fill.position = Vector2(2.0, 2.0)
		fill.size = Vector2(276.0, 9.0)
		_turn_timer_fill_sb = StyleBoxFlat.new()
		_turn_timer_fill_sb.set_corner_radius_all(5)
		fill.add_theme_stylebox_override("panel", _turn_timer_fill_sb)
		bar.add_child(fill)
		# 文字: 1:1 PoC .ttb-text (BattleTopRow.ts:239-242): 10px weight800 #fff 居中
		var lbl := Label.new()
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		lbl.add_theme_font_override("font", _get_panel_font(true))   # weight 800
		bar.add_child(lbl)
		_turn_timer_layer.add_child(bar)
		_turn_timer_bar = bar
		_turn_timer_fill = fill
		_turn_timer_label = lbl
	_turn_timer_bar.visible = true
	var ratio: float = clampf(float(left) / float(maxi(1, max_v)), 0.0, 1.0)
	_turn_timer_fill.size.x = 276.0 * ratio
	# 1:1 PoC fill 渐变色阈值 (BattleTopRow.ts:335-339): ≤10红#ff3b3b / ≤20橙#ffb01f / else绿#2bd66f (Godot纯色近似渐变起色)
	if left <= 10:
		_turn_timer_fill_sb.bg_color = Color("#ff3b3b")
	elif left <= 20:
		_turn_timer_fill_sb.bg_color = Color("#ffb01f")
	else:
		_turn_timer_fill_sb.bg_color = Color("#2bd66f")
	_turn_timer_label.text = "⏱ %ds" % left


func _hide_turn_timer_bar() -> void:
	if _turn_timer_bar != null:
		_turn_timer_bar.visible = false


## 面板字体: 主题默认(m6x11 像素打底 + YaHei CJK 回退, 1:1 PoC 字体栈); bold=合成粗体(PoC 技能名 weight 900)。
##   RichTextLabel 不像 Label 稳定继承主题 default_font → 显式覆盖, 避免落回 Godot 内置无衬线字体。
var _panel_norm_font: Font = null
var _panel_bold_font: Font = null
func _get_panel_font(bold: bool) -> Font:
	if _panel_norm_font == null:
		var th: Theme = load("res://assets/themes/default_theme.tres")   # Node2D 无 get_theme_default_font, 直接取主题
		_panel_norm_font = th.default_font if (th != null and th.default_font != null) else ThemeDB.fallback_font
		if _panel_norm_font != null:
			_panel_norm_font.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK web/iOS 默认主题字体兜底
		var bf := FontVariation.new()
		bf.base_font = _panel_norm_font
		bf.variation_embolden = 0.6
		_panel_bold_font = bf
	return _panel_bold_font if bold else _panel_norm_font


## SMOKE_CLICK: 在屏幕坐标注入一次真实左键点击 (motion 更新物理拾取 → down → up), 走真正的 GUI/Area2D 命中链路。
func _smoke_inject_click(screen_pos: Vector2) -> void:
	# 走 Input(OS输入路径, 含2D物理拾取)而非 viewport.push_input(后者不喂物理拾取→Area2D点不中)。
	Input.warp_mouse(screen_pos)   # 更新物理拾取的光标位置
	var mm := InputEventMouseMotion.new()
	mm.position = screen_pos; mm.global_position = screen_pos
	Input.parse_input_event(mm)
	await get_tree().physics_frame   # 让物理拾取处理 motion → 锁定光标下的 Area2D
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT; dn.pressed = true
	dn.position = screen_pos; dn.global_position = screen_pos
	Input.parse_input_event(dn)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
	up.position = screen_pos; up.global_position = screen_pos
	Input.parse_input_event(up)


## 选龟框: 玩家选哪只龟出手 (1:1 PoC showTurtlePicker). 可动龟脚下绿色呼吸环 + 底部按钮条; await 点击返回 fighter。
func _show_turtle_picker(can_act: Array) -> Dictionary:
	if _picker_layer == null:
		_picker_layer = CanvasLayer.new()
		_picker_layer.layer = 62   # 高于商店(40)+信息面板(60), 否则决策态开 ⓘ/商店时"点脚下发光的龟"提示被盖 (大卡70仍在上)
		add_child(_picker_layer)
	# 可动龟脚下绿色呼吸环 (PoC A2 "该你了")
	var rings: Array = []
	for f in can_act:
		var i: int = fighters.find(f)
		if i < 0 or i >= slot_nodes.size() or not is_instance_valid(slot_nodes[i]):
			continue
		var pos: Vector2 = slot_nodes[i].get_meta("home_pos", slot_nodes[i].position)
		var ring := Node2D.new()
		ring.position = pos + Vector2(0, -6.0)
		ring.z_index = 1
		ring.modulate.a = 0.9
		var line := Line2D.new()
		var pts := PackedVector2Array()
		for k in range(29):
			var a := TAU * k / 28.0
			pts.append(Vector2(cos(a) * 37.0, sin(a) * 14.0))   # 74×28 椭圆
		line.points = pts; line.width = 3.0; line.default_color = Color("#06d6a0"); line.closed = true
		ring.add_child(line)
		slots_root.add_child(ring)
		var tw := ring.create_tween().set_loops()   # 呼吸: scale 1↔1.16 (PoC Sine yoyo)
		tw.tween_property(ring, "scale", Vector2(1.16, 1.16), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(ring, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		rings.append(ring)
	# 点发光的龟直接出手 (用户 2026-06-23 选): 去掉底部卡条 → 每只可动龟身上罩透明可点区 + 顶部提示。绿圈见上。
	var picker_nodes: Array = []
	var hint := Label.new()
	hint.text = "👇 点脚下发光的龟出手"
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color("#ffe9a8"))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hint.add_theme_constant_override("outline_size", 6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.0; hint.anchor_right = 1.0
	hint.offset_top = 64.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_layer.add_child(hint)
	picker_nodes.append(hint)
	for f in can_act:
		var fi: int = fighters.find(f)
		if fi < 0 or fi >= slot_nodes.size() or not is_instance_valid(slot_nodes[fi]):
			continue
		# 修(审计A1#1): 点击区改【世界空间 Area2D】(挂 slots_root, 随相机ENVELOP变换) — 原 CanvasLayer Button
		#   固定屏幕尺寸/偏移, 非16:9窗口相机zoom>1时与世界空间绿圈错位 → 点发光龟点不中=出不了手。镜 _show_target_rings。
		var pos: Vector2 = slot_nodes[fi].get_meta("home_pos", slot_nodes[fi].position)
		var av = slot_nodes[fi].get_meta("avatar", null)
		var area := Area2D.new()
		area.position = pos + (av.position if is_instance_valid(av) else Vector2(0, -48))
		area.z_index = 61
		area.input_pickable = true
		var cs := CollisionShape2D.new()
		var shp := RectangleShape2D.new()
		shp.size = Vector2(104, 128)
		cs.shape = shp
		area.add_child(cs)
		area.input_event.connect(func(vp: Node, ev: InputEvent, _s: int) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				vp.set_input_as_handled()
				_picker_picked.emit(fi))
		slots_root.add_child(area)
		picker_nodes.append(area)
	if _smoke_click and not can_act.is_empty():   # SMOKE_CLICK: 在发光龟上注入【真实鼠标点击】(测世界空间 Area2D 点击命中)
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			var fa: Area2D = null
			for pn in picker_nodes:
				if pn is Area2D:
					fa = pn; break
			if fa != null:
				var spx: Vector2 = fa.get_global_transform_with_canvas().origin
				print("[CLICK] 注入点击-选龟 @ (%d,%d)" % [int(spx.x), int(spx.y)])
				_smoke_inject_click(spx))
	elif (auto_play_debug or OS.has_environment("SHOT_PANEL")) and not can_act.is_empty():   # 自测/截图: 自动选首只
		get_tree().create_timer(0.05).timeout.connect(func(): _picker_picked.emit(fighters.find(can_act[0])))
	_picker_active = true   # 选龟框等待中 → 点龟身=出手 (抑制详情面板; 看信息走 ⓘ 钮)
	var picked_idx: int = await _picker_picked
	_picker_active = false
	if _smoke_click:
		print("[CLICK] → 选中龟 idx=%d %s" % [picked_idx, (str(fighters[picked_idx].get("name", "?")) if picked_idx >= 0 else "(无! 点击没命中)")])
	for pn in picker_nodes:
		if is_instance_valid(pn):
			pn.queue_free()
	for r in rings:
		if is_instance_valid(r):
			r.queue_free()
	if picked_idx < 0 or picked_idx >= fighters.size():
		return {}
	return fighters[picked_idx]


var _timeout_actor_name: String = ""   # 当前等玩家操作的龟名 (供超时日志显名, 1:1 PoC)

## 玩家回合: 显示面板 → 选技能 → (选目标) → 执行 (PoC startActorTurn→onPlayerSkillPicked→executeAttack)
##   can_back = 同侧还有其它可动龟 → 面板显「←换龟」; 点它设 _player_wants_back (caller 检查回选龟框)。
func _player_take_turn(actor_idx: int, can_back: bool = false) -> void:
	var actor: Dictionary = fighters[actor_idx]
	if not actor.get("alive", false):
		return
	_timeout_actor_name = str(actor.get("name", "?"))
	if _turn_timed_out:   # 倒计时已超时 → 不再显示面板, 直接交 AI (覆盖 选龟框→面板 / 选靶取消→重入 两路)
		await _take_turn(actor_idx)
		return
	# 显示操作面板, 等玩家点技能
	_show_action_panel(actor_idx, can_back)
	_picked_skill_idx = -1
	if auto_play_debug:   # headless 自测: 0.05s 后自动点首个可用技能
		_autoplay_emit_skill(actor_idx)
	var skill_idx: int = await _skill_chosen
	_hide_action_panel()
	if _player_wants_back:   # ←换龟: 不行动, 回选龟框 (caller 查 flag)
		return
	if auto_battle or skill_idx < 0:   # 选技能途中切了自动战 → 转 AI
		await _take_turn(actor_idx)
		return
	var skills: Array = actor.get("skills", [])
	if skill_idx >= skills.size():
		await _take_turn(actor_idx)
		return
	var skill: Dictionary = skills[skill_idx]
	var stype: String = skill.get("type", "")
	if _tutorial_guide != null:   # 教程: 玩家释放技能 → 推进步骤 (1:1 PoC notify 'skill-cast')
		_tutorial_guide.notify("skill-cast")

	# 分类派发 (PoC 5 类)
	# 1) 自施放 → 目标=自己
	var is_two_head_melee: bool = stype == "twoHeadSwitch" and skill.get("switchTo", "") == "melee"
	if skill.get("selfCast", false) or stype in SKILL_SELF_CAST or is_two_head_melee:
		await _take_turn(actor_idx, skill_idx, actor_idx)
		return
	# 2) 自动选敌方最低血
	if stype in SKILL_AUTO_ENEMY:
		var en := _alive_enemies_of(actor)
		if en.is_empty():
			return
		en.sort_custom(func(a, b): return int(a.get("hp", 0)) < int(b.get("hp", 0)))
		await _take_turn(actor_idx, skill_idx, fighters.find(en[0]))
		return
	# 3) AoE / 群体 → 目标传任意敌(handler 自己打全体); aoeAlly 传自己
	if skill.get("aoe", false) or stype in SKILL_AOE:
		var en2 := _alive_enemies_of(actor)
		var t2: int = fighters.find(en2[0]) if not en2.is_empty() else actor_idx
		await _take_turn(actor_idx, skill_idx, t2)
		return
	if skill.get("aoeAlly", false):
		await _take_turn(actor_idx, skill_idx, actor_idx)
		return
	# 4) 友方目标 (治疗/给盾) → 选友军
	if stype in SKILL_ALLY or skill.get("isAlly", false):
		var ti: int = await _enter_targeting(actor_idx, "ally", skill)
		if ti < 0:   # 取消 → 重新选技能 (保留 ←换龟)
			await _player_take_turn(actor_idx, can_back)
		else:
			await _take_turn(actor_idx, skill_idx, ti)
		return
	# 5) 默认: 敌方单体 → 选敌人 (taunt/前排守门)
	var ei: int = await _enter_targeting(actor_idx, "enemy", skill)
	if ei < 0:
		await _player_take_turn(actor_idx, can_back)
	else:
		await _take_turn(actor_idx, skill_idx, ei)


## headless 自测: 面板显示后自动点首个可用技能 (模拟玩家点击, 验玩家路径不崩)
func _autoplay_emit_skill(actor_idx: int) -> void:
	var actor: Dictionary = fighters[actor_idx]
	var skills: Array = actor.get("skills", [])
	var pick := 0
	for i in range(skills.size()):
		if not skills[i].get("passiveSkill", false) and _skill_ready(actor, skills[i]):
			pick = i
			break
	get_tree().create_timer(0.05).timeout.connect(func(): _skill_chosen.emit(pick))


## 进入选目标: 高亮候选 → 等玩家点 → 返回 slot idx (-1 = 取消). PoC enterTargetingMode 1:1
## 选目标态: 右键 / Esc → 取消 (返回 -1 → 重选技能, 1:1 PoC「← 返回选技能」)
# 装备席: 5px 阈值判 点击/拖拽 (1:1 PoC BenchRail startDrag), 残影跟随 + 释放落点装备
func _input(event: InputEvent) -> void:
	if _drag_pending_eid == "" and _drag_eid == "":
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = event.position
		# 未起拖且移动 ≥5px → 转为拖拽 (PoC Math.hypot < 5 return)
		if _drag_eid == "" and _drag_pending_eid != "" and mp.distance_to(_drag_start) >= 5.0:
			_drag_eid = _drag_pending_eid
			_start_equip_drag(_drag_eid)
		if _drag_eid != "":
			_update_drag_ghost(mp)
			_show_sell_hint(_drag_eid, mp)   # 悬在商店区 → 显「出售 +N币」+ 商店区高亮 (云顶式拖卖)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag_eid != "":
			get_viewport().set_input_as_handled()
			_finish_equip_drag()
		elif _drag_pending_eid != "":
			# 未移动 = 点击 → 弹装备详情 (PoC onSlotClick 回退)
			get_viewport().set_input_as_handled()
			var clicked := _drag_pending_eid
			_drag_pending_eid = ""
			_show_equip_popup(clicked, {}, _bench_star_of(clicked))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# 右键取消
		if _drag_eid != "" or _drag_pending_eid != "":
			get_viewport().set_input_as_handled()
			_drag_eid = ""
			_drag_pending_eid = ""
			_end_drag_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if not _targeting_active:
		return
	var cancel := event.is_action_pressed("ui_cancel")
	if not cancel and event is InputEventMouseButton:
		cancel = event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if cancel:
		_targeting_active = false
		get_viewport().set_input_as_handled()
		_target_chosen.emit(-1)


func _enter_targeting(actor_idx: int, kind: String, skill: Dictionary) -> int:
	var actor: Dictionary = fighters[actor_idx]
	var ignore_row: bool = skill.get("ignoreRow", false)
	# 候选筛选 (存活 + 侧别 + 排黑洞; 敌方排召唤物)
	var candidates: Array = []
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("alive", false) or f.get("_isInBlackhole", false):
			continue
		if kind == "enemy":
			if f.get("side", "") == actor.get("side", "") or f.get("_isSummon", false) or f.get("_untargetable", false):   # _untargetable(口哨大师等)不可选 — 与 _alive_combatant 一致
				continue
			candidates.append(i)
		else:
			if f.get("side", "") == actor.get("side", ""):
				candidates.append(i)
	# 敌方兜底(审计): 全为召唤物(无非召唤合法目标) → 放开 _isSummon(仍排 _untargetable/黑洞), 否则玩家无靶可点=卡手到超时
	if kind == "enemy" and candidates.is_empty():
		for _i2 in range(fighters.size()):
			var _f2: Dictionary = fighters[_i2]
			if not _f2.get("alive", false) or _f2.get("_isInBlackhole", false) or _f2.get("_untargetable", false):
				continue
			if _f2.get("side", "") != actor.get("side", ""):
				candidates.append(_i2)
	# 敌方: taunt 优先, 否则前排守门 (PoC 2527-2538)
	if kind == "enemy" and not ignore_row:
		var taunters: Array = candidates.filter(func(i): return Buffs.has(fighters[i], "taunt"))
		if not taunters.is_empty():
			candidates = taunters
		else:
			var fronts: Array = candidates.filter(func(i): return fighters[i].get("_position", "") == "front")
			if not fronts.is_empty():
				candidates = fronts
	if candidates.is_empty():
		return -1
	if candidates.size() == 1:   # 只 1 个候选 → 直接打, 不让点 (PoC 2539)
		return candidates[0]
	# 高亮候选 + 等点击
	_picked_target_idx = -2   # -2 = 等待中
	# 修(审计A1#3): 选目标提示改【顶部可见标签】— 原写进 SkillBar(新出手流程已隐藏, 永不显示)=玩家选靶时无任何提示。
	var tgt_hint := Label.new()
	tgt_hint.text = "选择目标 (%s) — 右键/Esc 返回" % skill.get("name", "?")
	tgt_hint.add_theme_font_size_override("font_size", 19)
	tgt_hint.add_theme_color_override("font_color", Color("#ffe9a8"))
	tgt_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tgt_hint.add_theme_constant_override("outline_size", 6)
	tgt_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tgt_hint.anchor_left = 0.0; tgt_hint.anchor_right = 1.0
	tgt_hint.offset_top = 64.0
	tgt_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_layer := CanvasLayer.new()
	hint_layer.layer = 62   # 高于商店(40)+信息面板(60), 否则选靶时开 ⓘ/商店浮层"选择目标"提示被盖 (大卡70仍在上)
	hint_layer.add_child(tgt_hint)
	add_child(hint_layer)
	var rings: Array = _show_target_rings(candidates, kind)
	if auto_play_debug:   # headless 自测: 自动点首个候选
		var c0: int = candidates[0]
		get_tree().create_timer(0.05).timeout.connect(func(): _target_chosen.emit(c0))
	# 右键/Esc 取消 → 返回 -1 重选技能 (1:1 PoC「← 返回选技能」, _unhandled_input 监听)
	_targeting_active = true
	var ti: int = await _target_chosen
	_targeting_active = false
	if is_instance_valid(hint_layer):
		hint_layer.queue_free()
	for r in rings:
		r.queue_free()
	return ti


## 在候选 slot 上画可点的彩色圈 (敌红友绿), 返回创建的节点数组. PoC 红0xff3c3c/绿0x06d6a0
# ── 初始装备选择 (1:1 PoC _maybeRunInitialEquipPhase BattleScene.ts:1713-1741) ──
const _INITIAL_EQUIP_POOL := ["e_turtle_helmet", "e_turtle_sword", "e_turtle_shell"]
var _initial_equip_picked := false

## 教程: 预置装备席 + 启动步骤引导 (1:1 PoC setupTutorialGuide BattleScene.ts:8438-8453)
func _setup_tutorial_guide() -> void:
	bench_inventory.append("e_turtle_sword")   # 1 装备
	bench_inventory.append("c_heal")           # 1 消耗品 (供拖拽教学)
	_rebuild_bench_rail()
	_tutorial_guide = preload("res://scripts/scenes/TutorialGuide.gd").new()
	add_child(_tutorial_guide)
	_tutorial_guide.start([
		{"text": "欢迎来到<b>教程战斗</b>！你的队伍：石头龟(前排) + 小龟·竹叶龟(后排)，对面是 3 只 1 级龟。", "anchor": "top"},
		{"text": "左侧是<b>装备席</b>。把里面的装备/消耗品<b>拖到你的乌龟身上</b>即可装备/使用。先拖一件试试。", "advanceOn": "equip-dropped", "anchor": "top"},
		{"text": "轮到你时，下方会让你<b>选出手的龟 → 选技能 → 选目标</b>。释放一次技能继续。", "advanceOn": "skill-cast", "anchor": "top"},
		{"text": "每隔几回合会开<b>商店</b>(龟币购买)，买到的装备/消耗品同样进装备席，<b>拖到龟身上</b>使用。", "anchor": "top"},
		{"text": "教程到此结束！你可以打完这局，或回主菜单挑战<b>深海闯关</b>。", "anchor": "top"},
	], func(): _tutorial_guide = null)


func _maybe_run_initial_equip_phase() -> void:
	if _initial_equip_picked:
		return
	var mode: String = GameState.mode
	if mode in ["test", "boss-pick", "duallane"] or _is_tutorial:
		return   # 跳过. duallane: 用新装备系统(大地图商店/备战席), 不走老的初始3选1 (用户移除老装备). 教程用预置席.
	if mode == "dungeon" and GameState.dungeon_stage != 1:
		return   # 深海仅第1关 (PoC :1716)
	_initial_equip_picked = true
	var pick: String = await _show_initial_equip_pick_modal()   # 我方 3选1
	if pick != "":
		_apply_initial_equip("left", pick)
	# 敌方(野生/PVP, 非深海人机不选): 随机1 静默 (PoC :1728-1734)
	if mode != "dungeon":
		var epick: String = _INITIAL_EQUIP_POOL[randi() % _INITIAL_EQUIP_POOL.size()]
		_apply_initial_equip("right", epick)
		var en: String = str(DataRegistry.equipment_by_id.get(epick, {}).get("name", epick))
		if battle_log:
			battle_log.append_text("[color=#ffcc66]🎁 敌方选择了初始装备 %s[/color]\n" % en)


## 1:1 PoC _applyInitialEquip(:1737-1740): 选中的初始装备【进装备席】, 玩家拖到龟身上才装 (不直接上身)。
##   敌方(右)Godot AI 无拖拽 → 直接 attach 到首只存活敌龟 (PoC 是进 rightBench 由 aiDrainBench 取)。
func _apply_initial_equip(side: String, equip_id: String) -> void:
	if side == "left":
		bench_inventory.append(equip_id)   # 进我方装备席, 玩家拖装 (PoC addToBench)
		_rebuild_bench_rail()
		return
	var tgt_i := -1
	for i in range(fighters.size()):
		if fighters[i].get("side", "") == side and fighters[i].get("alive", false):
			tgt_i = i
			break
	if tgt_i < 0:
		return
	var tgt: Dictionary = fighters[tgt_i]
	EquipmentRuntime.on_attach(tgt, equip_id)
	if not tgt.has("_equipped_ids"):
		tgt["_equipped_ids"] = []
	(tgt["_equipped_ids"] as Array).append(equip_id)
	var allies: Array = []
	for f in fighters:
		if f.get("side", "") == side:
			allies.append(f)
	StatsRecalc.snapshot_base(tgt)
	StatsRecalc.recalc(tgt, allies)
	_refresh_slot(tgt_i)


## 初始装备 3选1 modal (1:1 PoC showInitialEquipPickModal :465-540): 遮罩+标题+3卡, 点击选。
func _show_initial_equip_pick_modal() -> String:
	var layer := CanvasLayer.new()
	layer.add_to_group("ui_modal")   # modal 浮层: 开着时挡住背后龟身 Area2D 点击 (修"点穿透到后面")
	layer.layer = 30
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.012, 0.031, 0.07, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var title := Label.new()
	title.text = "选择你的初始装备"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("#f0e6d2"))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_outline_color", Color(0.31, 0.67, 1.0, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.position = Vector2(0, 70)
	layer.add_child(title)
	var total_w := 3 * 300 + 2 * 40
	var x0 := (VIEW_W - total_w) / 2.0
	for k in range(_INITIAL_EQUIP_POOL.size()):
		var eid: String = _INITIAL_EQUIP_POOL[k]
		var card := _make_equip_card(eid)
		card.position = Vector2(x0 + k * (300 + 40), 150)
		layer.add_child(card)
		card.modulate.a = 0.0   # 错峰入场 (PoC translateY18→0 + alpha, delay 90+95k)
		var cy := card.position.y
		card.position.y = cy + 18.0
		var tw := card.create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.09 + 0.095 * k)
		tw.tween_property(card, "position:y", cy, 0.25).set_delay(0.09 + 0.095 * k)
	var picked: String = await _equip_picked
	layer.queue_free()
	return picked


## 单张初始装备卡 (300×539: equip-select-frame 框 + 122图标 + 名 + 描述 + 点击/hover1.05)。
func _make_equip_card(eid: String) -> Control:
	var eq: Dictionary = DataRegistry.equipment_by_id.get(eid, {})
	var card := Control.new()
	card.custom_minimum_size = Vector2(300, 539)
	card.size = Vector2(300, 539)
	card.pivot_offset = Vector2(150, 269)
	var frame := TextureRect.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/sprites/ui/equip-select-frame.png"):
		frame.texture = load("res://assets/sprites/ui/equip-select-frame.png")
	card.add_child(frame)
	var icon := TextureRect.new()
	icon.size = Vector2(122, 122)
	icon.position = Vector2((300 - 122) / 2.0, 70)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ipath := "res://assets/sprites/" + str(eq.get("icon", ""))
	if ResourceLoader.exists(ipath):
		icon.texture = load(ipath)
	card.add_child(icon)
	var nm := Label.new()
	nm.text = str(eq.get("name", "?"))
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Color("#f0e6d2"))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.size = Vector2(300, 30)
	nm.position = Vector2(0, 215)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(nm)
	var desc := Label.new()
	desc.text = _strip_html(str(eq.get("desc", eq.get("brief", eq.get("detail", "")))))
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", Color("#bcd6e6"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(195, 0)
	desc.size = Vector2(195, 220)
	desc.position = Vector2((300 - 195) / 2.0, 268)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func() -> void: _equip_picked.emit(eid))
	btn.mouse_entered.connect(func() -> void: card.scale = Vector2(1.05, 1.05))
	btn.mouse_exited.connect(func() -> void: card.scale = Vector2.ONE)
	card.add_child(btn)
	return card


func _strip_html(s: String) -> String:
	var re := RegEx.new()
	re.compile("<[^>]*>")
	return re.sub(s, "", true).strip_edges()


## 行动龟脚底回合圈 (1:1 PoC startActorTurn:2384-2392): 76×28 椭圆描边(绿我方/红敌方),
##   展开 scale0.55→1.3 + alpha.95→0 over 560ms 然后销毁。世界层(随相机), 龟身下。
func _play_turn_foot_ring(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var f: Dictionary = fighters[idx]
	var col := Color("#06d6a0") if f.get("side", "") == "left" else Color("#ff6b6b")
	var pos: Vector2 = slot_nodes[idx].get_meta("home_pos", slot_nodes[idx].position)
	var ring := Node2D.new()
	ring.position = pos + Vector2(0, -6.0)   # 脚底略上 (PoC groundY = sprite.y+dh/2-6)
	ring.z_index = 1                          # 龟身下、bg 上 (PoC depth 1)
	var line := Line2D.new()
	var pts := PackedVector2Array()
	for k in range(29):
		var a := TAU * k / 28.0
		pts.append(Vector2(cos(a) * 38.0, sin(a) * 14.0))   # 76×28 椭圆
	line.points = pts
	line.width = 3.0
	line.default_color = col
	line.closed = true
	ring.add_child(line)
	slots_root.add_child(ring)
	ring.scale = Vector2(0.55, 0.55)
	ring.modulate.a = 0.95
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.3, 1.3), 0.56)
	tw.tween_property(ring, "modulate:a", 0.0, 0.56)
	tw.chain().tween_callback(ring.queue_free)


func _show_target_rings(candidates: Array, kind: String) -> Array:
	# 1:1 PoC enterTargetingMode(:2546-2570): 候选龟身上 150×150 方框(敌红/友绿) + ring 脉冲
	#   + 龟本体 ×1.05 脉冲。**世界层(slots_root)**而非 CanvasLayer → 随相机 ENVELOP cover-zoom 变换,
	#   不再像旧 Button 在 CanvasLayer 上跟相机错位 (= 用户报"选目标没提示/不对位")。
	var color := Color("#06d6a0") if kind == "ally" else Color("#ff3c3c")
	var out: Array = []
	for i in candidates:
		var pos: Vector2 = slot_nodes[i].get_meta("home_pos", slot_nodes[i].position)
		var av = slot_nodes[i].get_meta("avatar", null)
		var center: Vector2 = pos + (av.position if is_instance_valid(av) else Vector2(0, -51))
		var ring := Node2D.new()
		ring.position = center
		ring.z_index = 60
		# 4px 描边闭合矩形 (Line2D) — 1:1 PoC 仅描边、无填充 (BattleScene.ts:2552 add.rectangle stroke-only;
		#   原 .12 半透填充=自创, 注释"PoC bg .12"引的是旧 JS DOM 的 CSS 非 Phaser PoC, 已删)
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(-75, -75), Vector2(75, -75), Vector2(75, 75), Vector2(-75, 75)])
		line.closed = true
		line.width = 4.0
		line.default_color = color
		ring.add_child(line)
		slots_root.add_child(ring)
		# 点击 Area2D (世界空间拾取, 随相机变换 — Control 做不到)
		var area := Area2D.new()
		area.input_pickable = true
		var cs := CollisionShape2D.new()
		var shp := RectangleShape2D.new()
		shp.size = Vector2(150, 150)
		cs.shape = shp
		area.add_child(cs)
		var idx_copy: int = i
		area.input_event.connect(func(vp: Node, ev: InputEvent, _s: int) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				vp.set_input_as_handled()   # 消费, 别同时触发龟身详情 Area2D
				_target_chosen.emit(idx_copy))
		ring.add_child(area)
		# ring 脉冲 alpha .95↔.4 (PoC 2556)
		ring.modulate.a = 0.95
		var rtw := create_tween().set_loops()
		rtw.tween_property(ring, "modulate:a", 0.4, 0.4)
		rtw.tween_property(ring, "modulate:a", 0.95, 0.4)
		# 龟本体 ×1.05 脉冲 (PoC 2557-2558) — 提示极明显; ring 释放时复原
		if is_instance_valid(av):
			var base_scale: Vector2 = av.scale
			var ptw := create_tween().set_loops()
			ptw.tween_property(av, "scale", base_scale * 1.05, 0.4)
			ptw.tween_property(av, "scale", base_scale, 0.4)
			ring.tree_exiting.connect(func() -> void:
				if ptw.is_valid():
					ptw.kill()
				if is_instance_valid(av):
					av.scale = base_scale)
		out.append(ring)
	return out


# ─── ActionPanel UI (底部技能卡条 + 自动战开关) ──────────────────

## 建面板 (在 _ready 调一次): CanvasLayer + 底部容器 + 右上自动战按钮
var _skill_icon_layer: CanvasLayer = null   # 龟前漂浮技能图标层 (替代底部施法卡条; 用户: "龟前出图标点击选目标")


func _create_action_panel() -> void:
	action_panel = CanvasLayer.new()
	action_panel.layer = 10
	add_child(action_panel)

	# 底部技能卡条容器 (默认隐藏) — PoC ActionPanel: bottom:12px 居中, min-width 533, 内容自适应宽
	var bar := PanelContainer.new()
	bar.name = "SkillBar"
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN   # 向上长高 (底沿钉住)
	bar.custom_minimum_size = Vector2(533, 0)          # PoC min-width 533 (scale1)
	bar.offset_top = -176
	bar.offset_bottom = -12
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.078, 0.106, 0.196, 0.97)   # PoC rgba(18,24,40,.97) 渐变近似
	sb.set_border_width_all(2)
	sb.border_color = Color("#3a4a6a")               # PoC border 2px #3a4a6a
	sb.set_corner_radius_all(11)                     # PoC radius 11
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 13; sb.content_margin_bottom = 16   # PoC padding 13 20 16
	bar.add_theme_stylebox_override("panel", sb)
	bar.visible = false
	action_panel.add_child(bar)

	var vb := VBoxContainer.new()
	vb.name = "VB"
	vb.add_theme_constant_override("separation", 6)
	bar.add_child(vb)
	# 头部 (1:1 PoC ActionPanel .action-header): 头像 + 行动名 + "的回合" + 右侧提示
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 7)
	# ←换龟 (PoC btn-back-picker; 同侧>1可动才显, _show_action_panel 控显隐)
	var back_btn := Button.new()
	back_btn.name = "BackBtn"
	back_btn.text = "← 换龟"
	back_btn.flat = true
	back_btn.add_theme_font_size_override("font_size", 12)
	back_btn.add_theme_color_override("font_color", Color("#aaaaaa"))
	back_btn.add_theme_color_override("font_hover_color", Color("#58a6ff"))
	back_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_btn.visible = false
	back_btn.pressed.connect(func() -> void:
		_player_wants_back = true
		_skill_chosen.emit(-1))   # 解开 _player_take_turn 的 await; flag 让它回选龟框
	header.add_child(back_btn)
	# 头像 33×33 金边 (PoC .ah-avatar)
	var av_wrap := PanelContainer.new()
	av_wrap.name = "AvatarWrap"
	var avsb := StyleBoxFlat.new()
	avsb.bg_color = Color(0, 0, 0, 0.35)
	avsb.set_border_width_all(2); avsb.border_color = Color("#ffd86b")
	avsb.set_corner_radius_all(7)
	av_wrap.add_theme_stylebox_override("panel", avsb)
	var av := TextureRect.new()
	av.name = "Avatar"
	av.custom_minimum_size = Vector2(33, 33); av.size = Vector2(33, 33)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	av_wrap.add_child(av)
	header.add_child(av_wrap)
	# 行动名 (金 bold 18, PoC .acting-name)
	var nm := Label.new()
	nm.name = "ActingName"
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color("#ffe9a8"))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(nm)
	var of := Label.new()
	of.text = " 的回合"
	of.add_theme_font_size_override("font_size", 14)
	of.add_theme_color_override("font_color", Color("#b8c2cc"))
	of.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(of)
	# 右侧提示 (PoC .hint margin-left:auto)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "选择技能"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#888888"))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hint)
	vb.add_child(header)
	var cards := HBoxContainer.new()
	cards.name = "Cards"
	cards.add_theme_constant_override("separation", 8)
	vb.add_child(cards)

	# (PoC _autoBattle 仅 F3/window.__autoBattle() 调试钩子, 无玩家可见按钮 — BattleScene.ts:979/2352;
	#  曾自创的 "▶ 自动战斗" 操作面板按钮已删。auto_battle flag + 守卫保留 = 等同 PoC 内部标志。)


## 显示面板: 为 actor 列技能卡 (PoC ActionPanel.show). can_back=同侧>1可动 → 显「←换龟」
## 龟前漂浮技能图标 (用户: "龟的前方出现技能图标, 点击后选择目标, 不要现在的施法面板")。
## 替代底部 SkillBar: 在出手龟正上方横排技能图标, 点击 → _skill_chosen.emit(idx) (下游选靶不变)。
func _show_action_panel(actor_idx: int, can_back: bool = false) -> void:
	_hide_skill_icons()
	if actor_idx < 0 or actor_idx >= fighters.size() or actor_idx >= slot_nodes.size():
		return
	var actor: Dictionary = fighters[actor_idx]
	var node: Node2D = slot_nodes[actor_idx]
	if not is_instance_valid(node):
		return
	var sp: Vector2 = node.get_global_transform_with_canvas().origin   # 出手龟屏幕坐标 (含相机变换)
	var vp: Vector2 = get_viewport_rect().size
	_skill_icon_layer = CanvasLayer.new()
	_skill_icon_layer.layer = 50   # 高于商店层(40)+面板, 否则商店挡住技能图标点击=出不了手
	add_child(_skill_icon_layer)
	var skills: Array = actor.get("skills", [])
	var idxs: Array = []
	for i in range(skills.size()):
		if not skills[i].get("passiveSkill", false):
			idxs.append(i)
	var icon_w := 58.0
	var gap := 10.0
	var back_extra: float = 60.0 if can_back else 0.0   # ←换钮(50) + 间隙(10)
	var total_w: float = float(idxs.size()) * icon_w + maxf(0.0, float(idxs.size()) - 1.0) * gap + back_extra
	var start_x: float = clampf(sp.x - total_w / 2.0, 8.0, maxf(8.0, vp.x - total_w - 8.0))
	var row_y: float = clampf(sp.y - 154.0, 60.0, vp.y - 260.0)   # 龟头顶上方, 防出屏
	var x := start_x
	var tag := Label.new()
	tag.text = "%s 出手 · 选技能" % str(actor.get("name", "?"))
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color("#ffe9a8"))
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tag.add_theme_constant_override("outline_size", 5)
	tag.position = Vector2(start_x, row_y - 22.0)
	_skill_icon_layer.add_child(tag)
	if can_back:
		var bb := Button.new()
		bb.text = "←换"
		bb.custom_minimum_size = Vector2(50.0, icon_w)
		bb.size = Vector2(50.0, icon_w)
		bb.add_theme_font_size_override("font_size", 13)
		bb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		bb.position = Vector2(x, row_y)
		bb.pressed.connect(func() -> void:
			_player_wants_back = true
			_skill_chosen.emit(-1))   # 1:1 旧 BackBtn: flag + 解 await → 回选龟框
		_skill_icon_layer.add_child(bb)
		x += 50.0 + gap
	for i in idxs:
		var ic := _make_skill_icon(actor, skills[i], i, icon_w)
		ic.position = Vector2(x, row_y)
		_skill_icon_layer.add_child(ic)
		x += icon_w + gap


func _hide_skill_icons() -> void:
	if _skill_icon_layer != null and is_instance_valid(_skill_icon_layer):
		_skill_icon_layer.queue_free()
	_skill_icon_layer = null


## 单技能图标 (58×58 框 + 名 + cd角标): ready→点击 emit, 否则灰+cd数。
func _make_skill_icon(actor: Dictionary, s: Dictionary, idx: int, sz: float) -> Control:
	var ready: bool = _skill_ready(actor, s)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(sz, sz + 16.0)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(sz, sz)
	box.size = Vector2(sz, sz)
	box.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.18, 0.92)
	sb.set_border_width_all(2)
	sb.border_color = Color("#ffd86b") if ready else Color(0.4, 0.43, 0.5, 0.7)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 4
	sb.set_content_margin_all(2)
	box.add_theme_stylebox_override("panel", sb)
	wrap.add_child(box)
	var icon_raw: String = str(s.get("icon", ""))
	if icon_raw.ends_with(".png") and ResourceLoader.exists("res://assets/sprites/%s" % icon_raw):
		var ic := TextureRect.new()
		ic.texture = load("res://assets/sprites/%s" % icon_raw)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
	else:
		var emo := Label.new()
		emo.text = icon_raw if icon_raw != "" else "❓"
		emo.add_theme_font_size_override("font_size", 30)
		emo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		emo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(emo)
	var nm := Label.new()
	nm.text = str(s.get("name", ""))
	nm.add_theme_font_size_override("font_size", 10)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	nm.add_theme_constant_override("outline_size", 4)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(-6.0, sz + 1.0)
	nm.size = Vector2(sz + 12.0, 14.0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(nm)
	if ready:
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_skill_chosen.emit(idx))
	else:
		wrap.modulate = Color(1, 1, 1, 0.5)
		var cdl: int = int(s.get("cdLeft", 0))
		if cdl > 0:
			var clbl := Label.new()
			clbl.text = "%d" % cdl
			clbl.add_theme_font_size_override("font_size", 22)
			clbl.add_theme_color_override("font_color", Color("#ff7b7b"))
			clbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			clbl.add_theme_constant_override("outline_size", 4)
			clbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			clbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			clbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			clbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(clbl)
	return wrap


## 单技能卡 (1:1 PoC ActionPanel skill-card): 图标47 + 名(段数/cd-tag) + brief(带色) + 详略toggle. 灰=禁用
func _make_skill_card(actor: Dictionary, s: Dictionary, idx: int) -> Control:
	var ready := _skill_ready(actor, s)
	var hits: int = int(s.get("hits", 1))
	var hits_label := " ×%d" % hits if hits > 1 else ""
	# 卡片 (PanelContainer, 渐变底 + 边, 点选技能)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(184, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.137, 0.176, 0.271, 0.72)          # PoC rgba(44,56,86,.72)
	csb.set_border_width_all(2); csb.border_color = Color(0.47, 0.55, 0.71, 0.42)
	csb.set_corner_radius_all(11)
	csb.content_margin_left = 12; csb.content_margin_right = 12
	csb.content_margin_top = 10; csb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", csb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	if ready:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_skill_chosen.emit(idx))
	else:
		card.modulate = Color(1, 1, 1, 0.5)                  # PoC disabled grayscale.7 opacity.5
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	# main 行: 图标 47 + 身体(名+brief)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 7)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(main)
	var icon_raw: String = str(s.get("icon", ""))
	if icon_raw != "":
		# 1:1 PoC .skill-icon/.skill-icon-emoji 框 (ActionPanel.ts:124-131): 47×47 radius8 border1px白.22 bg黑.32 (原Godot裸图无框)
		var icon_box := PanelContainer.new()
		icon_box.custom_minimum_size = Vector2(47, 47)
		icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.clip_contents = true
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(0, 0, 0, 0.32)              # PoC bg rgba(0,0,0,.32)
		isb.border_color = Color(1, 1, 1, 0.22)          # PoC border 1px rgba(255,255,255,.22)
		isb.set_border_width_all(1)
		isb.set_corner_radius_all(8)                     # PoC border-radius 8
		isb.set_content_margin_all(0)
		icon_box.add_theme_stylebox_override("panel", isb)
		if icon_raw.ends_with(".png") and ResourceLoader.exists("res://assets/sprites/%s" % icon_raw):
			var ic := TextureRect.new()
			ic.texture = load("res://assets/sprites/%s" % icon_raw)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED   # PoC object-fit:cover
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_box.add_child(ic)
		else:
			# emoji 兜底 (1:1 PoC .skill-icon-emoji font 28)
			var emo := Label.new()
			emo.text = icon_raw
			emo.add_theme_font_size_override("font_size", 28)
			emo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			emo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			emo.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_box.add_child(emo)
		main.add_child(icon_box)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(body)
	# 名 (含段数; 不可用→红 cd-tag 接在后)
	var name_lbl := RichTextLabel.new()
	name_lbl.bbcode_enabled = true
	name_lbl.fit_content = true
	name_lbl.scroll_active = false
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("normal_font_size", 16)
	name_lbl.add_theme_font_size_override("bold_font_size", 16)
	name_lbl.add_theme_font_override("normal_font", _get_panel_font(false))   # 强制 m6x11+YaHei (RichTextLabel 不稳定继承主题字体)
	name_lbl.add_theme_font_override("bold_font", _get_panel_font(true))      # [b] 用合成粗体 (PoC 技能名 weight 900)
	var reason := _skill_reason(actor, s) if not ready else ""
	var cd_tag := "  [color=#ff6b6b]%s[/color]" % reason if reason != "" else ""
	# 资源消耗 (龟能蓝⚡ / 怒气橙🔥, cost>0 时显; 放不起由 _skill_ready 置灰)
	var cinfo := _skill_cost_info(actor, s)
	var ecost_tag := "  [color=%s]%s%d[/color]" % [cinfo["color"], cinfo["icon"], int(cinfo["cost"])] if not cinfo.is_empty() else ""
	name_lbl.text = "[color=#ffe9a8][b]%s%s[/b][/color]%s%s" % [s.get("name", "?"), hits_label, ecost_tag, cd_tag]
	body.add_child(name_lbl)
	# brief / detail (带色 bbcode)
	var brief_bb: String = SkillText.render_bbcode(str(s.get("brief", "")), actor, s)
	var detail_src: String = str(s.get("detail", s.get("brief", "")))
	var detail_bb: String = SkillText.render_bbcode(detail_src, actor, s)
	var brief_lbl := RichTextLabel.new()
	brief_lbl.name = "Brief"
	brief_lbl.bbcode_enabled = true
	brief_lbl.fit_content = true
	brief_lbl.scroll_active = false
	brief_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief_lbl.custom_minimum_size = Vector2(150, 0)
	brief_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brief_lbl.add_theme_font_size_override("normal_font_size", 11)
	brief_lbl.add_theme_font_override("normal_font", _get_panel_font(false))
	brief_lbl.add_theme_font_override("bold_font", _get_panel_font(true))
	brief_lbl.add_theme_color_override("default_color", Color("#aaaaaa"))
	brief_lbl.text = brief_bb
	body.add_child(brief_lbl)
	# 基础冷却子行 (1:1 PoC ActionPanel.ts:338 .skill-cd-info "冷却N回合", 仅 cd>0 且 <100)
	var cd_base: int = int(s.get("cd", 0))
	if cd_base > 0 and cd_base < 100:
		var cdl := Label.new()
		cdl.text = "冷却 %d回合" % cd_base
		cdl.add_theme_font_size_override("font_size", 11)   # PoC .skill-cd-info font-size:11px
		cdl.add_theme_color_override("font_color", Color(0.667, 0.667, 0.667, 0.7))   # PoC color:#aaa opacity:.7
		cdl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(cdl)
	var detail_lbl := RichTextLabel.new()
	detail_lbl.name = "Detail"
	detail_lbl.bbcode_enabled = true
	detail_lbl.fit_content = true
	detail_lbl.scroll_active = false
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.custom_minimum_size = Vector2(150, 0)
	detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_lbl.add_theme_font_size_override("normal_font_size", 11)
	detail_lbl.add_theme_font_override("normal_font", _get_panel_font(false))
	detail_lbl.add_theme_font_override("bold_font", _get_panel_font(true))
	detail_lbl.add_theme_color_override("default_color", Color("#aaaaaa"))
	detail_lbl.text = detail_bb
	detail_lbl.visible = false
	body.add_child(detail_lbl)
	# 详略 toggle (仅 detail≠brief 时; PoC skill-toggle 详细▾/简略▴)
	if detail_bb != brief_bb:
		var tg := Button.new()
		tg.flat = true
		tg.text = "详细 ▾"
		tg.add_theme_font_size_override("font_size", 11)
		tg.add_theme_color_override("font_color", Color("#58a6ff"))
		tg.add_theme_color_override("font_hover_color", Color("#8ec5ff"))
		tg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tg.size_flags_horizontal = Control.SIZE_SHRINK_END
		tg.mouse_filter = Control.MOUSE_FILTER_STOP
		tg.pressed.connect(func() -> void:
			var open := not detail_lbl.visible
			detail_lbl.visible = open
			brief_lbl.visible = not open
			tg.text = "简略 ▴" if open else "详细 ▾")
		vb.add_child(tg)
	return card


## 不可用技能的红字原因 (1:1 PoC ActionPanel reasonStr :298-311)
func _skill_reason(actor: Dictionary, s: Dictionary) -> String:
	var cd_left: int = int(s.get("cdLeft", 0))
	if cd_left > 0:
		return "CD%d" % cd_left
	var t: String = str(s.get("type", ""))
	match t:
		"hidingCommand", "hidingBuffSummon":
			return "随从已阵亡"
		"fortuneAllIn":
			return "无金币"
		"bubbleBurst":
			return "无泡沫"
		"gamblerBet":
			return "HP过低"
		"fortuneBuyEquip":
			var fbe_c: int = int(actor.get("_fortuneBuyCost", s.get("coinCost", 20)))
			return "金币不足" if int(actor.get("_goldCoins", 0)) < fbe_c else "席满且满血"
	if s.get("passiveSkill", false):
		return "被动"
	return "不可用"


## 技能可用判定 (PoC ActionPanel ready: cdLeft==0 + 特殊职业条件)
func _skill_ready(actor: Dictionary, s: Dictionary) -> bool:
	if Buffs.has(actor, "confused"):   # 混乱: 全技能不可用(动作面板置灰) — 用户新状态
		return false
	if int(s.get("cdLeft", 0)) > 0:
		return false
	if not _can_afford_energy(actor, s):   # 龟能不足 → 放不起 → 置灰不可点
		return false
	var t: String = s.get("type", "")
	match t:
		"hidingCommand", "hidingBuffSummon":
			# 随从存活才可用 (1:1 PoC ActionPanel.ts:265-266; 旧版漏了 hidingBuffSummon)
			var summon = actor.get("_summon", null)
			return summon is Dictionary and summon.get("alive", false)
		"fortuneAllIn":
			return int(actor.get("_goldCoins", 0)) > 0
		"gamblerBet":
			return float(actor.get("hp", 0)) / maxf(1.0, actor.get("maxHp", 1)) > 0.4
		"bubbleBurst":
			# 1:1 PoC ActionPanel.ts:282 读 bubbleStore (旧版读 bubbleShieldVal = 独立护盾, 永灰)
			return int(actor.get("bubbleStore", 0)) > 0
		"fortuneBuyEquip":
			# 币不够 → 禁; 币够但席满(≥10)且全员满血 → 纯浪费禁 (1:1 PoC ActionPanel.ts:269-281)
			var fbe_cost: int = int(actor.get("_fortuneBuyCost", s.get("coinCost", 20)))
			if int(actor.get("_goldCoins", 0)) < fbe_cost:
				return false
			if bench_inventory.size() >= 10:
				var fbe_allies: Array = []
				for a in fighters:
					if a.get("side", "") == actor.get("side", "") and a.get("alive", false):
						fbe_allies.append(a)
				if not fbe_allies.is_empty() and fbe_allies.all(func(a): return int(a.get("hp", 0)) >= int(a.get("maxHp", 0))):
					return false
			return true
	return true


func _hide_action_panel() -> void:
	_hide_skill_icons()
	if action_panel == null:
		return
	var bar: PanelContainer = action_panel.get_node_or_null("SkillBar")
	if bar:
		bar.visible = false
	_position_battle_shop(false)   # 技能条隐藏 → 整备商店落回贴底


# ─── 战中商店 (1:1 PoC ShopOverlay, turn%4开店) ────────────────
func _open_shop(shop_index: int) -> void:
	_shop_reroll_cost = 2   # G8: 每次开店重置重投费 (1:1 PoC ShopOverlay.open rerollCost=2, 非跨场累加)
	var items: Array = ShopData.roll(shop_index)
	# 财富羁绊: 左队存活若有 _synergyWealthShopDiscount → 非重投格打折 (PoC ShopOverlay applyWealthDisc)
	var live_left: Array = fighters.filter(func(f): return f.get("side", "") == "left" and f.get("alive", false))
	var wealth_disc: float = ShopData.team_wealth_discount(live_left)
	if wealth_disc > 0.0:
		ShopData.apply_wealth_discount(items, wealth_disc)
	var layer := CanvasLayer.new()
	layer.add_to_group("ui_modal")   # modal 浮层: 开着时挡住背后龟身 Area2D 点击 (修"点穿透到后面")
	layer.layer = 30
	add_child(layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.05, 0.08, 0.82)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH; panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -480; panel.offset_right = 480; panel.offset_top = -260; panel.offset_bottom = 260
	# 面板底图 (PoC ShopOverlay.ts:88-91: url('menu/shop-panel-bg.png') center/100% 100% no-repeat,
	#   兜底深色渐变 + border 2px rgba(120,170,255,.35) radius18)
	var shop_bg_path := "res://assets/sprites/menu/shop-panel-bg.png"
	if ResourceLoader.exists(shop_bg_path):
		var psb_tex := StyleBoxTexture.new()
		psb_tex.texture = load(shop_bg_path)
		psb_tex.set_content_margin_all(16)
		panel.add_theme_stylebox_override("panel", psb_tex)
	else:
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(0.07, 0.09, 0.16, 0.97); psb.set_border_width_all(2); psb.border_color = Color("#78aaff"); psb.set_corner_radius_all(14); psb.set_content_margin_all(16)
		panel.add_theme_stylebox_override("panel", psb)
	layer.add_child(panel)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 10); panel.add_child(vb)
	# 头部
	var head := HBoxContainer.new(); vb.add_child(head)
	var title := Label.new(); title.text = "🛒 小商店 · 第 %d 次" % (shop_index + 1); title.add_theme_font_size_override("font_size", 22); title.add_theme_color_override("font_color", Color("#ffd93d")); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(title)
	# 货币显示 (PoC ShopOverlay.ts:105-111: deep-coin.png icon + 数值; 非 emoji)
	var coin_box := HBoxContainer.new(); coin_box.add_theme_constant_override("separation", 4); head.add_child(coin_box)
	var coin_ic := _shop_coin_icon(18); coin_box.add_child(coin_ic)
	var coin_l := Label.new(); coin_l.add_theme_font_size_override("font_size", 18); coin_l.add_theme_color_override("font_color", Color("#aef0ff")); coin_box.add_child(coin_l)
	var timer_l := Label.new(); timer_l.add_theme_font_size_override("font_size", 18); timer_l.custom_minimum_size = Vector2(70, 0); head.add_child(timer_l)
	var grid := GridContainer.new(); grid.columns = 3; grid.add_theme_constant_override("h_separation", 12); grid.add_theme_constant_override("v_separation", 12); vb.add_child(grid)
	var skip := Button.new(); skip.text = "跳过"; skip.custom_minimum_size = Vector2(0, 40); skip.pressed.connect(func(): _shop_closed.emit()); vb.add_child(skip)

	var refresh_coin := func(): coin_l.text = "%d" % GameState.battle_coins
	refresh_coin.call()
	var rebuild = func(): pass
	rebuild = func():
		for c in grid.get_children(): c.queue_free()
		for it in items:
			grid.add_child(_make_shop_card(it, shop_index, refresh_coin, rebuild, items))
	rebuild.call()

	# 30秒倒计时
	var left := 30
	timer_l.text = "⏳ %d" % left
	var tick := Timer.new(); tick.wait_time = 1.0; tick.autostart = true; layer.add_child(tick)
	tick.timeout.connect(func():
		left -= 1
		timer_l.text = "⏳ %d" % maxi(0, left)
		timer_l.add_theme_color_override("font_color", Color("#ff7a7a") if left <= 10 else Color("#ffff99"))
		if left <= 0: _shop_closed.emit())

	if auto_play_debug:   # headless 自测: 0.1s 后自动跳过
		get_tree().create_timer(0.1).timeout.connect(func(): _shop_closed.emit())
	await _shop_closed
	tick.queue_free()
	layer.queue_free()
	await get_tree().create_timer(0.3).timeout


## 单个商品卡 (名/描述/价 + 买按钮); 买后置灰
func _make_shop_card(it: Dictionary, shop_index: int, refresh_coin: Callable, rebuild: Callable, items: Array) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 130)
	var cb := StyleBoxFlat.new()
	var rar: String = it.get("rarity", "normal")
	var bcol: Color = {"normal": Color(0.6,0.63,0.7,0.5), "consumable": Color(0.35,0.78,0.86,0.6), "buff": Color(0.43,0.86,0.55,0.6), "unique": Color(1,0.78,0.27,0.7), "reroll": Color(0.75,0.51,1,0.7)}.get(rar, Color(0.6,0.6,0.6))
	# PoC .shop-item: border 1px(稀有色) radius10 padding 14px 14px 12px (ShopOverlay.ts:128-135)
	cb.bg_color = Color(0.08,0.12,0.18,0.9); cb.set_border_width_all(1); cb.border_color = bcol; cb.set_corner_radius_all(10)
	cb.content_margin_left = 14; cb.content_margin_right = 14; cb.content_margin_top = 14; cb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", cb)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 3); v.alignment = BoxContainer.ALIGNMENT_CENTER; card.add_child(v)
	# 商品格图标 (PoC ShopOverlay.ts:136-144,507-521: 64px 装备 png / emoji; reroll=🔄)
	var icon_node := _shop_item_icon(it)
	if icon_node != null:
		v.add_child(icon_node)
	var nm := Label.new(); nm.text = it.get("name", "?"); nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.add_theme_font_size_override("font_size", 14); nm.add_theme_color_override("font_color", Color("#eee")); v.add_child(nm)   # PoC .shop-item-name 14px
	var ds := Label.new(); ds.text = it.get("desc", ""); ds.add_theme_font_size_override("font_size", 11); ds.add_theme_color_override("font_color", Color("#bbc")); ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ds.custom_minimum_size = Vector2(0, 44); v.add_child(ds)   # PoC .shop-item-desc min-height:44px
	var buy := Button.new()
	# PoC .shop-item-buy: 蓝渐变(纯色近似) 白字 radius7 padding6/16 font13; disabled 灰@.6 (ShopOverlay.ts:152-168)
	var buy_sb := StyleBoxFlat.new()
	buy_sb.bg_color = Color(0.27, 0.55, 0.9)
	buy_sb.set_corner_radius_all(7)
	buy_sb.content_margin_left = 16; buy_sb.content_margin_right = 16
	buy_sb.content_margin_top = 6; buy_sb.content_margin_bottom = 6
	var buy_hover := buy_sb.duplicate(); buy_hover.bg_color = Color(0.34, 0.62, 0.95)
	var buy_dis := buy_sb.duplicate(); buy_dis.bg_color = Color(0.31, 0.31, 0.35, 0.5)
	buy.add_theme_stylebox_override("normal", buy_sb)
	buy.add_theme_stylebox_override("hover", buy_hover)
	buy.add_theme_stylebox_override("pressed", buy_hover)
	buy.add_theme_stylebox_override("focus", buy_sb)
	buy.add_theme_stylebox_override("disabled", buy_dis)
	buy.add_theme_font_size_override("font_size", 13)
	buy.add_theme_color_override("font_color", Color("#ffffff"))
	buy.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	buy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 买按钮货币图标 (PoC ShopOverlay.ts:160-162: buy 按钮内 deep-coin.png) — 用 Button.icon 当价格币图
	var deep_coin_path := "res://assets/sprites/battle/deep-coin.png"
	if ResourceLoader.exists(deep_coin_path):
		buy.icon = load(deep_coin_path)
		buy.add_theme_constant_override("icon_max_width", 15)
		buy.expand_icon = true
	if rar == "reroll":
		buy.text = "🔄 %d" % _shop_reroll_cost
		buy.disabled = GameState.battle_coins < _shop_reroll_cost
		buy.pressed.connect(func():
			if GameState.battle_coins < _shop_reroll_cost: return
			GameState.battle_coins -= _shop_reroll_cost
			_shop_reroll_cost += 1
			var ni: Array = ShopData.roll(shop_index)
			items.clear(); items.append_array(ni)
			var ll: Array = fighters.filter(func(f): return f.get("side", "") == "left" and f.get("alive", false))
			var wd: float = ShopData.team_wealth_discount(ll)
			if wd > 0.0:
				ShopData.apply_wealth_discount(items, wd)
			refresh_coin.call(); rebuild.call())
	else:
		buy.text = "%d" % it.get("price", 0)
		buy.disabled = it.get("_bought", false) or GameState.battle_coins < int(it.get("price", 0))
		if it.get("_bought", false):
			buy.text = "✓ 已购"
			buy.icon = null
		buy.pressed.connect(func():
			if it.get("_bought", false) or GameState.battle_coins < int(it.get("price", 0)): return
			GameState.battle_coins -= int(it["price"])
			_shop_apply(it)
			it["_bought"] = true
			refresh_coin.call(); rebuild.call())
	v.add_child(buy)
	return card


## 货币图标 (PoC ShopOverlay deep-coin.png) — 指定边长的 TextureRect
func _shop_coin_icon(px: int) -> TextureRect:
	var ic := TextureRect.new()
	var p := "res://assets/sprites/battle/deep-coin.png"
	if ResourceLoader.exists(p):
		ic.texture = load(p)
	ic.custom_minimum_size = Vector2(px, px)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


## 商品格 64px 图标 (PoC ShopOverlay.ts:136-144,507-521: 装备 png / emoji; reroll=🔄, 增益=name 首 token)
func _shop_item_icon(it: Dictionary) -> Control:
	# 装备: equipId → equipment.icon (.png) → res://assets/sprites/<icon>
	var eid: String = it.get("equipId", "")
	if eid != "":
		var eq_def: Dictionary = DataRegistry.equipment_by_id.get(eid, {})
		var icon_rel: String = eq_def.get("icon", "")
		if icon_rel.ends_with(".png"):
			var ipath := "res://assets/sprites/%s" % icon_rel
			if ResourceLoader.exists(ipath):
				var ic := TextureRect.new()
				ic.texture = load(ipath)
				ic.custom_minimum_size = Vector2(64, 64)
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				return ic
	# reroll / 增益: emoji (reroll=🔄; 增益 name 以 emoji 开头, 取首 token) — PoC slotIconHtml:508,519
	var glyph := "📦"
	if it.get("rarity", "") == "reroll":
		glyph = "🔄"
	else:
		var nm: String = str(it.get("name", "")).strip_edges()
		var first := nm.split(" ", false)
		if not first.is_empty() and first[0] != "":
			glyph = first[0]
		else:
			glyph = "✨"
	var l := Label.new()
	l.text = glyph
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 46)
	l.custom_minimum_size = Vector2(64, 64)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 应用购买的商品 (team-buff 全队 / single-buff 选最低血友(敌) / 装备 装最低血友)
# 野生敌方 AI 自动购物 (1:1 PoC aiAutoShop:8201): planAiShop 纯决策 → 副作用施给右队。
#   深海/Boss/非野生 no-op (enemy_coins 也只在野生模式攒)。装备直接装右队最低血龟(Godot 无 bench)。
func _ai_auto_shop(shop_index: int) -> void:
	if not GameState.is_wild_enemy_mode() or GameState.enemy_coins <= 0 or finished:
		return
	var right_team: Array = []
	for f in fighters:
		if f.get("side", "") == "right" and f.get("alive", false) and not f.get("_isSummon", false):
			right_team.append(f)
	if right_team.is_empty():
		return
	var plan: Dictionary = ShopData.plan_ai_shop(GameState.enemy_coins, shop_index)
	GameState.enemy_coins = int(plan.get("coins_left", 0))
	var buys: Array = plan.get("buys", [])
	for slot in buys:
		if slot.has("buff"):
			var buff: Dictionary = slot["buff"]
			if buff.get("kind", "") == "team":
				ShopData.apply_team_buff(buff, right_team)
			else:
				var pool: Array = right_team
				if buff.get("wantsEnemy", false):   # 单体标记型 → 我方(左)随机一只
					pool = []
					for f in fighters:
						if f.get("side", "") == "left" and f.get("alive", false):
							pool.append(f)
				if not pool.is_empty():
					ShopData.apply_single_buff(buff, pool[randi() % pool.size()])
		elif slot.has("equipId"):
			right_team.sort_custom(func(a, b): return int(a.get("hp", 0)) < int(b.get("hp", 0)))
			var tgt: Dictionary = right_team[0]
			EquipmentRuntime.on_attach(tgt, slot["equipId"])
			if not tgt.has("_equipped_ids"): tgt["_equipped_ids"] = []
			(tgt["_equipped_ids"] as Array).append(slot["equipId"])
			StatsRecalc.snapshot_base(tgt); StatsRecalc.recalc(tgt, right_team)
	if not buys.is_empty():
		battle_log.append_text("[color=#ff9d9d]🛒 敌方购入 %d 件 (花 %d, 余 %d)[/color]\n" % [buys.size(), int(plan.get("spent", 0)), GameState.enemy_coins])
		_refresh_all_slots()


func _shop_apply(it: Dictionary) -> void:
	var allies: Array = []
	for f in fighters:
		if f.get("side", "") == "left" and f.get("alive", false) and not f.get("_isSummon", false):
			allies.append(f)
	if it.has("buff"):
		var buff: Dictionary = it["buff"]
		if buff["kind"] == "team":
			ShopData.apply_team_buff(buff, allies)
		else:
			# 单体增益: 1:1 PoC buySlot (ShopOverlay.ts:420-431) → 进装备席, 玩家拖到龟(wantsEnemy 拖到敌)身上才用。
			var bench_id := "%s#%d" % [str(buff.get("id", "buff")), _buff_bench_seq]
			_buff_bench_seq += 1
			_bench_buff_items[bench_id] = buff
			bench_inventory.append(bench_id)
			_rebuild_bench_rail()
	elif it.has("equipId"):
		# 1:1 PoC buySlot (ShopOverlay.ts:389-398): 买的装备【进装备席】, 玩家拖到龟身上才装 (不自动装最低血友)
		bench_inventory.append(str(it["equipId"]))
		_rebuild_bench_rail()
		# 成就: 战中买装备 (Godot 模型 equipId 恒非消耗品 → 必触发; 消耗品走 buff 分支). PoC onEquipBought
		AchievementTracker.on_equip_bought()
	_refresh_all_slots()


func _refresh_all_slots() -> void:
	for i in range(mini(fighters.size(), slot_nodes.size())):
		_refresh_slot(i)


# 每龟自己回合起手 (PoC processTurnBeginPassives:5236): buff duration 唯一递减点
func _actor_turn_begin(idx: int) -> void:
	var f: Dictionary = fighters[idx]
	if not f.get("alive", false):
		return
	Buffs.reset_per_turn_flags(f)
	f["_shieldOnHitUsedTurn"] = false   # shieldOnHit 每回合一次
	f["_multiBonus"] = 0                 # 赌徒连击加成 (gamblerBet 当回合设)
	f["_dmgBonusThisTurnPct"] = 0        # 放大器/FPGA 本回合增伤 (每回合重置, 装备 onTurnBegin 再设)
	StatsRecalc.tick_buffs_duration(f)   # buff duration 唯一递减点 (PoC 5246, 别处不再减)
	# 闪电涌动倒计时: 在 turn-begin 减 (1:1 PoC BattleScene.ts:5267-5274; 原在 side_end 减 → 与side-end zap加成窗口差1)
	if int(f.get("_lightningSurgeTurns", 0)) > 0:
		f["_lightningSurgeTurns"] = int(f["_lightningSurgeTurns"]) - 1
	# recalc 只对同侧存活 (chiWave/synergy 需同侧 allies)
	var allies: Array = []
	for a in fighters:
		if a.get("side", "") == f.get("side", "") and a.get("alive", false):
			allies.append(a)
	StatsRecalc.recalc(f, allies)
	# recalc 后叠 HP-scaling 被动 (不写 baseAtk; 每回合按当前血重算)
	var tbp = f.get("passive", null)
	if tbp is Dictionary and f.get("maxHp", 0) > 0:
		var lost_pct: float = maxf(0.0, 1.0 - float(f.get("hp", 0)) / float(f.get("maxHp", 1))) * 100.0
		match tbp.get("type", ""):
			"undeadRage":  # 无头龟: 每损1%血 +atkPerLostPct% ATK (cap atkMaxBonus)
				var bonus_pct: float = minf(tbp.get("atkMaxBonus", 100), lost_pct * tbp.get("atkPerLostPct", 1))
				f["atk"] = f.get("atk", 0) + roundi(f.get("baseAtk", 0) * bonus_pct / 100.0)
			"gamblerBlood":  # 骰子龟: 失血→暴击 (损maxCritAtLoss%血 →+maxCritGain%暴击)
				var bonus_crit: float = minf(tbp.get("maxCritGain", 50), lost_pct / maxf(1.0, tbp.get("maxCritAtLoss", 30)) * tbp.get("maxCritGain", 50)) / 100.0
				f["crit"] = f.get("crit", 0.0) + bonus_crit
	# 无头龟亡灵锁血倒计时 (每回合 -1, 归 0 解锁)
	if int(f.get("_undeadLockTurns", 0)) > 0:
		f["_undeadLockTurns"] = int(f["_undeadLockTurns"]) - 1
	# 招财龟聚宝盆: 技能金币 _goldCoins +3~8 (财神技能伤害资源, PoC :7948) + 商店钱包 +2 (PoC :5290)
	if tbp is Dictionary and tbp.get("type", "") == "fortuneGold":
		f["_goldCoins"] = int(f.get("_goldCoins", 0)) + 3 + randi() % 6
		GameState.grant_wealth_coin(f.get("side", "left"), 2)
	# 财富羁绊每回合 +N 商店钱包 (1:1 PoC :5301-5308, 是 this.coins 不是 _goldCoins 技能资源)
	if GameState.mode != "duallane" and int(f.get("_synergyWealthCoinPerTurn", 0)) > 0:
		GameState.grant_wealth_coin(f.get("side", "left"), int(f.get("_synergyWealthCoinPerTurn", 0)))
	# 回合起手被动 (PoC applyRoundStartPassive + bambooCharge 计数; 眩晕也不漏 → 在 stun 判定前)
	_apply_round_start_passive(idx)
	_fire_turn_begin_equip_for(idx)   # 装备 onTurnBegin (哑铃 +2 ATK 等), 仅此龟
	await _fire_p2_turn_begin(idx)    # 二阶段装备 onTurnBegin (锈蚀短剑劈砍), 仅此龟
	_sync_stun_overhead(idx)   # buff 已 tick: stun 自然到期 → 撤头顶星星 (仍眩晕则 _do_stun_skip 出手时撤)
	# 黑洞 flag 跟随 buff 存亡 (PoC updateBlackholeVisuals 每帧同步; 这里每 turn-begin 全场同步一次)
	for ff in fighters:
		ff["_isInBlackhole"] = Buffs.has(ff, "blackhole")
	await _process_lava_rage(idx)      # 熔岩龟: 怒气满→变身 / 已变身→倒计时 (PoC processLavaRage)


## 二阶段装备 onTurnBegin (001 锈蚀短剑劈砍): 携带者回合开始触发, 显示返回效果 (mirror side-end 显示)。
func _fire_p2_turn_begin(idx: int) -> void:
	if idx < 0 or idx >= fighters.size():
		return
	var f: Dictionary = fighters[idx]
	if not f.get("alive", false):
		return
	# 法器·法力: 回合开始每件法器 +25 法力 (≠龟能; 在 on_turn_begin 前加, 让 023 满法力判定看到本回合增量)。
	Phase2EquipRuntime.staff_round_begin(f)
	if f.get("_staff_mana") is Dictionary and not (f["_staff_mana"] as Dictionary).is_empty():
		_refresh_staff_mana_for(f)
	# 食物[增益]每回合成长: 携带食物者每件食物 → 自身+相邻槽 永久 +8/20 maxHp (累积, 同时回等量当前血)。
	if int(f.get("_foodRoundGrow", 0)) > 0:
		var grow: int = int(f["_foodRoundGrow"]) * Phase2Types.count_type(f, "食物")
		if grow > 0:
			var food_targets: Array = [f]
			food_targets.append_array(SlotHelpers.adjacent_fighters(fighters, f))
			for ft in food_targets:
				if ft is Dictionary and ft.get("alive", false):
					ft["maxHp"] = int(ft.get("maxHp", 0)) + grow
					ft["hp"] = int(ft.get("hp", 0)) + grow
	for p2 in f.get("_p2_equips", []):
		var fx: Array = Phase2EquipRuntime.on_turn_begin(f, str(p2["id"]), int(p2["star"]), fighters)
		# 龙蛋 024 火柱横扫: fx 含 firesweep VFX 标记 + 该列(友/敌)各 effect。火接触各目标才掉血/盾/魔法 →
		#   按目标 x 沿扫向(携带者x→列敌x) 错峰盖 delay (~0~0.6s), 沿扫顺序逐个显 (同海浪思路, 数值不动, 只改显示时机)。
		var fire_from_x: float = 0.0
		var fire_to_x: float = 0.0
		var has_firesweep := false
		for e in fx:
			if e is Dictionary and str(e.get("vfx", "")) == "firesweep":
				var ff_idx: int = int(e.get("vfx_from", -1))
				var ft_idx: int = int(e.get("target_idx", -1))
				if ff_idx >= 0 and ff_idx < slot_nodes.size() and ft_idx >= 0 and ft_idx < slot_nodes.size():
					fire_from_x = float(slot_nodes[ff_idx].get_meta("home_pos", slot_nodes[ff_idx].position).x)
					fire_to_x = float(slot_nodes[ft_idx].get_meta("home_pos", slot_nodes[ft_idx].position).x)
					has_firesweep = true
				break
		if has_firesweep:
			# 各 effect 按其目标 x 在扫向(from_x→to_x)上的比例 → 到达时刻 (clamp 0~0.6s); firesweep 标记本身固定 0 (扫起手即放)。
			for e in fx:
				if not (e is Dictionary):
					continue
				if str(e.get("vfx", "")) == "firesweep":
					e["_fire_delay"] = 0.0
					continue
				var fe_ti: int = int(e.get("target_idx", -1))
				if fe_ti >= 0 and fe_ti < slot_nodes.size():
					var fe_x: float = float(slot_nodes[fe_ti].get_meta("home_pos", slot_nodes[fe_ti].position).x)
					e["_fire_delay"] = wave_arrival_delay_at(fe_x, fire_from_x, fire_to_x, FIRE_SWEEP_DUR)
				else:
					e["_fire_delay"] = 0.0
			# 稳定按到达时刻排序 → 顺序循环增量等待才单调 (后到的早显被 clamp 成立即, 同海浪)
			fx.sort_custom(func(a, b): return float((a as Dictionary).get("_fire_delay", 0.0)) < float((b as Dictionary).get("_fire_delay", 0.0)))
		var fire_elapsed: float = 0.0   # 火柱路径: 已等待的累计墙钟时间 (把 effect 绝对到达时刻转成顺序循环的增量等待)
		for e in fx:
			var ti: int = int(e.get("target_idx", -1))
			if ti < 0 or ti >= slot_nodes.size():
				continue
			if fighters[ti].get("_deathVfxDone", false):   # 目标已死透 → 跳过(死龟身上不飘伤害字/不重触发死亡演出, 修残留76×)
				continue
			# 火柱横扫: _fire_delay 是【绝对】到达时刻 → 顺序循环里减去已等待的, 只补还差的增量, 让每段落在火头真到达的墙钟点
			if has_firesweep:
				var fd: float = maxf(0.0, float(e.get("_fire_delay", 0.0)) - fire_elapsed)
				if fd > 0.0:
					await get_tree().create_timer(fd).timeout
					fire_elapsed += fd
			# 全kind渲染 (1:1 on_side_end管线): 原只渲染damage → 回合起手的回血/护盾(012/016/018/019/021/036/042)漏飘字+漏统计
			var vfx_tb: String = str(e.get("vfx", ""))
			if vfx_tb == "firesweep":
				# 龙蛋火柱横扫: 从携带者扫向该列敌 (纯VFX标记, 不飘字) — 1:1 PoC spawnFireSweep
				_play_fire_sweep(int(e.get("vfx_from", -1)), ti)
				continue
			if vfx_tb == "slash":
				# 剑系斩击弧 (001锈蚀短剑 回合起手劈砍): 目标处月牙刃光, 方向=携带者→目标 (本身伤害effect, 续飘字)
				_play_slash_at(ti, Color(str(e.get("vfx_color", "#e8eef5"))), int(e.get("vfx_from", -1)), float(e.get("vfx_scale", 1.0)))
			elif vfx_tb == "shieldlink":
				# 守护贝母 021: 携带者→连接友军 青蓝能量链 + 该友军盾光 (本身是 shield effect, 续飘字)
				_play_link_chain(int(e.get("vfx_from", -1)), ti)
				_play_shield_glow(ti)
			elif vfx_tb != "":
				_play_equip_vfx(vfx_tb, ti)
			var kind_tb: String = str(e.get("kind", "damage"))
			if kind_tb == "passive":
				# 纯标记/增益 (038信号放大器 +增伤% / 040FPGA 抽中等): 飘绿字, 不走伤害飘字
				_spawn_passive_text(ti, str(e.get("label", "")), str(e.get("color", "")))
				_refresh_slot(ti)
				continue
			_spawn_float_text(ti, e.get("value", 0), kind_tb, str(e.get("dmg_type", "physical")), bool(e.get("is_crit", false)))
			if kind_tb == "damage":
				_flash_hit(ti)
				battle_stats.record_damage(f, fighters[ti], e.get("value", 0), _stat_type(str(e.get("dmg_type", "physical"))))
			elif kind_tb == "heal":
				battle_stats.record_heal(f, fighters[ti], int(e.get("value", 0)))
			_refresh_slot(ti)
			if not fighters[ti].get("alive", false) and kind_tb == "damage":
				await _play_death(ti)
		if not fx.is_empty():
			await get_tree().create_timer(0.2).timeout


# 回合起手被动 (PoC applyRoundStartPassive:5756 + processTurnBeginPassives bambooCharge:5329)
# 在该龟 turn-begin 调一次 (眩晕也照跑). candySteal / auraAwaken觉醒+储能盾衰减 / rainbowPrism / bambooCharge计数.
## 雷暴后续伤害 (1:1 PoC processThunderstormTick): thunder 事件标记 _thunderstormTurns 后, 之后每回合
##   随机一名活单位(非蛋/非已死透) 40 真伤, 全体计数 -1 归 0 止。原只 set 标记从不读 = 雷暴只打触发当回合一下。
func _thunderstorm_tick() -> void:
	var active := false
	for f in fighters:
		if int(f.get("_thunderstormTurns", 0)) > 0:
			active = true
			break
	if not active:
		return
	var pool: Array = []
	for i in range(fighters.size()):
		if fighters[i].get("alive", false) and not fighters[i].get("_isEgg", false) and not fighters[i].get("_deathVfxDone", false):
			pool.append(i)
	if not pool.is_empty():
		var ti: int = pool[randi() % pool.size()]
		var hp0: int = int(fighters[ti].get("hp", 0))
		fighters[ti]["hp"] = maxi(0, hp0 - 40)
		if int(fighters[ti]["hp"]) == 0:
			fighters[ti]["alive"] = false
		var dealt: int = hp0 - int(fighters[ti]["hp"])
		if dealt > 0:
			if OS.has_environment("DUALLANE_SMOKE"):
				print("[SMOKE] ⚡雷暴后续tick → %s 受 %d真伤" % [fighters[ti].get("name", "?"), dealt])
			battle_log.append_text("[color=#ffd700]⚡ 雷暴 → %s 受 %d 真伤[/color]\n" % [fighters[ti].get("name", "?"), dealt])
			_spawn_float_text(ti, dealt, "damage", "true", false)
			_refresh_slot(ti)
		if not fighters[ti].get("alive", false) and not fighters[ti].get("_deathVfxDone", false):
			await _play_death(ti)
	for f in fighters:
		if int(f.get("_thunderstormTurns", 0)) > 0:
			f["_thunderstormTurns"] = int(f["_thunderstormTurns"]) - 1
	if not auto_play_debug:
		await get_tree().create_timer(0.4).timeout


## 局中环境事件 (第3/6/9/12回合开始, 1:1 PoC events.ts + BattleScene:1780). [Phase1: 仅env事件; 中立生物spawn=Phase2]
func _roll_battle_event(t: int) -> void:
	if t != 3 and t != 6 and t != 9 and t != 12:
		return
	var ev_id: String = Events.roll_event_for_turn(t, _events_fired)
	if ev_id == "":
		return
	_events_fired.append(ev_id)
	var meta: Dictionary = Events.ENV_EVENT_META.get(ev_id, {})
	var hp_before: Array = []
	for f in fighters:
		hp_before.append(int(f.get("hp", 0)))
	Events.apply_env_event(ev_id, fighters)
	battle_log.append_text("[color=#ffd86b]%s %s — %s[/color]\n" % [meta.get("emoji", "✦"), meta.get("name", ev_id), meta.get("desc", "")])
	_flash_event_entrance()   # 1:1 PoC flashEventEntrance: 事件来袭 暗底脉冲+橙闪+轻震 (在横幅前)
	_show_center_banner("%s %s" % [meta.get("emoji", ""), meta.get("name", ev_id)], str(meta.get("desc", "")))
	if ev_id == "treasure-rain":
		if GameState.mode == "duallane":
			pass   # V2-TODO 阶段2/6: 宝藏雨发币已删 (局内无经济); 事件奖励待重定
		else:
			GameState.battle_coins += 30
			if GameState.is_wild_enemy_mode():
				GameState.enemy_coins += 30
			_refresh_battle_hud()
	var dt: String = "magic" if ev_id == "meteor" else "true"
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		var dealt: int = hp_before[i] - int(f.get("hp", 0))
		if dealt > 0:
			_spawn_float_text(i, dealt, "damage", dt, false)
			_refresh_slot(i)
		elif ev_id == "tide" or ev_id == "fog":
			_refresh_slot(i)
		if not f.get("alive", false) and not f.get("_deathVfxDone", false):   # 仅对【首次】死的龟放演出 (原 modulate.a 守卫失效: 死亡演出改动 avatar 后 node.a 恒1)
			await _play_death(i)
	if not auto_play_debug:
		await get_tree().create_timer(0.9).timeout


func _apply_round_start_passive(idx: int) -> void:
	var f: Dictionary = fighters[idx]
	if not f.get("alive", false):
		return
	var p = f.get("passive", null)
	if not (p is Dictionary):
		return
	var pt: String = p.get("type", "")
	# 磐石之躯 stoneWall: 每回合永久 +护甲 (maxCap/capTurns 累加, 上限 initDef×maxDefInitPct%) (1:1 PoC applyStoneWallGain ts:5215). 原Godot只有HUD条无累加=条恒0.
	if pt == "stoneWall":
		var s_sg: int = int(f.get("_stoneDefGained", 0))
		var s_init: int = int(f.get("_initDef", f.get("baseDef", 0)))
		var s_cap: int = roundi(float(s_init) * float(p.get("maxDefInitPct", 100)) / 100.0)
		if s_sg < s_cap:
			var s_frac: float = float(f.get("_stoneDefFraction", 0.0)) + float(s_cap) / float(p.get("capTurns", 6))
			f["_stoneDefFraction"] = s_frac
			var s_tgt: int = mini(s_cap, roundi(s_frac))
			var s_gain: int = s_tgt - s_sg
			if s_gain > 0:
				f["baseDef"] = int(f.get("baseDef", 0)) + s_gain
				f["def"] = f["baseDef"]
				f["_stoneDefGained"] = s_tgt
				battle_log.append_text("[color=#c8a050]🪨 %s 坚壁 +%d 护甲 (累计 +%d/%d)[/color]
" % [f.get("name", "?"), s_gain, s_tgt, s_cap])
		return

	# 龟壳 气场觉醒: 第 N 回合一次性永久全属性+ (PoC 5763-5788); 储能盾每回合衰减 (PoC 2308-2314)
	if pt == "auraAwaken":
		var aturn: int = int(f.get("_auraTurn", 0)) + 1
		f["_auraTurn"] = aturn
		var awaken_turn: int = p.get("awakenTurn", 4)
		var enhanced_turn: int = p.get("enhancedAwakenTurn", 8)
		var do_enhanced := false
		for ps in f.get("_passiveSkills", []):
			if ps is Dictionary and ps.get("type", "") == "shellEnhanceAwaken":
				do_enhanced = true
		if aturn == awaken_turn or (aturn == enhanced_turn and do_enhanced):
			f["baseAtk"] = roundi(f.get("baseAtk", 0) * (1.0 + p.get("atkPct", 12) / 100.0)); f["atk"] = f["baseAtk"]
			f["baseDef"] = roundi(f.get("baseDef", 0) * (1.0 + p.get("defPct", 12) / 100.0)); f["def"] = f["baseDef"]
			f["baseMr"] = roundi(int(f.get("baseMr", f.get("def", 0))) * (1.0 + p.get("mrPct", 12) / 100.0)); f["mr"] = f["baseMr"]
			var new_max: int = roundi(f.get("maxHp", 0) * (1.0 + p.get("hpPct", 12) / 100.0))
			f["hp"] = int(f.get("hp", 0)) + (new_max - int(f.get("maxHp", 0))); f["maxHp"] = new_max
			f["lifestealPct"] = f.get("lifestealPct", 0.0) + p.get("lifestealPct", 12) / 100.0
			f["_baseLifesteal"] = f.get("_baseLifesteal", 0.0) + p.get("lifestealPct", 12) / 100.0
			f["reflectPct"] = f.get("reflectPct", 0.0) + p.get("reflectPct", 12)   # 整数百分比 (跟 013/015 apply_stats 口径对齐; 消费端 :5544 再 /100 才对)
			f["crit"] = f.get("crit", 0.0) + p.get("critGain", 0.25); f["_baseCrit"] = f.get("_baseCrit", 0.0) + p.get("critGain", 0.25)
			# 1:1 PoC doAwaken(BattleScene.ts:5785): 只 battleLog 不飘字 (原 Godot 飘"✨气场觉醒"=自创且漏log)
			battle_log.append_text("[color=#c77dff]✨ %s 气场觉醒! +%d%% 全属性 + %d%% 暴击[/color]\n" % [f.get("name", "?"), int(p.get("atkPct", 12)), int(p.get("critGain", 0.25) * 100.0)])
		# 储能盾衰减: gain 回合后, 每回合一次 (第1次减半, 第2次清零)
		if int(f.get("_auraShield", 0)) > 0 and int(f.get("_auraShieldGainTurn", 0)) > 0 \
				and turn > int(f.get("_auraShieldGainTurn", 0)) and int(f.get("_auraShieldLastDecayTurn", 0)) < turn:
			var dc: int = int(f.get("_auraShieldDecayCount", 0)) + 1
			f["_auraShieldDecayCount"] = dc
			f["_auraShieldLastDecayTurn"] = turn
			f["_auraShield"] = roundi(int(f.get("_auraShield", 0)) / 2.0) if dc == 1 else 0

	# 糖果 甜蜜掠夺: 第 stealTurn 回合对随机敌真伤偷血+偷 maxHp (PoC 5804-5824)
	if pt == "candySteal" and turn == int(p.get("stealTurn", 3)):
		var enemies := _alive_enemies_of(f)
		if not enemies.is_empty():
			var tgt: Dictionary = enemies[randi() % enemies.size()]
			var steal: int = roundi(tgt.get("maxHp", 0) * p.get("stealPct", 25) / 100.0)
			tgt["maxHp"] = maxi(1, int(tgt.get("maxHp", 0)) - steal)
			tgt["hp"] = maxi(1, mini(int(tgt.get("hp", 0)) - steal, int(tgt["maxHp"])))
			f["maxHp"] = int(f.get("maxHp", 0)) + steal; f["hp"] = int(f.get("hp", 0)) + steal
			var tidx: int = fighters.find(tgt)
			_spawn_float_text(tidx, steal, "damage", "true", false)
			_refresh_slot(tidx); _refresh_slot(idx)
			battle_stats.record_damage(f, tgt, steal, "tru")

	# 水晶 不朽(B4): 存活到第10回合 +5000HP/+400ATK 一次性 (1:1 PoC BattleScene.ts:5353)
	if f.get("_crystalImmortal", false) and turn >= 10 and not f.get("_crystalImmortalTriggered", false):
		f["_crystalImmortalTriggered"] = true
		f["maxHp"] = int(f.get("maxHp", 0)) + 5000
		f["hp"] = int(f.get("hp", 0)) + 5000
		f["baseAtk"] = int(f.get("baseAtk", 0)) + 400; f["atk"] = f["baseAtk"]
		_spawn_passive_text(idx, "不朽! +5000HP +400ATK")   # 1:1 PoC BattleScene.ts:5361 (原多了自创"💎"前缀)
		_refresh_slot(idx)

	# 赌神 命运之轮(B2): 每回合抽花色永久加属性 (1:1 PoC BattleScene.ts:5827-5853)
	if f.get("_fateWheel", false):
		var fc: Dictionary = f.get("_fateWheelCounts", {"spade": 0, "heart": 0, "diamond": 0, "club": 0})
		match randi() % 4:
			0:
				fc["spade"] = int(fc.get("spade", 0)) + 1
				f["baseAtk"] = int(f.get("baseAtk", 0)) + 5; f["atk"] = int(f.get("atk", 0)) + 5
				f["maxHp"] = int(f.get("maxHp", 0)) + 30; f["hp"] = int(f.get("hp", 0)) + 30
				_spawn_passive_text(idx, "♠ +5攻+30HP")
			1:
				fc["heart"] = int(fc.get("heart", 0)) + 1
				f["baseDef"] = int(f.get("baseDef", 0)) + 2; f["def"] = int(f.get("def", 0)) + 2
				f["baseMr"] = int(f.get("baseMr", f.get("baseDef", 0))) + 2; f["mr"] = int(f.get("mr", 0)) + 2
				_spawn_passive_text(idx, "♥ +2甲+2魔抗")
			2:
				fc["diamond"] = int(fc.get("diamond", 0)) + 1
				f["crit"] = minf(1.0, f.get("crit", 0.0) + 0.08); f["_baseCrit"] = f.get("_baseCrit", 0.0) + 0.08
				f["armorPen"] = int(f.get("armorPen", 0)) + 2; f["_baseArmorPen"] = int(f.get("_baseArmorPen", f.get("armorPen", 0))) + 2
				_spawn_passive_text(idx, "♦ +8%暴击+2穿甲")
			3:
				fc["club"] = int(fc.get("club", 0)) + 1
				f["lifestealPct"] = f.get("lifestealPct", 0.0) + 0.04; f["_baseLifesteal"] = f.get("_baseLifesteal", 0.0) + 0.04
				_spawn_passive_text(idx, "♣ +4%吸血")
		f["_fateWheelCounts"] = fc
		_refresh_slot(idx)

	# 彩虹 棱镜: 每回合随机色光 → 全队增益 / 随机敌 debuff (PoC applyRainbowPrism:5858)
	if pt == "rainbowPrism":
		_apply_rainbow_prism(idx)

	# 竹叶 生长: 每 2 次 turn-begin 充能, 下次技能后追加强化攻击 (PoC 5329-5342)
	if pt == "bambooCharge":
		f["_bambooFired"] = false
		if not f.get("_bambooCharged", false):
			var cnt: int = int(f.get("_bambooCounter", 0)) + 1
			if cnt >= 2:
				f["_bambooCharged"] = true; f["_bambooCounter"] = 0
				_spawn_passive_text(idx, "🎋充能!", "#10b981")   # 1:1 PoC 充能就绪绿字
			else:
				f["_bambooCounter"] = cnt


# 棱镜随机色光 (PoC applyRainbowPrism:5858 — 1:1 7 色 turn.js:397-444)
func _apply_rainbow_prism(idx: int) -> void:
	var f: Dictionary = fighters[idx]
	var p = f.get("passive", null)
	if not (p is Dictionary):
		return
	var allies := _alive_allies_of(f)
	var enemies := _alive_enemies_of(f)
	var atk_pct: float = p.get("atkPct", 12)
	var def_pct: float = p.get("defPct", 12)
	var heal_pct: float = p.get("healPct", 5)
	var enhanced: bool = f.get("_enhancedPrism", false)
	var base_pool: Array = [0, 1] if turn <= 1 else [0, 1, 2]
	var picks: Array = [base_pool[randi() % base_pool.size()]]
	if enhanced:
		picks.append([3, 4, 5, 6][randi() % 4])
	f["_prismColor"] = picks[0]
	f["_prismColors"] = picks.duplicate()
	var names := ["🔴", "🔵", "🟢", "🟠", "🟡", "🩵", "🟣"]
	for color in picks:
		match color:
			0:  # 红: 全队 atk +%
				for a in allies:
					var g: int = roundi(a.get("baseAtk", 0) * atk_pct / 100.0)
					(a["buffs"] as Array).append({"type": "atkUp", "value": g, "duration": 2})
					a["atk"] = int(a.get("atk", 0)) + g
			1:  # 蓝: 全队 def/mr +%
				for a in allies:
					var dg: int = roundi(a.get("baseDef", 0) * def_pct / 100.0)
					var mg: int = roundi(int(a.get("baseMr", a.get("baseDef", 0))) * def_pct / 100.0)
					(a["buffs"] as Array).append({"type": "defUp", "value": dg, "duration": 2})
					(a["buffs"] as Array).append({"type": "mrUp", "value": mg, "duration": 2})
					a["def"] = int(a.get("def", 0)) + dg; a["mr"] = int(a.get("mr", 0)) + mg
			2:  # 绿: 全队回 %
				for a in allies:
					var h: int = roundi(a.get("maxHp", 0) * heal_pct / 100.0)
					a["hp"] = mini(int(a.get("maxHp", 0)), int(a.get("hp", 0)) + h)
					_refresh_slot(fighters.find(a))
			3:  # 橙: 生命偷取 1 回合
				for a in allies:
					(a["buffs"] as Array).append({"type": "lifesteal", "value": 10, "duration": 2})
			4:  # 黄: 灼烧随机敌
				if not enemies.is_empty():
					Dot.apply_stacks(enemies[randi() % enemies.size()], "burn", Dot.default_burn_stacks(f))
			5:  # 青: 冰寒
				if not enemies.is_empty():
					(enemies[randi() % enemies.size()]["buffs"] as Array).append({"type": "chilled", "value": 1, "duration": 2})
			6:  # 紫: 诅咒 (maxHp×5%, 3 回合)
				if not enemies.is_empty():
					var ce: Dictionary = enemies[randi() % enemies.size()]
					(ce["buffs"] as Array).append({"type": "curse", "value": roundi(ce.get("maxHp", 0) * 0.05), "duration": 3, "_src": f})
	var label := ""
	for c in picks:
		label += names[c]
	_spawn_passive_text(idx, label)


# 竹叶龟充能追击 (PoC fireBambooChargeIfReady:3244): 持 _bambooCharged 时消费, 追加强化魔法攻击.
## 竹叶充能 生命球: 绿球从 target 抛物线飞回 turtle, 落点爆 (1:1 PoC spawnBambooOrb BattleScene.ts:3325-3360). fire-and-forget.
##   坐标/帧/落点burst 走 _play_vfx 同款约定(slots_root + home_pos); 尺寸48px/burst缩放需F5微调.
func _spawn_bamboo_orb(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	var orb_path := "res://assets/sprites/vfx/bamboo-charge-orb.png"
	if not ResourceLoader.exists(orb_path):
		return
	var p_from: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -20)   # PoC sy=fromV.homeY-20 (头顶起落, 非身心)
	var p_to: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -20)       # PoC ey=toV.homeY-20
	var tex: Texture2D = load(orb_path)
	var fw: int = maxi(1, tex.get_height())   # 方形帧 sheet → 帧宽=高
	var nframes: int = maxi(1, int(tex.get_width() / fw))
	var orb := Sprite2D.new()
	orb.texture = tex
	orb.hframes = nframes
	orb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	orb.z_index = 601   # 竹叶生命球抛物飞行高过龟身(最深 ~497): 原 210 被龟立绘遮死 (trail dot 600 在其下)
	orb.position = p_from
	var oscale: float = 48.0 / float(fw)   # PoC 48px orb
	orb.scale = Vector2(oscale, oscale)
	slots_root.add_child(orb)
	var arc_h: float = maxf(60.0, p_from.distance_to(p_to) * 0.4)   # PoC arcH=max(60, dist×0.4)
	var trail_seg := [0]   # 捕获可变: 拖尾节流段
	var tw := create_tween()
	tw.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(orb):
				return
			var base := p_from.lerp(p_to, t)
			orb.position = Vector2(base.x, base.y - arc_h * 4.0 * t * (1.0 - t))   # 抛物线 (同 PoC -(-4·arcH·e·(e-1)))
			if nframes > 1:
				orb.frame = int(t * float(nframes) * 2.0) % nframes
			if t > 0.05 and t < 0.93:   # 绿拖尾 (PoC 0.05<e<0.93 每30ms 撒一绿圆) — 按进度段节流~19个
				var seg := int(t / 0.046)
				if seg > trail_seg[0]:
					trail_seg[0] = seg
					_bamboo_trail_dot(orb.position),
		0.0, 1.0, 0.65)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)   # PoC Sine.easeInOut 650ms
	tw.tween_callback(func() -> void:
		if is_instance_valid(orb):
			orb.queue_free()
		# 落点爆裂 76px (PoC setDisplaySize(76,76))
		var bpath := "res://assets/sprites/vfx/bamboo-charge-burst.png"
		if ResourceLoader.exists(bpath):
			_play_vfx("bamboo-charge-burst", p_to, 76.0 / float(maxi(1, (load(bpath) as Texture2D).get_height()))))


## 竹叶生命球 绿拖尾圆点 (1:1 PoC trail: circle r5 #7dffb3 α.7, 420ms 淡出缩0.3 cubic.out)
func _bamboo_trail_dot(pos: Vector2) -> void:
	var dot := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in range(10):
		var ang := TAU * float(k) / 10.0
		pts.append(Vector2(cos(ang), sin(ang)) * 5.0)   # PoC circle r5
	dot.polygon = pts
	dot.color = Color(125.0 / 255.0, 1.0, 179.0 / 255.0, 0.7)   # PoC 0x7dffb3 α0.7
	dot.position = pos
	dot.z_index = 600   # 略低于 orb(601), 同抬过龟身(最深 ~497): 原 209 被龟立绘遮死
	slots_root.add_child(dot)
	var dt := create_tween()
	dt.set_parallel(true)
	dt.tween_property(dot, "modulate:a", 0.0, 0.42).set_ease(Tween.EASE_OUT)   # PoC 420ms cubic.out
	dt.tween_property(dot, "scale", Vector2(0.3, 0.3), 0.42).set_ease(Tween.EASE_OUT)   # PoC scale→0.3
	dt.chain().tween_callback(dot.queue_free)


func _fire_bamboo_charge(actor_idx: int, skill_target_idx: int) -> void:
	var f: Dictionary = fighters[actor_idx]
	if not f.get("_bambooCharged", false) or f.get("_bambooFired", false):
		return
	var enemies := _alive_enemies_of(f)
	if enemies.is_empty():
		return
	# 追加攻击必打敌方: 技能目标若是有效存活敌方则用它, 否则最低 HP 敌方 (PoC 3250-3255)
	var tv: Dictionary = enemies[0]
	if skill_target_idx >= 0 and skill_target_idx < fighters.size():
		var stf: Dictionary = fighters[skill_target_idx]
		if stf.get("alive", false) and stf.get("side", "") != f.get("side", ""):
			tv = stf
		else:
			enemies.sort_custom(func(a, b): return int(a.get("hp", 0)) < int(b.get("hp", 0)))
			tv = enemies[0]
	else:
		enemies.sort_custom(func(a, b): return int(a.get("hp", 0)) < int(b.get("hp", 0)))
		tv = enemies[0]
	f["_bambooFired"] = true
	f["_bambooCharged"] = false
	var p = f.get("passive", null)
	if not (p is Dictionary):
		return
	var enh: bool = f.get("_bambooEnhanced", false)
	var atk_pct: float = 100.0 if enh else p.get("atkPct", 75)
	var self_hp_pct: float = 13.0 if enh else p.get("selfHpPct", 8)
	var heal_self_pct: float = 12.0 if enh else p.get("healSelfHpPct", 8)
	var hp_gain_pct: float = 105.0 if enh else p.get("hpGainAtkPct", 60)
	_spawn_passive_text(actor_idx, "🎋蓄力...", "#10b981")   # 1:1 PoC 蓄力绿字 #10b981
	await get_tree().create_timer(1.0).timeout   # 1:1 PoC 蓄力 windup 1000ms (BattleScene.ts:3271) — 原无暂停=瞬发无节奏
	# 魔法伤害 (PoC 3276-3290)
	var tidx: int = fighters.find(tv)
	var is_crit: bool = Damage.roll_crit(f.get("crit", 0.0))
	var crit_mult: float = Damage.calc_crit_mult(f) if is_crit else 1.0
	var raw: float = (f.get("atk", 0) * atk_pct / 100.0 + f.get("maxHp", 0) * self_hp_pct / 100.0) * crit_mult
	var final_dmg: int = Damage.calc_damage(f, tv, raw, "magic")
	var r: Dictionary = Damage.apply_raw_damage(tv, final_dmg, "magic")
	var shown: int = r["hpLoss"] + r["shieldAbs"]
	if shown > 0:
		_spawn_float_text(tidx, shown, "damage", "magic", is_crit)
		_refresh_slot(tidx)
		battle_stats.record_damage(f, tv, shown, "mag")
	# 充能追击也走 on-hit 链 (审判/反伤/墨迹/电击/吸血) — PoC 3285
	var bonus: Array = []
	_on_hit_chain(f, tv, final_dmg, "magic", actor_idx, tidx, bonus)
	for be in bonus:
		var bt: int = be.get("target_idx", -1)
		if bt >= 0 and be.get("kind", "") == "damage":
			_spawn_float_text(bt, be.get("value", 0), "damage", be.get("dmg_type", "magic"), false)
			_refresh_slot(bt)
	if not tv.get("alive", false):
		_award_and_record_kill(f, tv)
		await _play_death(tidx)
	# 生命球飞回 + 落点结算 (1:1 PoC spawnBambooOrb + await 650ms, BattleScene.ts:3293-3299) — 原瞬发无"吸血回流"节奏
	_spawn_bamboo_orb(tidx, actor_idx)
	await get_tree().create_timer(0.65).timeout
	# 回血 + 永久 +maxHp (PoC 3302-3319)
	var raw_heal: int = roundi(f.get("maxHp", 0) * heal_self_pct / 100.0)
	var heal_red: float = 0.0
	var hr = Buffs.find(f, "healReduce")
	if hr != null:
		heal_red = hr.get("value", 0)
	var heal_amt: int = roundi(raw_heal * (1.0 - heal_red / 100.0))
	var hp_gain: int = roundi(f.get("atk", 0) * hp_gain_pct / 100.0)
	var before: int = f.get("hp", 0)
	f["maxHp"] = int(f.get("maxHp", 0)) + hp_gain
	f["_bambooGainedHp"] = int(f.get("_bambooGainedHp", 0)) + hp_gain
	f["hp"] = mini(int(f["maxHp"]), before + Buffs.fatigue_amt(f, heal_amt) + hp_gain)
	var actual_heal: int = int(f["hp"]) - before
	if actual_heal > 0:
		battle_stats.record_heal(f, f, actual_heal)
		_spawn_passive_text(actor_idx, "+%d" % actual_heal, "#06d6a0")   # 1:1 PoC 回血绿 #06d6a0
	if hp_gain > 0:
		_spawn_passive_text(actor_idx, "+%d最大HP" % hp_gain, "#a0e8ff")   # 1:1 PoC 永久成长浅蓝 #a0e8ff (BattleScene.ts:3316) — 原缺=成长无反馈
	_refresh_slot(actor_idx)
	battle_log.append_text("  [color=#10b981]🎋 %s 竹编充能 → %s: %d 魔法%s 永久+%d最大HP[/color]\n" % [
		f.get("name", "?"), tv.get("name", "?"), shown, " 暴击!" if is_crit else "", hp_gain])


# 龟壳气场储能波击 (PoC processEnergyWave:7962): 每 energyReleaseTurn 回合, 持能者爆发全敌物理 + 自获气场盾.
func _process_energy_wave() -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("alive", false):
			continue
		var p = f.get("passive", null)
		if not (p is Dictionary) or p.get("type", "") != "auraAwaken" or not p.get("energyStore", false):
			continue
		var period: int = p.get("energyReleaseTurn", 4)
		if turn < period or turn % period != 0:
			continue
		var stored: int = int(f.get("_auraEnergy", 0))
		if stored <= 0:
			continue
		var lvl: int = maxi(1, int(f.get("_level", 1)))
		var per_lv: float = p.get("perLevelPct", 0.01)
		var dmg_pct: float = p.get("energyDmgPct", 0.4) + (lvl - 1) * per_lv
		var shield_pct: float = p.get("energyShieldPct", 0.8) + (lvl - 1) * per_lv
		var wave_dmg: int = maxi(1, roundi(stored * dmg_pct))
		for ev in _alive_enemies_of(f):
			var was_alive: bool = ev.get("alive", false)
			var r: Dictionary = Damage.apply_raw_damage(ev, wave_dmg, "physical")
			var shown: int = r["hpLoss"] + r["shieldAbs"]
			var ei: int = fighters.find(ev)
			if shown > 0:
				_spawn_float_text(ei, shown, "damage", "physical", false)
				_refresh_slot(ei)
				battle_stats.record_damage(f, ev, shown, "phy")
			if was_alive and not ev.get("alive", false):
				_award_and_record_kill(f, ev)
				await _play_death(ei)
		var shield_amt: int = roundi(stored * shield_pct)
		f["_auraShield"] = int(f.get("_auraShield", 0)) + shield_amt
		f["_auraShieldGainTurn"] = turn
		f["_auraShieldDecayCount"] = 0
		f["_auraEnergy"] = 0
		_spawn_passive_text(i, "+%d🛡" % shield_amt)
		battle_log.append_text("  [color=#ffd166]⚡ %s 储能波击! 全体 %d 物理 + %d 气场盾[/color]\n" % [f.get("name", "?"), wave_dmg, shield_amt])
		await get_tree().create_timer(0.3).timeout
		if finished:
			return


# 海盗龟开局轰击 (PoC battle-setup 1652): 每海盗对随机敌 maxHp×bombardPct% 真伤穿透. 战斗开始前调一次.
func _pirate_opening_barrage() -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("alive", false):
			continue
		var p = f.get("passive", null)
		if not (p is Dictionary) or p.get("type", "") != "pirateBarrage" or p.get("bombardPct", 0) <= 0:
			continue
		var enemies := _alive_enemies_of(f)
		if enemies.is_empty():
			continue
		var tgt: Dictionary = enemies[randi() % enemies.size()]
		var base_dmg: int = roundi(f.get("maxHp", 0) * p.get("bombardPct", 25) / 100.0)
		var was_alive: bool = tgt.get("alive", false)
		var r: Dictionary = Damage.apply_raw_damage(tgt, base_dmg, "true", true)
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		var tidx: int = fighters.find(tgt)
		if shown > 0:
			_spawn_float_text(tidx, shown, "damage", "true", false)
			_refresh_slot(tidx)
			battle_stats.record_damage(f, tgt, shown, "tru")
		if was_alive and not tgt.get("alive", false):
			_award_and_record_kill(f, tgt)
			await _play_death(tidx)
		battle_log.append_text("  [color=#ffb347]🏴 %s 掠夺 → %s %d 真实[/color]\n" % [f.get("name", "?"), tgt.get("name", "?"), shown])
		await get_tree().create_timer(0.2).timeout


# side-end: 对【对面】队伍结算 DoT (PoC processSideEnd:7251 — DoT 打对面是"我打完→敌方烧"的节拍)
func _side_end(ended_side: String) -> void:
	var opp := "right" if ended_side == "left" else "left"
	await _tick_dots_for_team(opp)
	await _tick_hots_for_team(ended_side)     # 本侧 HoT 持续回血 + bubbleStore被动回血 (1:1 PoC side-end own队 hot tick)
	_check_revives()                          # 凤凰涅槃 (DoT 致死也复活)
	await _check_summon_cascade()             # 主人阵亡的随从一同倒下
	_check_mech_transforms()                 # DoT/行动致死的赛博龟 → 机甲
	await _lightning_side_end(ended_side)     # 闪电风暴: 随机敌真伤 + 叠层
	await _cyber_side_end(ended_side)         # 浮游炮: 生成 + (turn>=2)开火
	await _armory_turret_fire(ended_side)     # 深海军械库[军火]: 炮台1 回合末沿列轰击+回血; 9档火控真伤波
	await _mech_side_end(ended_side)          # 机甲: 自动攻击最低血敌
	await _crystal_ball_side_end(ended_side)  # 水晶球: 本侧全行动后射魔光沿列 (crystalBall passive)
	# 缩头龟随从: 本侧每个随从自动行动一次 (PoC summonAutoAction) — 排训龟大师 (它走 _process_master_trainer)
	for i in range(fighters.size()):
		if fighters[i].get("side", "") == ended_side and fighters[i].get("_isSummon", false) and fighters[i].get("alive", false) \
				and not fighters[i].get("_isMasterTrainer", false) and not fighters[i].get("_isCrystalBall", false) \
				and not fighters[i].get("_isCandyBomb", false) and not fighters[i].get("_isPirateShip", false) \
				and not fighters[i].get("_isTentacle", false):   # 触手走 _process_tentacles 拍击, 不走通用随从 AI
			await _summon_act(i)
	await _check_summon_cascade()             # 上面致死后再补检
	_check_mech_transforms()                  # 上面致死的也补检
	# 熔岩龟二次检查: DoT 在回合外可能填满怒气, 行动入口已过 → side-end 再扫一遍 (PoC 7455-7463)
	for i in range(fighters.size()):
		if fighters[i].get("alive", false):
			await _process_lava_rage(i)
	await _fire_side_end_equipment(ended_side)   # 回合末装备 (蜡烛/哑铃/左轮/海浪)
	_check_revives()
	await _check_summon_cascade()
	await _process_master_trainer(ended_side)    # 训龟大师: 每回合放 1 能力 + 倒计时离场 (口哨召唤)


## 回合末装备效果 (PoC processSideEndEquipment): 本侧每龟每件装备调 on_side_end, 显示返回的效果
func _fire_side_end_equipment(ended_side: String) -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("side", "") != ended_side or not f.get("alive", false):
			continue
		for eq_id in f.get("_equipped_ids", []):
			var fx: Array = EquipmentRuntime.on_side_end(f, eq_id, fighters)
			# 海浪 e_wave 横扫 VFX: 一道浪扫过被扫行 (1:1 PoC launchWaveSweep vfx/skills.ts:324)
			if eq_id == "e_wave" and not fx.is_empty():
				var w_ti: int = int(fx[0].get("target_idx", -1))
				if w_ti >= 0 and w_ti < slot_nodes.size():
					_play_wave_sweep(float(slot_nodes[w_ti].get_meta("home_pos", slot_nodes[w_ti].position).y) - 40.0)
			for e in fx:
				var ti: int = e.get("target_idx", -1)
				if ti < 0 or ti >= slot_nodes.size():
					continue
				if fighters[ti].get("_deathVfxDone", false):   # 目标已死透 → 跳过(修死龟残留效果重触发/飘字)
					continue
				# 逐效果错峰 (1:1 PoC 每发/每段 sleep) + 装备 VFX
				var dly: float = float(e.get("delay", 0.0))
				if dly > 0.0:
					await get_tree().create_timer(dly).timeout
				var vfx_n: String = str(e.get("vfx", ""))
				if vfx_n == "projectile":
					# 装备弹道 (哑铃/飞镖/左轮子弹): 从携带者飞向目标 (fire-and-forget) — 1:1 PoC fireStraightProjectile
					var pf: int = int(e.get("vfx_from", -1))
					if pf >= 0:
						_fire_projectile(pf, ti, str(e.get("vfx_path", "")), float(e.get("vfx_size", 32.0)), float(e.get("vfx_dur", 0.36)))
						# 血跟子弹落地才掉: 等弹道飞行时长后再飘字/扣血显示 (数值已结算, 只推迟显示时机)
						if e.get("kind", "damage") == "damage":
							await get_tree().create_timer(float(e.get("vfx_dur", 0.36))).timeout
				elif vfx_n != "":
					_play_equip_vfx(vfx_n, ti)
				if e.get("kind", "") == "passive":
					_spawn_passive_text(ti, e.get("label", ""))
				elif e.get("kind", "") == "damage":
					# 伤害走显示调度队列 → 同目标多源(并段/DoT/装备)有序消费, 不抢血条; 统计仍立即记 (数值已结算).
					battle_stats.record_damage(f, fighters[ti], e.get("value", 0), _stat_type(e.get("dmg_type", "physical")))
					var _ev_fse: Dictionary = {"kind": "damage", "value": e.get("value", 0), "dmg_type": e.get("dmg_type", "physical"), "is_crit": false}
					if e.has("hp_after"):
						_ev_fse["hp_after"] = float(e["hp_after"])
						_ev_fse["shield_after"] = float(e.get("shield_after", -1.0))
					_enqueue_display(ti, _ev_fse)
					if not fighters[ti].get("alive", false):
						await _await_display_drained(ti)   # 死亡时机根治: 等致命掉血血条 step 显示完再播死亡
						await _play_death(ti)
				else:
					# heal 等其它 kind: 队列消费器只识 damage/dot → 直接飘字+刷血 (保留原路径).
					_spawn_float_text(ti, e.get("value", 0), e.get("kind", "damage"), e.get("dmg_type", "physical"), false, 0.0, not e.has("hp_after"))
					if e.has("hp_after"):
						_refresh_slot(ti, float(e["hp_after"]), float(e.get("shield_after", -1.0)))
					else:
						_refresh_slot(ti)
			if not fx.is_empty():
				await get_tree().create_timer(0.25).timeout
		# 二阶段装备 on_side_end (020哑铃/025雷鸣/037蜡烛/043海浪/052左轮) — 同侧回合末
		for p2 in f.get("_p2_equips", []):
			var p2fx: Array = Phase2EquipRuntime.on_side_end(f, str(p2["id"]), int(p2["star"]), fighters)
			# 海浪 043 横扫 VFX: 复用 _play_wave_sweep (1:1 phase-1 e_wave, 被扫行 y-40)
			var is_wave43: bool = str(p2["id"]) == "p2eq_043"
			if is_wave43 and not p2fx.is_empty():
				var w2_ti: int = int(p2fx[0].get("target_idx", -1))
				if w2_ti >= 0 and w2_ti < slot_nodes.size():
					_play_wave_sweep(float(slot_nodes[w2_ti].get_meta("home_pos", slot_nodes[w2_ti].position).y) - 40.0)
				# 海浪接触各目标才掉血/盾/魔法: 给各 effect 盖上"波头扫到该目标"的到达时刻(arrival-delay),
				#   沿波扫方向(x 增)逐个错峰显示. 纯显示时机, 伤害/盾/属性数值已在 on_side_end 结算(不动).
				for e in p2fx:
					if e is Dictionary:
						e["delay"] = _wave_arrival_delay(int(e.get("target_idx", -1)))
				# 按到达时刻(波扫顺序)稳定排序 → 顺序循环增量等待才单调 (否则后扫的早到=被 clamp 成立即)
				p2fx.sort_custom(func(a, b): return float(a.get("delay", 0.0)) < float(b.get("delay", 0.0)))
			var wave_elapsed: float = 0.0   # 海浪路径: 已等待的累计墙钟时间 (把 effect 绝对到达时刻转成顺序循环的增量等待)
			for e in p2fx:
				var ti2: int = int(e.get("target_idx", -1))
				if ti2 < 0 or ti2 >= slot_nodes.size():
					continue
				if fighters[ti2].get("_deathVfxDone", false):   # 目标已死透 → 跳过(修死龟残留效果重触发/飘字)
					continue
				# 逐效果错峰 (delay) + 装备 VFX (vfx) — 与 phase-1 _fire_side_end_equipment 同款字段读取
				var dly2: float = float(e.get("delay", 0.0))
				if is_wave43:
					# 海浪: delay 是【绝对】到达时刻 → 顺序循环里减去已等待的, 只补还差的增量, 让每段落在波头真到达的墙钟点
					dly2 = maxf(0.0, dly2 - wave_elapsed)
				if dly2 > 0.0:
					await get_tree().create_timer(dly2).timeout
					wave_elapsed += dly2
				var vfx2: String = str(e.get("vfx", ""))
				if vfx2 == "projectile":
					# 装备弹道 (020哑铃/052左轮/056飞镖): 从携带者飞向目标 (fire-and-forget) — 1:1 phase-1 fireStraightProjectile
					var pf2: int = int(e.get("vfx_from", -1))
					if pf2 >= 0:
						_fire_projectile(pf2, ti2, str(e.get("vfx_path", "")), float(e.get("vfx_size", 32.0)), float(e.get("vfx_dur", 0.36)))
						# 血跟子弹落地才掉: 等弹道飞行时长后再飘字/扣血显示 (数值已结算, 只推迟显示时机)
						if str(e.get("kind", "damage")) == "damage":
							await get_tree().create_timer(float(e.get("vfx_dur", 0.36))).timeout
				elif vfx2 != "":
					_play_equip_vfx(vfx2, ti2)
					if e.get("kind", "damage") == "damage":
						# 伤害走显示调度队列 → 同目标多源有序消费, 不抢血条; 统计立即记 (数值已结算).
						battle_stats.record_damage(f, fighters[ti2], e.get("value", 0), _stat_type(str(e.get("dmg_type", "physical"))))
						_enqueue_display(ti2, {"kind": "damage", "value": e.get("value", 0), "dmg_type": str(e.get("dmg_type", "physical")), "is_crit": false, "hp_after": float(fighters[ti2].get("hp", 0)), "shield_after": float(fighters[ti2].get("shield", 0))})
						if not fighters[ti2].get("alive", false):
							await _await_display_drained(ti2)   # 死亡时机根治: 等致命掉血血条 step 显示完再播死亡
							await _play_death(ti2)
					else:
						# heal 等其它 kind: 直接飘字+刷血 (队列消费器只识 damage/dot).
						_spawn_float_text(ti2, e.get("value", 0), str(e.get("kind", "damage")), str(e.get("dmg_type", "physical")), false)
						_refresh_slot(ti2)
	# 召唤系满层 → 召唤大熊 fighter + 销毁玩偶装备 (034玩偶 / phase1 e_doll). 在 _p2_equips 遍历之后做 (防遍历中改数组).
	_consume_doll_summons(ended_side)
	# 灵物[召唤] 无敌触手: 该侧每个触手朝最前敌拍击其列 + 消费本回合闪避追击 (规格#553).
	await _process_tentacles(ended_side)


# 浮游炮 side-end: 生成 spawnCount 个 (满 maxDrones 止), turn>=2 每炮打随机敌 (PoC 7355-7413)
func _cyber_side_end(side: String) -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("side", "") != side or not f.get("alive", false) or f.get("_isMech", false):
			continue
		var p = f.get("passive", null)
		if not (p is Dictionary) or p.get("type", "") != "cyberDrone":
			continue
		if not f.has("_drones"):
			f["_drones"] = []
		var drones: Array = f["_drones"]
		var enhanced: bool = f.get("_cyberEnhanced", false)
		var max_d: int = 20 if enhanced else p.get("maxDrones", 10)
		var spawn_count: int = p.get("dronesPerTurn", 2 if enhanced else 1)
		var spawned := 0
		for _d in range(spawn_count):
			if drones.size() >= max_d:
				break
			drones.append({"age": 0})
			spawned += 1
		if spawned > 0:
			_spawn_passive_text(i, "+%d🛰" % spawned)
		if turn <= 1:
			continue   # 第 1 回合只生成不开火
		var drone_scale: float = 0.12 if enhanced else p.get("droneScale", 0.25)
		for _di in range(drones.size()):
			var enemies := _alive_enemies_of(f)
			if enemies.is_empty():
				break
			var tgt: Dictionary = enemies[randi() % enemies.size()]
			var ti: int = fighters.find(tgt)
			var dmg: int = Damage.calc_damage(f, tgt, roundi(f.get("atk", 0) * drone_scale), "physical")
			var r: Dictionary = Damage.apply_raw_damage(tgt, dmg, "physical")
			var shown: int = r["hpLoss"] + r["shieldAbs"]
			if shown > 0:
				_enqueue_display(ti, {"kind": "damage", "value": shown, "dmg_type": "physical", "is_crit": false, "hp_after": float(tgt.get("hp", 0)), "shield_after": float(tgt.get("shield", 0))})
			# 无人机命中也走 on-hit 链 (反伤/结晶/受击盾) — 1:1 PoC BattleScene.ts:7399-7403 triggerOnHitEffects
			var d_bonus: Array = []
			_on_hit_chain(f, tgt, dmg, "physical", i, ti, d_bonus)
			for d_be in d_bonus:
				var d_bt: int = d_be.get("target_idx", -1)
				if d_bt >= 0 and d_be.get("kind", "") == "damage":
					_enqueue_display(d_bt, {"kind": "damage", "value": d_be.get("value", 0), "dmg_type": d_be.get("dmg_type", "physical"), "is_crit": false, "hp_after": float(fighters[d_bt].get("hp", 0)), "shield_after": float(fighters[d_bt].get("shield", 0))})
			if not tgt.get("alive", false):
				await _await_display_drained(ti)   # 死亡时机根治: 等致命掉血血条 step 显示完再播死亡
				await _play_death(ti)
			await get_tree().create_timer(0.12).timeout


# 闪电风暴 side-end: 随机敌真伤穿透 round(atk×0.82×surge) + 叠 1 层电击 (PoC 7294-7324)
func _lightning_side_end(side: String) -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("side", "") != side or not f.get("alive", false):
			continue
		var p = f.get("passive", null)
		if not (p is Dictionary) or p.get("type", "") != "lightningStorm":
			continue
		# (涌动倒计时已移到 _actor_turn_begin, 对齐 PoC turn-begin 递减; 此处只读 _surge_boost 不再减)
		var enemies := _alive_enemies_of(f)
		if enemies.is_empty():
			continue
		var tgt: Dictionary = enemies[randi() % enemies.size()]
		var ti: int = fighters.find(tgt)
		# P78: 闪电风暴每回合电击 → 天降闪电劈下 (1:1 PoC setLightningVfxHook, combat.js:702)
		_play_lightning_strike(ti)
		var dmg: int = roundi(f.get("atk", 0) * p.get("shockScale", 0.82) * SkillHandlers._surge_boost(f))
		var r: Dictionary = Damage.apply_raw_damage(tgt, dmg, "true", true)
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		if shown > 0:
			_enqueue_display(ti, {"kind": "damage", "value": shown, "dmg_type": "true", "is_crit": false, "hp_after": float(tgt.get("hp", 0)), "shield_after": float(tgt.get("shield", 0))})
		# 叠层 + 满层引爆
		var det: Array = []
		SkillHandlers._lightning_apply_shock(f, tgt, fighters, det)
		for de in det:
			# 满 8 层引爆 → 在引爆目标脚下再劈一道闪电 (1:1 PoC passive-triggers.ts:380)
			_play_lightning_strike(de["target_idx"])
			_enqueue_display(int(de["target_idx"]), {"kind": "damage", "value": de["value"], "dmg_type": "true", "is_crit": false, "hp_after": float(fighters[int(de["target_idx"])].get("hp", 0)), "shield_after": float(fighters[int(de["target_idx"])].get("shield", 0))})
		if not tgt.get("alive", false):
			await _await_display_drained(ti)   # 死亡时机根治: 等致命掉血血条 step 显示完再播死亡
			await _play_death(ti)
		await get_tree().create_timer(0.2).timeout


# 机甲 side-end: 自动攻击当前最低血敌 1.5×atk 物理 (PoC 7431-7444)
func _mech_side_end(side: String) -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("side", "") != side or not f.get("alive", false) or not f.get("_isMech", false):
			continue
		# 眩晕跳过 (审计#9, 对齐主循环 @1979): 被眩晕的机甲跳过本次自动攻击并消耗眩晕 (镜 _do_stun_skip)
		if Buffs.is_stunned(f):
			f["_stunUsed"] = true
			Buffs.remove_all(f, "stun")
			_remove_stun_overhead(i)   # 出手消耗眩晕 → 撤头顶星星
			_spawn_passive_text(i, "💫 眩晕")
			await get_tree().create_timer(0.3).timeout
			continue
		var enemies := _alive_enemies_of(f)
		if enemies.is_empty():
			continue
		enemies.sort_custom(func(a, b): return float(a.get("hp", 0)) < float(b.get("hp", 0)))
		var tgt: Dictionary = enemies[0]
		var ti: int = fighters.find(tgt)
		var dmg: int = Damage.calc_damage(f, tgt, f.get("atk", 0) * 1.5, "physical")
		var r: Dictionary = Damage.apply_raw_damage(tgt, dmg, "physical")
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		if shown > 0:
			_enqueue_display(ti, {"kind": "damage", "value": shown, "dmg_type": "physical", "is_crit": false, "hp_after": float(tgt.get("hp", 0)), "shield_after": float(tgt.get("shield", 0))})
		# 机甲攻击也走 on-hit 链 (反伤/结晶/受击盾) — 1:1 PoC dealPhysicalHit BattleScene.ts:7441
		var m_bonus: Array = []
		_on_hit_chain(f, tgt, dmg, "physical", i, ti, m_bonus)
		for m_be in m_bonus:
			var m_bt: int = m_be.get("target_idx", -1)
			if m_bt >= 0 and m_be.get("kind", "") == "damage":
				_enqueue_display(m_bt, {"kind": "damage", "value": m_be.get("value", 0), "dmg_type": m_be.get("dmg_type", "physical"), "is_crit": false, "hp_after": float(fighters[m_bt].get("hp", 0)), "shield_after": float(fighters[m_bt].get("shield", 0))})
		if not tgt.get("alive", false):
			await _await_display_drained(ti)   # 死亡时机根治: 等致命掉血血条 step 显示完再播死亡
			await _play_death(ti)
		await get_tree().create_timer(0.2).timeout


# 深海军械库[军火] 回合末: 炮台1 沿"列"轰击(80物理) + 给最低血友军回血; 9档火控为军火携带者追加真伤波。
#   炮台为纯逻辑(无实体), 标记 _armoryTier/_armoryCount/_armoryTrueDmgPct 由 Phase2Schools.apply_team_start 写到本队全员。
#   简化: "炮台↔敌直线" 用敌方同列(front-N/back-N)近似 — 炮台居我方前排中路, 笔直打向选定敌列。
func _armory_turret_fire(side: String) -> void:
	# 本侧有无激活军火 (任一存活非蛋单位带 _armoryTier ≥1)
	var holder: Dictionary = {}
	for f in fighters:
		if f.get("side", "") == side and f.get("alive", false) and not f.get("_isEgg", false) and int(f.get("_armoryTier", 0)) >= 1:
			holder = f
			break
	if holder.is_empty():
		return
	var tier: int = int(holder.get("_armoryTier", 0))
	var acount: int = int(holder.get("_armoryCount", 3))
	var enemies := _alive_enemies_of(holder)
	# 排除不可选(口哨大师等)
	enemies = enemies.filter(func(e): return not e.get("_untargetable", false))
	if enemies.is_empty():
		return

	# ── 炮台1 (3档+): 选一名敌人, 沿其"列"(同 col 的 front/back)轰击全员 80 物理, 最低血友军回 30%×总伤 ──
	var aim: Dictionary = enemies[randi() % enemies.size()]
	var aim_col: String = ""
	var aim_parts := String(aim.get("_slotKey", "")).split("-")
	if aim_parts.size() >= 2:
		aim_col = String(aim_parts[1])
	var line_targets: Array = []
	if aim_col != "":
		for e in enemies:
			if String(e.get("_slotKey", "")).ends_with("-" + aim_col):
				line_targets.append(e)
	if line_targets.is_empty():
		line_targets = [aim]
	# 军火炮台轰击演出: 从军火携带者贯穿到瞄准敌的赛博光束扫射 (复用 cyber-beam-sweep, 无新资源)
	var hi_aim: int = fighters.find(holder)
	var aim_i: int = fighters.find(aim)
	if hi_aim >= 0 and aim_i >= 0:
		_play_cyber_beam_sweep(hi_aim, aim_i)
		_play_screen_shake(0.16, 8.0)
		await get_tree().create_timer(0.18).timeout   # 光束扫过再落伤 (与 PoC 炮击节奏一致)
	var total_dealt: int = 0
	for e in line_targets:
		var ti: int = fighters.find(e)
		if ti < 0:
			continue
		var dmg: int = Damage.calc_damage(holder, e, 80.0, "physical")
		var r: Dictionary = Damage.apply_raw_damage(e, dmg, "physical")
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		total_dealt += shown
		if shown > 0:
			_spawn_float_text(ti, shown, "damage", "physical", false)
			_flash_hit(ti)
			_refresh_slot(ti)
			battle_stats.record_damage(holder, e, shown, _stat_type("physical"))
		if not e.get("alive", false):
			await _play_death(ti)
	_spawn_passive_text(fighters.find(holder), "🔫 炮台轰击")
	# 治疗最低血友军 30%×总伤
	if total_dealt > 0:
		var allies := _alive_allies_of(holder)
		allies = allies.filter(func(a): return not a.get("_isEgg", false))
		if not allies.is_empty():
			allies.sort_custom(func(a, b): return float(a.get("hp", 0)) < float(b.get("hp", 0)))
			var lowest: Dictionary = allies[0]
			var li: int = fighters.find(lowest)
			var heal: int = roundi(total_dealt * 0.30)
			if heal > 0 and li >= 0:
				lowest["hp"] = mini(int(lowest.get("maxHp", 0)), int(lowest.get("hp", 0)) + heal)
				_spawn_float_text(li, heal, "heal", "physical", false)
				_refresh_slot(li)
	await get_tree().create_timer(0.18).timeout

	# ── 炮台3 火控 (9档): 军火携带者额外造成 (10+5×件数)% 真伤 → 每位携带者向随机敌轰一发真伤波(以其 ATK 计) ──
	if tier >= 3:
		for f in fighters:
			if f.get("side", "") != side or not f.get("alive", false) or float(f.get("_armoryTrueDmgPct", 0.0)) <= 0.0:
				continue
			var live := _alive_enemies_of(f).filter(func(e): return not e.get("_untargetable", false))
			if live.is_empty():
				break
			var tg: Dictionary = live[randi() % live.size()]
			var tgi: int = fighters.find(tg)
			var tdmg: int = roundi(float(f.get("atk", 0)) * float(f.get("_armoryTrueDmgPct", 0.0)) / 100.0)
			if tdmg <= 0:
				continue
			var tr: Dictionary = Damage.apply_raw_damage(tg, tdmg, "true")
			var tshown: int = tr["hpLoss"] + tr["shieldAbs"]
			if tshown > 0:
				_spawn_float_text(tgi, tshown, "damage", "true", false)
				_flash_hit(tgi)
				_refresh_slot(tgi)
				battle_stats.record_damage(f, tg, tshown, _stat_type("true"))
			if not tg.get("alive", false):
				await _play_death(tgi)
			await get_tree().create_timer(0.12).timeout


# 赛博龟死亡 → 机甲 (PoC 4511-4550): dc 浮游炮组装, 复活为机甲
func _check_mech_transforms() -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("alive", false) or f.get("_mechFormed", false):
			continue
		var p = f.get("passive", null)
		if not (p is Dictionary) or p.get("type", "") != "cyberDrone":
			continue
		var dc: int = (f.get("_drones", []) as Array).size()
		if dc <= 0:
			continue
		f["_mechFormed"] = true
		var lv: int = f.get("_level", 1)
		var hp_per: float = p.get("mechHpPerBase", 30) + p.get("mechHpPerLv", 2) * lv
		var atk_per: float = p.get("mechAtkPerBase", 4.5) + p.get("mechAtkPerLv", 0.1) * lv
		f["maxHp"] = roundi(hp_per * dc); f["hp"] = f["maxHp"]
		f["baseAtk"] = roundi(atk_per * dc); f["atk"] = f["baseAtk"]
		var armor: int = 3 * dc if f.get("_cyberEnhanced", false) else 0
		f["baseDef"] = armor; f["def"] = armor; f["baseMr"] = armor; f["mr"] = armor
		f["shield"] = 0; f["crit"] = 0.25; f["buffs"] = []; f["alive"] = true
		f["name"] = "机甲"; f["emoji"] = "🤖"; f["_isMech"] = true
		f["passive"] = {"type": "mechBody", "droneCount": dc}
		f["skills"] = [{"type": "physical", "hits": 1, "cd": 0, "cdLeft": 0, "atkScale": 1.5, "name": "机甲攻击"}]
		_swap_avatar(i, "mech")
		_revive_node(i)
		var mshift: Dictionary = Synergies.apply_shift(f)   # 换形羁绊: 机甲变身后护盾 + tier3首次ATK
		if int(mshift.get("atkAdded", 0)) > 0:
			_spawn_passive_text(i, "换形 +%dATK" % int(mshift["atkAdded"]), "#ff9d5c")   # 1:1 PoC float (原漏)
		Audio.play_sfx("rebirth", 0.7)   # 1:1 PoC 机甲变身 sfx-rebirth vol0.7 (BattleScene.ts:4285)
		_refresh_slot(i)
		# 机甲组装 VFX + 震屏 (1:1 PoC BattleScene.ts:4533-4588 cyber-mech-birth — 之前漏播了)
		var mpos: Vector2 = slot_nodes[i].get_meta("home_pos", slot_nodes[i].position) + Vector2(0.0, -55.0)
		_play_vfx("cyber-mech-birth", mpos, 1.5)
		_play_screen_shake(0.35, 12.0)
		battle_log.append_text("[color=#4cc9f0]🤖 %d 浮游炮组装成机甲! (%dHP/%dATK)[/color]\n" % [dc, f["maxHp"], f["baseAtk"]])


# 战斗中换龟立绘 (变身/机甲): 重载 avatar 纹理 + 重算缩放/朝向 (asset agent 建议抽出)
func _swap_avatar(idx: int, pet_id: String) -> void:
	if idx < 0 or idx >= slot_nodes.size():
		return
	var node: Node2D = slot_nodes[idx]
	if not node.has_meta("avatar"):
		return
	var avatar: Sprite2D = node.get_meta("avatar")
	# 形态贴图解析 (1:1 PoC BootScene 资源键): mech=pets/mech.png(在 avatars/), volcano=passive/volcano-form-icon.png。
	#   先查 avatars/<id>.png, 缺失再查已知形态贴图表 (火山形态图标不在 avatars/ 下)。
	var path := "res://assets/sprites/avatars/%s.png" % pet_id
	if not ResourceLoader.exists(path):
		var form_paths := {
			"volcano": "res://assets/sprites/passive/volcano-form-icon.png",  # PoC pet-form-volcano (BootScene.ts:87)
		}
		path = form_paths.get(pet_id, path)
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	avatar.texture = tex
	var th: float = tex.get_height() if tex.get_height() > 0 else 120.0
	var sf: float = 120.0 / th
	avatar.scale = Vector2(sf, sf)
	# 朝向: 用换形后的立绘 id 判定 (mech 朝右 → 反着翻转), 1:1 PoC FACING_RIGHT_ASSETS。
	if _should_flip_x(pet_id, fighters[idx].get("side", "")):
		avatar.scale.x = -sf


# 机甲复活: 撤销 _play_death 的淡出/旋转
func _revive_node(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size():
		return
	var node: Node2D = slot_nodes[idx]
	if idx < fighters.size():
		fighters[idx]["_deathVfxDone"] = false   # 复活 → 清死亡演出标, 之后再死可正常重播
	_bump_disp_epoch(idx)   # 复活: bump epoch → 死前残留的待显事件不会在复活后的血条上回放 (#8)
	node.modulate.a = 1.0
	node.rotation = 0.0
	node.position = node.get_meta("home_pos", node.position)   # 撤销 deathHop 位移
	var av_r: Sprite2D = node.get_meta("avatar", null)
	if av_r != null:
		av_r.modulate = Color(1, 1, 1, 1)   # 撤销死亡灰度压暗 + 淡出 (本体淡出现在动 avatar)
		av_r.position = av_r.get_meta("home", av_r.position)   # 撤销 deathHop 位移 (现在动 avatar 非 node)
		av_r.rotation = 0.0                                    # 撤销 deathHop 倾倒
	var sh_r = node.get_meta("shadow", null)
	if sh_r != null and is_instance_valid(sh_r):
		sh_r.modulate.a = 1.0   # 撤销影子独立 1200ms 淡出
	var hud_r = node.get_meta("hud", null)
	if hud_r != null:
		hud_r.modulate.a = 1.0


# 缩头盾 round-end: turns-1, 到期剩余盾 × healPct% 转生命 (PoC processRoundEndBuffs)
func _tick_hiding_shields() -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("alive", false):
			continue
		# 缩头限时盾: 到期剩余×healPct% 转生命
		if int(f.get("_hidingShieldTurns", 0)) > 0:
			f["_hidingShieldTurns"] = int(f["_hidingShieldTurns"]) - 1
			if int(f["_hidingShieldTurns"]) <= 0:
				var remain: int = int(f.get("_hidingShieldVal", 0))
				if remain > 0:
					var heal: int = roundi(remain * f.get("_hidingShieldHealPct", 20) / 100.0)
					var before: int = f.get("hp", 0)
					f["hp"] = mini(int(f.get("maxHp", 0)), before + heal)
					if int(f["hp"]) > before:
						_spawn_float_text(i, int(f["hp"]) - before, "heal")   # 1:1 PoC BattleScene.ts:7877 plain +N heal-num绿 (原"+N🛡→生命"=自创后缀+错类)
				f["_hidingShieldVal"] = 0
				_refresh_slot(i)
		# 泡泡盾: 到期剩余×burstScale 对全敌魔法爆裂
		if int(f.get("_bubbleShieldTurns", 0)) > 0:
			f["_bubbleShieldTurns"] = int(f["_bubbleShieldTurns"]) - 1
			if int(f["_bubbleShieldTurns"]) <= 0:
				var bval: int = int(f.get("bubbleShieldVal", 0))
				if bval > 0:
					_play_aoe_ring(i, Color(0.6, 0.85, 1.0, 0.6))   # 泡泡盾自爆: 自身处青蓝爆环 (原只敌方飘伤害, 爆源自身无反馈) — 需F5
					var burst: int = roundi(bval * f.get("_bubbleBurstScale", 2))
					for e in fighters:
						if e.get("side", "") != f.get("side", "") and e.get("alive", false):
							var ei: int = fighters.find(e)
							var r: Dictionary = Damage.apply_raw_damage(e, Damage.calc_damage(f, e, burst, "magic"), "magic")
							if r["hpLoss"] + r["shieldAbs"] > 0:
								_spawn_float_text(ei, r["hpLoss"] + r["shieldAbs"], "damage", "magic", false)
								_refresh_slot(ei)
				f["bubbleShieldVal"] = 0
		# 熔岩盾: 到期清
		if int(f.get("_lavaShieldTurns", 0)) > 0:
			f["_lavaShieldTurns"] = int(f["_lavaShieldTurns"]) - 1
			if int(f["_lavaShieldTurns"]) <= 0:
				f["_lavaShieldVal"] = 0
		# 连笔墨链: turns-1, 到期清除 (PoC turn.js:965-972 processRoundEndBuffs)
		var ink_link = f.get("_inkLink", null)
		if ink_link is Dictionary and int(ink_link.get("turns", 0)) > 0:
			ink_link["turns"] = int(ink_link["turns"]) - 1
			if int(ink_link["turns"]) <= 0:
				f["_inkLink"] = null
				battle_log.append_text("[color=#6c5ce7]%s🐢 %s 的连笔链接消散了[/color]\n" % [f.get("emoji", ""), f.get("name", "?")])


# 复活检查: 凤凰涅槃 (首次死亡 → revivePct% HP 复活 + 全敌灼烧/治疗削减)
func _check_revives() -> void:
	# 猎人「猎杀」执行端 (PoC processHunterExecute, 原完全缺失): 存活猎人(hunterKill)每次(行动后)斩杀所有 HP<hpThresh% 的存活敌
	#   → 置死, 走下方死亡管线(复活检查 + 猎杀窃取). 跳过 undeadLock/龟蛋_eggImmune/不沉锚_p2AnchorImmune.
	#   (3-phase 处决演出 hunter-kill-icon/箭雨/红屏闪 需 F5; 此处实装逻辑+飘字+log)
	for hi in range(fighters.size()):
		var hf: Dictionary = fighters[hi]
		var hpas = hf.get("passive", null)
		if not (hpas is Dictionary) or hpas.get("type", "") != "hunterKill" or not hf.get("alive", false):
			continue
		var thresh: float = float(hpas.get("hpThresh", 14))
		for ei in range(fighters.size()):
			var ef: Dictionary = fighters[ei]
			if not ef.get("alive", false) or ef.get("side", "") == hf.get("side", ""):
				continue
			if int(ef.get("_undeadLockTurns", 0)) > 0 or ef.get("_eggImmune", false) or ef.get("_p2AnchorImmune", false):
				continue   # PoC state.js: undeadLock 跳过; 龟蛋/不沉锚免处决
			if float(ef.get("maxHp", 1)) > 0.0 and float(ef.get("hp", 0)) / float(ef.get("maxHp", 1)) * 100.0 < thresh:
				# 1:1 PoC processHunterExecute(BattleScene.ts:5999-6015): 走 applyRawDamage 真伤 + 记统计;
				#   先保活 → on-hit 链(反伤/泡泡束缚) + 通用吸血(猎人 8% 生命偷取) → 再杀。原直接 hp=0 跳过全部。
				var exec_dmg: int = int(ef.get("hp", 0)) + int(ef.get("shield", 0))
				var er: Dictionary = Damage.apply_raw_damage(ef, exec_dmg, "true")
				var eshown: int = er["hpLoss"] + er["shieldAbs"]
				battle_stats.record_damage(hf, ef, eshown, "tru")
				ef["alive"] = true   # 保活: 让需 target 存活的 on-hit 效果(反伤/束缚)生效
				var hk_bonus: Array = []
				_on_hit_chain(hf, ef, exec_dmg, "true", hi, ei, hk_bonus)
				for hk_be in hk_bonus:
					var hk_bt: int = hk_be.get("target_idx", -1)
					if hk_bt < 0:
						continue
					if hk_be.get("kind", "") == "damage":
						_spawn_float_text(hk_bt, hk_be.get("value", 0), "damage", hk_be.get("dmg_type", "true"), false)
						_refresh_slot(hk_bt)
					elif hk_be.get("kind", "") == "shield":
						_spawn_float_text(hk_bt, hk_be.get("value", 0), "shield")
						_refresh_slot(hk_bt)
				# 通用吸血 (猎人 8% 生命偷取也走此) — 1:1 PoC triggerOnHitEffects:598-602
				if hf.get("alive", false) and hf.get("lifestealPct", 0.0) > 0.0 and exec_dmg > 0:
					var hk_heal: int = roundi(exec_dmg * hf.get("lifestealPct", 0.0))
					if hk_heal > 0:
						var hlb: int = int(hf.get("hp", 0))
						hf["hp"] = mini(int(hf.get("maxHp", 0)), hlb + hk_heal)
						var hk_healed: int = int(hf["hp"]) - hlb
						if hk_healed > 0:
							_spawn_float_text(hi, hk_healed, "heal")
							_refresh_slot(hi)
				ef["hp"] = 0
				ef["alive"] = false
				battle_stats.record_kill(hf, ef)
				_refresh_slot(ei)
				_play_execute_flash(ei)   # 猎人斩杀: 处决红闪+幽冥触碰+震屏 (复用现成, 同羁绊5560/暴君7016; 原只飘字) — 需F5
				_spawn_passive_text(ei, "🎯 猎杀!")
				battle_log.append_text("[color=#ff6b6b]🎯 %s 猎杀 %s (HP<%d%%)[/color]\n" % [hf.get("name", "?"), ef.get("name", "?"), int(thresh)])
	_split_conch_worms()   # 复活海螺 3★: 会分裂的小虫每回合在空位生成新虫 (gate 每回合至多1次/虫)
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("alive", false):
			continue
		var p = f.get("passive", null)
		# 凤凰涅槃: 首次死亡复活
		if p is Dictionary and p.get("type", "") == "phoenixRebirth" and not f.get("_rebirthUsed", false):
			f["_rebirthUsed"] = true
			var enhanced := false
			for ps in f.get("_passiveSkills", []):
				if ps.get("type", "") == "phoenixEnhancedRebirth":
					enhanced = true
			var hp_pct: float = 100.0 if enhanced else p.get("revivePct", 30)
			_revive_fighter(i, hp_pct, "🐦凤凰重生!")   # 1:1 PoC BattleScene.ts:4340 (原"🔥涅槃重生!"=自创措辞)
			_play_flame_burst(i)   # 凤凰涅槃复活: 橙红火焰喷涌爆环 (原只飘字, 玩家看不见复活/灼烧瞬间) — 需F5
			Audio.play_sfx("rebirth", 0.7)   # 1:1 PoC sfx-rebirth vol0.7 (BattleScene.ts:4161) — 原rebirth.wav载入却从不播
			if enhanced:
				var boost: int = roundi(f.get("baseAtk", 0) * 0.20)
				f["baseAtk"] = f.get("baseAtk", 0) + boost; f["atk"] = f.get("atk", 0) + boost
			for e in fighters:
				if e.get("side", "") != f.get("side", "") and e.get("alive", false):
					Dot.apply_stacks(e, "burn", Dot.default_burn_stacks(f))
					Buffs.add(e, "healReduce", 50, 4, "refresh")
			battle_log.append_text("[color=#ff6600]🔥🐢 %s 涅槃重生! 灼烧全敌[/color]\n" % f.get("name", "?"))
			continue
		# 天使圣光: 首次阵亡 25%HP 复活一次 (passiveSkill _angelRevive; 1:1 PoC _angelReviveUsed 守卫, 原从不接=被动无效)
		if f.get("_angelRevive", false) and not f.get("_angelReviveUsed", false):
			f["_angelReviveUsed"] = true
			_revive_fighter(i, 25.0, "😇圣光重生!")
			_play_summon_burst(i, Color(1.0, 0.92, 0.55))   # 天使圣光复活: 金白圣光爆环 (复用召唤光环, 原只飘字) — 需F5
			Audio.play_sfx("rebirth", 0.7)   # 1:1 PoC sfx-rebirth vol0.7 (BattleScene.ts:4329)
			continue
		# 无头龟亡灵: 首次死亡锁血 1HP, 2回合内致死被截留 1 (锁血消费在 apply_raw_damage)
		if p is Dictionary and p.get("type", "") == "undeadRage" and not f.get("_undeadUsed", false):
			f["_undeadUsed"] = true; f["alive"] = true; f["hp"] = 1; f["_undeadLockTurns"] = 2; f["_stunUsed"] = false
			f["_hunterKillProcessed"] = false
			_revive_node(i); _refresh_slot(i)
			# 1:1 PoC(BattleScene.ts:4592-4599): undeadRage 死亡只 log 不飘"亡灵不灭!"文字 (原自创)
			battle_log.append_text("[color=#9d6b9d]💀 %s 亡灵之力! 锁血 2 回合[/color]\n" % f.get("name", "?"))
			continue
		# 复活海螺 (e_conch): 彻底阵亡 → 变形海螺小虫复活 (EquipmentRuntime.on_death 做属性/技能/alive 变形)
		if f.get("_equipConch", false) and not f.get("_conchUsed", false):
			var old_name: String = f.get("name", "?")
			if EquipmentRuntime.on_death(f, "e_conch"):
				_revive_node(i); _refresh_slot(i)
				_play_summon_burst(i, Color(0.3, 0.79, 0.94))   # 复活海螺(033/e_conch): 化形入场青色召唤光环 (需F5)
				_spawn_passive_text(i, "🐛 化形小虫!")   # 1:1 PoC BattleScene.ts:4479 (同效果, 原"🐚海螺复活!"=自创措辞)
				battle_log.append_text("[color=#4cc9f0]🐚 %s 变形海螺小虫, 复活![/color]\n" % old_name)
			continue
	# 猎杀窃取: 任意单位死亡 → 对面存活猎人各窃取一次 (PoC processDeathPassives:4691)
	for i in range(fighters.size()):
		var d: Dictionary = fighters[i]
		if not d.get("alive", false) and not d.get("_hunterKillProcessed", false):
			d["_hunterKillProcessed"] = true
			_process_hunter_kill(d)
			_process_pirate_death_hook(d)   # 海盗龟死亡钩锁: 随机敌 maxHp×deathHookPct% 真伤
			if d.get("_isCandyBomb", false) and not d.get("_candyBombDetonated", false):
				_detonate_candy_bomb(i)   # 糖果炸弹被击杀→引爆 AOE 1:1 PoC
			# 左轮: 任意敌死亡 → 对面持左轮者 +1 子弹 (cap 6) (PoC e_revolver)
			for g in fighters:
				if g.get("_equipRevolver", false) and g.get("alive", false) and g.get("side", "") != d.get("side", ""):
					g["_equipRevolverBullets"] = mini(6, int(g.get("_equipRevolverBullets", 0)) + 1)
			# 招财龟聚宝盆: 任意单位阵亡 → 所有存活财神 +9 币
			for g in fighters:
				var gp = g.get("passive", null)
				if gp is Dictionary and gp.get("type", "") == "fortuneGold" and g.get("alive", false):
					g["_goldCoins"] = int(g.get("_goldCoins", 0)) + 9


# 海盗龟死亡钩锁 (PoC 4623): 死亡时对随机存活敌 maxHp×deathHookPct% 真伤穿透 + 走 on-hit 链.
func _process_pirate_death_hook(dead: Dictionary) -> void:
	var p = dead.get("passive", null)
	if not (p is Dictionary) or p.get("type", "") != "pirateBarrage":
		return
	var hook_pct: float = p.get("deathHookPct", 0)
	if hook_pct <= 0:
		return
	var enemies := _alive_enemies_of(dead)
	if enemies.is_empty():
		return
	var attacker: Dictionary = enemies[randi() % enemies.size()]
	var dmg: int = roundi(dead.get("maxHp", 0) * hook_pct / 100.0)
	var ai: int = fighters.find(attacker)
	var was_alive: bool = attacker.get("alive", false)
	var r: Dictionary = Damage.apply_raw_damage(attacker, dmg, "true", true)
	var shown: int = r["hpLoss"] + r["shieldAbs"]
	if shown > 0:
		_spawn_float_text(ai, shown, "damage", "true", false)
		_refresh_slot(ai)
		battle_stats.record_damage(dead, attacker, shown, "tru")
	# 钩锁伤害也触发 on-hit 链 (吸血/装备/结晶 — PoC 4649)
	var bonus: Array = []
	_on_hit_chain(dead, attacker, dmg, "true", fighters.find(dead), ai, bonus)
	if was_alive and not attacker.get("alive", false):
		_award_and_record_kill(dead, attacker)
	battle_log.append_text("  [color=#ffb347]⚓ %s 钩锁! 对 %s %d 真实[/color]\n" % [dead.get("name", "?"), attacker.get("name", "?"), shown])


# 猎杀窃取: 对面所有存活 hunterKill 龟从死者偷 stealPct% atk/def/mr/maxHp
func _process_hunter_kill(dead: Dictionary) -> void:
	for h in fighters:
		var hp = h.get("passive", null)
		if not (hp is Dictionary) or hp.get("type", "") != "hunterKill" or not h.get("alive", false) or h.get("side", "") == dead.get("side", ""):
			continue
		var pct: float = hp.get("stealPct", 5)
		var sa: int = roundi(dead.get("baseAtk", 0) * pct / 100.0)
		var sd: int = roundi(dead.get("baseDef", 0) * pct / 100.0)
		var sm: int = roundi(int(dead.get("baseMr", dead.get("baseDef", 0))) * pct / 100.0)
		var shp: int = roundi(dead.get("maxHp", 0) * pct / 100.0)
		h["baseAtk"] = h.get("baseAtk", 0) + sa; h["atk"] = h.get("atk", 0) + sa
		h["baseDef"] = h.get("baseDef", 0) + sd; h["def"] = h.get("def", 0) + sd
		h["baseMr"] = int(h.get("baseMr", h.get("baseDef", 0))) + sm; h["mr"] = h.get("mr", 0) + sm
		h["maxHp"] = int(h.get("maxHp", 0)) + shp; h["hp"] = int(h.get("hp", 0)) + shp
		if shp > 0:
			battle_stats.record_damage(h, dead, shp, "tru")   # 偷取的HP计入猎人真伤输出条 (1:1 PoC battleStats.recordDamage(h,dead,sHp,'tru'); 原漏)
		if hp.has("lifesteal"):
			h["_lifestealPct"] = float(h.get("_lifestealPct", 0)) + hp.get("lifesteal", 0)
		var hi: int = fighters.find(h)
		if hi >= 0:
			# 1:1 PoC(BattleScene.ts:4732-4739): 飘窃取属性明细 + log"猎杀吸收" (原飘"🎯窃取!"=自创措辞且漏log)
			_spawn_passive_text(hi, "+%d攻+%d甲+%d抗+%dHP" % [sa, sd, sm, shp])
			battle_log.append_text("[color=#ff8c42]🏹 %s 猎杀吸收! 攻+%d 甲+%d 抗+%d HP+%d[/color]\n" % [h.get("name", "?"), sa, sd, sm, shp])
			_refresh_slot(hi)


# 复活一个 fighter (PoC reviveFighter): hpPct (+再生羁绊bonus, cap100) → alive; tier3 复活攻击
func _revive_fighter(idx: int, hp_pct: float, label: String) -> void:
	var f: Dictionary = fighters[idx]
	var pct: float = minf(100.0, hp_pct + f.get("_synergyRegenReviveBonus", 0.0) * 100.0)
	f["hp"] = roundi(f.get("maxHp", 0) * pct / 100.0)
	f["alive"] = true
	f["_stunUsed"] = false
	f["_hunterKillProcessed"] = false
	_revive_node(idx)
	_refresh_slot(idx)
	_spawn_passive_text(idx, label)
	# 再生羁绊 tier3: 复活时对随机敌 1×ATK 魔法
	if f.get("_synergyRegenReviveAttack", false):
		var en := _alive_enemies_of(f)
		if not en.is_empty():
			var tgt: Dictionary = en[randi() % en.size()]
			var ti: int = fighters.find(tgt)
			# PoC BattleScene:4174 floor max(1,...): 即便 MR 全减也至少打 1
			var rev_dmg: int = maxi(1, Damage.calc_damage(f, tgt, f.get("atk", 0), "magic"))
			var r: Dictionary = Damage.apply_raw_damage(tgt, rev_dmg, "magic")
			var shown: int = r["hpLoss"] + r["shieldAbs"]
			if shown > 0:
				_spawn_float_text(ti, shown, "damage", "magic", false)
				_refresh_slot(ti)


# 某 fighter 的存活敌方列表
func _alive_enemies_of(f: Dictionary) -> Array:
	var out: Array = []
	for e in fighters:
		if e.get("side", "") != f.get("side", "") and e.get("alive", false):
			out.append(e)
	return out


func _alive_allies_of(f: Dictionary) -> Array:
	var out: Array = []
	for a in fighters:
		if a.get("side", "") == f.get("side", "") and a.get("alive", false):
			out.append(a)
	return out


# ─── 缩头龟召唤系统 (1:1 PoC spawnSummonAlly / summonAutoAction) ───
const RARITY_ORDER := ["C", "B", "A", "S", "SS", "SSS"]
const SUMMON_SLOT_ORDER := ["back-2", "back-1", "back-0", "front-2", "front-1", "front-0"]


# 战斗开始: 为每个 summonAlly 龟生成 1 随从 (真龟, 血=hpBasis×hpPct%, 后排优先占槽)
## 召唤"单位型"被动技 (1:1 PoC:6305): 随从抽到这些 → 过滤掉(否则随从又召唤随从)
const _SUMMON_SPAWNS_UNIT := {"pirateShipPassive": true, "crystalBall": true, "candyBombPassive": true, "cyberEnhancedDrone": true, "hidingEnhancedSummon": true}
func _spawn_summons() -> void:
	var new_summons: Array = []
	var on_field: Dictionary = {}
	for f in fighters:
		on_field[f.get("id", "")] = true
	for f in fighters:
		var p = f.get("passive", null)
		if not (p is Dictionary) or p.get("type", "") != "summonAlly":
			continue
		var max_i: int = RARITY_ORDER.find(p.get("maxRarity", "A"))
		if max_i < 0:
			max_i = 2
		var candidates: Array = []
		for pet in DataRegistry.launch_pets:
			var ri: int = RARITY_ORDER.find(pet.get("rarity", ""))
			if ri >= 0 and ri <= max_i and not on_field.has(pet.get("id", "")):
				candidates.append(pet)
		if candidates.is_empty():
			continue
		var pick = candidates[randi() % candidates.size()]
		# 随从技能装载: 按主人等级 aiPickSkills 抽 (1:1 PoC BattleScene.ts:6299-6313) + 过滤"召唤单位型"被动;
		#   全过滤掉 → 回退 defaultSkills。 现敌人主队仍用默认 (PoC 主队也不走 aiPickSkills, 仅随从走)。
		var s_opts: Dictionary = {}
		var s_pool: Array = pick.get("skillPool", [])
		var picked = FighterFactory.ai_pick_skills(s_pool, int(f.get("_level", 1)))
		if picked != null:
			var filtered: Array = []
			for pi in picked:
				if pi < s_pool.size() and not _SUMMON_SPAWNS_UNIT.has(str(s_pool[pi].get("type", ""))):
					filtered.append(pi)
			if not filtered.is_empty():
				s_opts["equipped_idxs"] = filtered
		var summon: Dictionary = FighterFactory.create(pick["id"], f.get("side", "left"), s_opts)
		var hp_basis: int = int(f.get("_summonHpBase", f.get("maxHp", 0)))
		var s_hp: int = roundi(hp_basis * p.get("hpPct", 40) / 100.0)
		summon["maxHp"] = s_hp; summon["hp"] = s_hp
		# 召唤羁绊: owner 有 boost → 随从 maxHp ×(1+boost) + ATK +flat
		var hp_boost: float = f.get("_synergySummonHpBoost", 0.0)
		if hp_boost > 0:
			summon["maxHp"] = roundi(int(summon["maxHp"]) * (1.0 + hp_boost)); summon["hp"] = summon["maxHp"]
		var atk_flat: int = f.get("_synergySummonAtkFlat", 0)
		if atk_flat > 0:
			summon["baseAtk"] = summon.get("baseAtk", 0) + atk_flat; summon["atk"] = summon["baseAtk"]
		var slot: String = _find_summon_slot(f)
		if slot == "":
			continue   # 阵地已满
		summon["_slotKey"] = slot
		summon["_position"] = "front" if slot.begins_with("front") else "back"
		summon["_isSummon"] = true
		summon["_owner"] = f
		summon["_level"] = f.get("_level", 1)
		f["_summon"] = summon
		on_field[pick["id"]] = true
		new_summons.append(summon)
	for s in new_summons:
		fighters.append(s)


## 水晶龟登场召唤水晶球 (crystalBall passiveSkill, 1:1 PoC) — HP=本体maxHp×50%, ATK=本体atk, 占空位.
##   带本体的 crystalResonance 被动 (叠结晶/与本体共享目标层数); _owner 绑定 → 本体死则级联消失.
##   不走 _summon_act AI 出手, 改每回合本侧全行动后 _crystal_ball_side_end 射魔光.
func _spawn_crystal_balls() -> void:
	var new_balls: Array = []
	for f in fighters:
		# 仅当玩家【装备了】crystalBall (在 _passiveSkills, 即 equipped_idxs 含其槽位) 才召唤 —
		#   1:1 PoC fighter.ts:50 "P137 CRITICAL": passiveSkill 只在装备时生效, 非全池恒生效 (否则严重错形).
		var has_ball := false
		for ps in f.get("_passiveSkills", []):
			if ps is Dictionary and ps.get("type", "") == "crystalBall":
				has_ball = true
				break
		if not has_ball:
			continue
		if f.get("_crystalBallSpawned", false):
			continue
		var slot: String = _find_summon_slot(f)
		if slot == "":
			continue
		f["_crystalBallSpawned"] = true
		var side: String = str(f.get("side", "left"))
		var bhp: int = maxi(1, roundi(float(f.get("maxHp", 0)) * 0.5))
		var batk: int = int(f.get("atk", 0))
		var ball: Dictionary = {
			"id": "crystal_ball", "name": "水晶球", "emoji": "🔮", "rarity": "C", "side": side,
			"img": "", "sprite": null,
			"_level": int(f.get("_level", 1)), "_maxEnergy": 0, "_energy": 0,
			"maxHp": bhp, "hp": bhp, "shield": 0,
			"baseAtk": batk, "baseDef": 0, "baseMr": 0, "atk": batk, "def": 0, "mr": 0,
			"crit": 0.0, "armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
			"passive": f.get("passive", null),   # 带本体 crystalResonance → on-hit 叠结晶 (共享目标层数)
			"passiveUsedThisTurn": false, "skills": [], "_passiveSkills": [],
			"alive": true, "buffs": [], "tags": [],
			"_position": "front" if slot.begins_with("front") else "back",
			"_slotKey": slot, "_statsDirty": false, "equipment": [],
			"_isSummon": true, "_isCrystalBall": true, "_owner": f,
		}
		new_balls.append(ball)
	for b in new_balls:
		fighters.append(b)


## 水晶球射魔光 (side-end, 本侧全行动后) — 1:1 PoC processCrystalBallBeam(BattleScene.ts:6510).
##   每存活水晶球(本体活): 随机敌→取其同列(same_column F/B)敌, 射束 + 2段各 atk×0.5 魔法;
##   每段走 ball 的 on-hit 链 (ball 带 crystalResonance → 叠结晶, 满层引爆用本体参数).
func _crystal_ball_side_end(side: String) -> void:
	for bi in range(fighters.size()):
		var ball: Dictionary = fighters[bi]
		if not ball.get("_isCrystalBall", false) or not ball.get("alive", false) or ball.get("side", "") != side:
			continue
		var owner = ball.get("_owner", null)
		if not (owner is Dictionary) or not owner.get("alive", false):
			continue
		var enemies := _alive_enemies_of(ball)
		if enemies.is_empty():
			continue
		var aim: Dictionary = enemies[randi() % enemies.size()]
		var ai: int = fighters.find(aim)
		var col_enemies: Array = []
		for c in SlotHelpers.same_column_fighters(fighters, aim):
			if c is Dictionary and c.get("alive", false) and c.get("side", "") != side:
				col_enemies.append(c)
		if col_enemies.is_empty():
			col_enemies = [aim]
		_play_crystal_beam(bi, ai)   # VFX: 球→目标 红警告→蓝紫束
		battle_log.append_text("[color=#b478ff]🔮 %s 射出魔法光线! 沿列 %d 敌[/color]\n" % [str(ball.get("name", "水晶球")), col_enemies.size()])
		await get_tree().create_timer(0.3).timeout   # 等警告相
		for _seg in range(2):
			for tgt in col_enemies:
				if not tgt.get("alive", false):
					continue
				var ti: int = fighters.find(tgt)
				var dmg: int = Damage.calc_damage(ball, tgt, roundi(ball.get("atk", 0) * 0.5), "magic")
				var r: Dictionary = Damage.apply_raw_damage(tgt, dmg, "magic")
				var shown: int = r["hpLoss"] + r["shieldAbs"]
				if shown > 0:
					_spawn_float_text(ti, shown, "damage", "magic", false)
					_refresh_slot(ti)
					battle_stats.record_damage(owner, tgt, shown, "mag")
				# 结晶叠层 + 满层引爆 (ball 带 crystalResonance → _on_hit_chain 处理)
				var cbonus: Array = []
				_on_hit_chain(ball, tgt, dmg, "magic", bi, ti, cbonus)
				for cbe in cbonus:
					var cbt: int = cbe.get("target_idx", -1)
					if cbt >= 0 and cbe.get("kind", "") == "damage":
						_spawn_float_text(cbt, cbe.get("value", 0), "damage", cbe.get("dmg_type", "magic"), false)
						_refresh_slot(cbt)
				if not tgt.get("alive", false):
					await _play_death(ti)
			await get_tree().create_timer(0.15).timeout


## 糖果龟登场召唤糖果炸弹 (candyBombPassive passiveSkill, 1:1 PoC spawnCandyBomb) — 仅装备时生效 (_passiveSkills).
##   HP=本体maxHp×hpPct(40%); 每回合开始自损 decayPct(20%); 归零(自损/被击杀/主人死)引爆: 全敌均摊 explodePct(150%)×maxHp 魔法.
func _spawn_candy_bombs() -> void:
	var new_bombs: Array = []
	for f in fighters:
		var ps_def: Dictionary = {}
		for ps in f.get("_passiveSkills", []):
			if ps is Dictionary and ps.get("type", "") == "candyBombPassive":
				ps_def = ps
				break
		if ps_def.is_empty() or f.get("_candyBombSpawned", false):
			continue
		var slot: String = _find_summon_slot(f)
		if slot == "":
			continue
		f["_candyBombSpawned"] = true
		var side: String = str(f.get("side", "left"))
		var bhp: int = maxi(1, roundi(float(f.get("maxHp", 0)) * float(ps_def.get("hpPct", 40)) / 100.0))
		var bomb: Dictionary = {
			"id": "candy_bomb", "name": "糖果炸弹", "emoji": "🍬", "rarity": "C", "side": side,
			"img": "", "sprite": null,
			"_level": int(f.get("_level", 1)), "_maxEnergy": 0, "_energy": 0,
			"maxHp": bhp, "hp": bhp, "shield": 0,
			"baseAtk": 0, "baseDef": 0, "baseMr": 0, "atk": 0, "def": 0, "mr": 0,
			"crit": 0.0, "armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
			"passive": null, "passiveUsedThisTurn": false, "skills": [], "_passiveSkills": [],
			"alive": true, "buffs": [], "tags": [],
			"_position": "front" if slot.begins_with("front") else "back",
			"_slotKey": slot, "_statsDirty": false, "equipment": [],
			"_isSummon": true, "_isCandyBomb": true, "_owner": f,
			"_candyBombDecayPct": float(ps_def.get("decayPct", 20)),
			"_candyBombExplodePct": float(ps_def.get("explodePct", 150)),
		}
		new_bombs.append(bomb)
	for b in new_bombs:
		fighters.append(b)


## 糖果炸弹每回合开始自损 decayPct% maxHp (round-begin; 归零→引爆) — 1:1 PoC candyBombDecay.
func _candy_bomb_decay_tick() -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("_isCandyBomb", false) or not f.get("alive", false):
			continue
		var dl: int = maxi(1, roundi(float(f.get("maxHp", 0)) * float(f.get("_candyBombDecayPct", 20)) / 100.0))
		var r: Dictionary = Damage.apply_raw_damage(f, dl, "true")
		var shown: int = int(r.get("hpLoss", 0)) + int(r.get("shieldAbs", 0))
		if shown > 0:
			_spawn_float_text(i, shown, "damage", "true", false)
			_refresh_slot(i)
		if not f.get("alive", false):
			_detonate_candy_bomb(i)


## 糖果炸弹引爆 (自损/被击杀/主人死 三触发, _candyBombDetonated 守一次) — 1:1 PoC detonateCandyBomb.
##   全敌均摊: total=maxHp×explodePct%; 每只 base=total÷敌数, 实伤=base×魔抗减免 魔法.
func _detonate_candy_bomb(idx: int) -> void:
	if idx < 0 or idx >= fighters.size():
		return
	var bomb: Dictionary = fighters[idx]
	if bomb.get("_candyBombDetonated", false):
		return
	bomb["_candyBombDetonated"] = true
	bomb["alive"] = false
	bomb["hp"] = 0
	_play_candy_boom(idx)
	_play_screen_shake(0.26, 10.0)   # 1:1 PoC cam.shake(260, 0.01)
	var enemies := _alive_enemies_of(bomb)
	if not enemies.is_empty():
		var total: int = maxi(1, roundi(float(bomb.get("maxHp", 0)) * float(bomb.get("_candyBombExplodePct", 150)) / 100.0))
		var base_share: int = maxi(1, roundi(float(total) / float(enemies.size())))
		battle_log.append_text("[color=#ff6bd6]💥 糖果炸弹引爆! 全敌均摊 %d 法术 (每只基数 %d, 过魔抗)[/color]\n" % [total, base_share])
		var owner = bomb.get("_owner", null)
		for e in enemies:
			if not e.get("alive", false):
				continue
			var ti: int = fighters.find(e)
			var dealt: int = maxi(1, roundi(float(base_share) * Damage.calc_dmg_mult(Damage.calc_eff_mr(bomb, e))))
			var r: Dictionary = Damage.apply_raw_damage(e, dealt, "magic")
			var shown: int = int(r.get("hpLoss", 0)) + int(r.get("shieldAbs", 0))
			if shown > 0:
				_spawn_float_text(ti, shown, "damage", "magic", false)
				_refresh_slot(ti)
				if owner is Dictionary:
					battle_stats.record_damage(owner, e, shown, "mag")
			if not e.get("alive", false) and owner is Dictionary:
				battle_stats.record_kill(owner, e)
	_refresh_slot(idx)


## 糖果炸弹引爆 VFX — 1:1 PoC detonateCandyBomb: 28 糖果色 ADD 粒子爆 (#ff6bd6/#ffd93d/#ff5050).
func _play_candy_boom(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var node: Node2D = slot_nodes[idx]
	var avatar = node.get_meta("avatar") if node.has_meta("avatar") else null
	var burst := CPUParticles2D.new()
	burst.position = avatar.position if avatar != null else Vector2(0, -55)
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 28
	burst.lifetime = 0.48
	burst.explosiveness = 1.0
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = 90.0
	burst.initial_velocity_max = 300.0
	burst.scale_amount_curve = _make_decay_curve()
	burst.color = Color(1.0, 0.42, 0.84)   # #ff6bd6 糖果粉
	var bmat := CanvasItemMaterial.new()
	bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	burst.material = bmat
	burst.z_index = 48
	node.add_child(burst)
	get_tree().create_timer(0.7).timeout.connect(burst.queue_free)


## 海盗船 turn-3 召唤 (pirateShipPassive passiveSkill, 装备门控) — 1:1 PoC P29/spawnPirateShip.
##   HP=本体maxHp×1.5, ATK=本体atk, 带「开炮」技能(0.2×ATK物理); 前排优先槽; 每回合顶开炮(_pirate_ship_fire).
func _pirate_ship_spawn_check() -> void:
	if turn != 3:
		return
	var new_ships: Array = []
	for f in fighters:
		var has_ship := false
		for ps in f.get("_passiveSkills", []):
			if ps is Dictionary and ps.get("type", "") == "pirateShipPassive":
				has_ship = true
				break
		if not has_ship or f.get("_pirateShipSummoned", false) or not f.get("alive", false):
			continue
		var side: String = str(f.get("side", "left"))
		var used: Dictionary = {}
		for o in fighters:
			if o.get("side", "") == side and o.get("alive", false):
				used[str(o.get("_slotKey", ""))] = true
		var slot := ""
		for k in ["front-0", "front-1", "front-2", "back-0", "back-1", "back-2"]:   # PoC 前排优先
			if not used.has(k):
				slot = k
				break
		if slot == "":
			battle_log.append_text("[color=#c9a86a]🚢 %s 海盗船: 阵型已满, 无空位召唤[/color]\n" % str(f.get("name", "?")))
			continue
		f["_pirateShipSummoned"] = true
		var ship_hp: int = maxi(1, roundi(float(f.get("maxHp", 0)) * 1.5))
		var ship_atk: int = int(f.get("atk", 0))
		var ship: Dictionary = {
			"id": "pirate_ship", "name": "海盗船", "emoji": "🚢", "rarity": str(f.get("rarity", "C")), "side": side,
			"img": "", "sprite": null,
			"_level": int(f.get("_level", 1)), "_maxEnergy": 0, "_energy": 0,
			"maxHp": ship_hp, "hp": ship_hp, "shield": 0,
			"baseAtk": ship_atk, "baseDef": 0, "baseMr": 0, "atk": ship_atk, "def": 0, "mr": 0,
			"crit": 0.0, "armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
			"passive": null, "passiveUsedThisTurn": false,
			"skills": [{"name": "开炮", "type": "physical", "hits": 1, "power": 0, "atkScale": 0.2, "cd": 0, "cdLeft": 0, "energyCost": 0, "icon": "🚢", "brief": "", "detail": ""}],
			"_passiveSkills": [], "alive": true, "buffs": [], "tags": [],
			"_position": "front" if slot.begins_with("front") else "back",
			"_slotKey": slot, "_statsDirty": false, "equipment": [],
			"_isSummon": true, "_isPirateShip": true, "_owner": f,
		}
		new_ships.append(ship)
	for s in new_ships:
		var idx := _spawn_combatant(s)
		_spawn_passive_text(idx, "🚢 海盗船登场!")
		battle_log.append_text("[color=#c9a86a]🚢 %s 召唤【海盗船】(HP %d / 攻 %d, 每回合开炮)![/color]\n" % [str((s["_owner"] as Dictionary).get("name", "?")), int(s["maxHp"]), int(s["atk"])])


## 海盗船开炮 (round-begin, 在召唤前; 每船对随机敌 0.2×ATK 物理过甲) — 1:1 PoC processPirateShipFire.
func _pirate_ship_fire() -> void:
	for i in range(fighters.size()):
		var ship: Dictionary = fighters[i]
		if not ship.get("_isPirateShip", false) or not ship.get("alive", false):
			continue
		var enemies := _alive_enemies_of(ship)
		if enemies.is_empty():
			continue
		var tgt: Dictionary = enemies[randi() % enemies.size()]
		var ti: int = fighters.find(tgt)
		var dmg: int = roundi(float(ship.get("atk", 0)) * 0.2)
		var final_dmg: int = maxi(1, Damage.calc_damage(ship, tgt, dmg, "physical"))
		var r: Dictionary = Damage.apply_raw_damage(tgt, final_dmg, "physical")
		var shown: int = int(r.get("hpLoss", 0)) + int(r.get("shieldAbs", 0))
		if shown > 0:
			_spawn_float_text(ti, shown, "damage", "physical", false)
			_refresh_slot(ti)
			battle_stats.record_damage(ship, tgt, shown, "phy")
		if not tgt.get("alive", false):
			battle_stats.record_kill(ship, tgt)
		battle_log.append_text("[color=#c9a86a]🚢 海盗船开炮 → %s: %d 物理[/color]\n" % [str(tgt.get("name", "?")), shown])


## 糖果龟登场在己方装备席放糖果罐 (sweetTrap passiveSkill, 装备门控) — 1:1 PoC.
##   c_candy_jar 进 bench_inventory; 点击「打碎」→ _break_candy_jar 按回合掉落. (PoC 己方席; Godot 仅左队有席)
func _spawn_candy_jars() -> void:
	for f in fighters:
		if f.get("side", "") != "left":
			continue
		var has_trap := false
		for ps in f.get("_passiveSkills", []):
			if ps is Dictionary and ps.get("type", "") == "sweetTrap":
				has_trap = true
				break
		if not has_trap or f.get("_candyJarPlaced", false):
			continue
		f["_candyJarPlaced"] = true
		bench_inventory.append("c_candy_jar")
		battle_log.append_text("[color=#ff6bd6]🍬 %s 被动「糖果罐」: 装备席获得糖果罐 (点击「打碎」按回合掉落)[/color]\n" % str(f.get("name", "?")))


## 打碎糖果罐: 移除罐子 → 按当前回合掉落 1-4 件进席 — 1:1 PoC breakCandyJar.
func _break_candy_jar(side: String) -> void:
	if side != "left":
		return
	var idx: int = _bench_idx_of("c_candy_jar")
	if idx < 0:
		return
	bench_inventory.remove_at(idx)
	var loot: Array = _candy_jar_loot(turn)
	var names := ""
	for eid in loot:
		if bench_inventory.size() < 10:
			bench_inventory.append(eid)
		var nm: String = str(DataRegistry.equipment_by_id.get(eid, {}).get("name", eid))
		names += (" + " if names != "" else "") + nm
	_rebuild_bench_rail()
	battle_log.append_text("[color=#ffd93d]🍬 糖果罐打碎 (回合%d) → %s[/color]\n" % [turn, names])
	_show_center_banner("🍬 糖果罐 → %s" % names, "", "#ffd93d", 1.5)


## 糖果罐战利品 (回合越晚越好) — 1:1 PoC generateCandyJarLoot.
func _candy_jar_loot(t: int) -> Array:
	t = maxi(1, t)
	var cons: Array = []
	for ceid in DataRegistry.equipment_by_id:
		if str(DataRegistry.equipment_by_id[ceid].get("category", "")) == "consumable":
			cons.append(ceid)
	var pick_c := func() -> String: return str(cons[randi() % cons.size()]) if not cons.is_empty() else "c_heal"
	var out: Array = []
	if t <= 2:
		out.append("c_heal" if randf() < 0.5 else "c_speed")
	elif t <= 4:
		out.append("c_heal" if randf() < 0.5 else "c_speed")
		out.append("c_bomb")
	elif t <= 6:
		out.append(pick_c.call())
		out.append(EquipmentRuntime.random_loot())
	elif t <= 9:
		out.append(pick_c.call())
		out.append(pick_c.call())
		out.append(EquipmentRuntime.random_loot())
	else:
		out.append(pick_c.call())
		out.append(pick_c.call())
		out.append(EquipmentRuntime.random_loot())
		out.append(EquipmentRuntime.random_loot())
	return out


## 017 不沉之锚: 每回合熔 1 件其它装备进锚 — 携带者获该装备原属性×meltPct (锚星 25/50/1000%) + 销毁该装备.
##   用户确认: 1-5 费(=所有 phase2 装备)都能融. (017 三件事的最后一支, 之前待做)
func _anchor_melt_tick() -> void:
	for fi in range(fighters.size()):
		var f: Dictionary = fighters[fi]
		if not f.get("alive", false):
			continue
		var p2arr: Array = f.get("_p2_equips", [])
		# 找锚 + 锚星
		var anchor_star: int = 0
		for p2 in p2arr:
			if p2 is Dictionary and str(p2.get("id", "")) == "p2eq_017":
				anchor_star = int(p2.get("star", 1))
				break
		if anchor_star <= 0:
			continue
		var melt_pct: float = [0.25, 0.50, 10.0][clampi(anchor_star, 1, 3) - 1]
		# 找 1 件可熔装备 (非锚自身; 任意 cost 1-5 = 所有 phase2 装备)
		var melt_idx: int = -1
		for i in range(p2arr.size()):
			if p2arr[i] is Dictionary and str(p2arr[i].get("id", "")) != "p2eq_017":
				melt_idx = i
				break
		if melt_idx < 0:
			continue   # 无其它装备可熔, 跳过
		var melted: Dictionary = p2arr[melt_idx]
		var melted_id: String = str(melted.get("id", ""))
		var melted_star: int = int(melted.get("star", 1))
		Phase2EquipRuntime.apply_stats(f, melted_id, melted_star, melt_pct)   # 原属性 × meltPct 并入携带者
		StatsRecalc.recalc(f)
		p2arr.remove_at(melt_idx)   # 销毁该装备
		var eq_ids: Array = f.get("_equipped_ids", [])
		for j in range(eq_ids.size() - 1, -1, -1):
			if str(eq_ids[j]) == melted_id:
				eq_ids.remove_at(j)
				break
		var melted_name: String = str(DataRegistry.phase2_equipment_by_id.get(melted_id, {}).get("name", melted_id))
		_spawn_passive_text(fi, "⚓熔%s" % melted_name, "#6bb3ff")
		_refresh_slot(fi)
		battle_log.append_text("[color=#6bb3ff]⚓ %s 不沉之锚熔入【%s%s】(×%d%% 原属性)[/color]\n" % [str(f.get("name", "?")), melted_name, "★".repeat(melted_star), int(melt_pct * 100)])


func _find_summon_slot(owner: Dictionary) -> String:
	var used: Dictionary = {}
	for f in fighters:
		if f.get("side", "") == owner.get("side", "") and f.get("alive", false):
			used[f.get("_slotKey", "")] = true
	var saved: String = owner.get("_savedSummonSlot", "")
	if saved != "" and not used.has(saved):
		return saved
	for k in SUMMON_SLOT_ORDER:
		if not used.has(k):
			return k
	return ""


# 随从独立行动 (side-end / 被指挥): 复用主 AI 选技能+目标, 执行并显示
func _summon_act(idx: int) -> void:
	if idx < 0 or idx >= fighters.size():
		return
	var s: Dictionary = fighters[idx]
	if not s.get("alive", false):
		return
	# 眩晕跳过 (审计#9, 对齐主循环 @1979): side-end 自动行动的随从若被眩晕 → 跳过本次行动并消耗眩晕
	#   (镜 _do_stun_skip: remove_all+反馈), 否则被晕的随从仍在 side-end 照常出手。
	if Buffs.is_stunned(s):
		s["_stunUsed"] = true
		Buffs.remove_all(s, "stun")
		_remove_stun_overhead(idx)   # 出手消耗眩晕 → 撤头顶星星
		_spawn_passive_text(idx, "💫 眩晕")
		await get_tree().create_timer(0.3).timeout
		return
	var choice = SkillHandlers.ai_pick(s, fighters)
	if choice == null:
		return
	var skill: Dictionary = s["skills"][choice["skill_idx"]]
	var target: Dictionary = fighters[choice["target_idx"]]
	var result: Dictionary = SkillHandlers.execute(s, target, fighters, skill)
	if skill.get("cd", 0) > 0:
		skill["cdLeft"] = skill["cd"]
	var effects: Array = result.get("effects", [])
	for eff in effects:
		var ti: int = eff["target_idx"]
		if eff.get("kind", "") == "passive":
			_spawn_passive_text(ti, eff.get("label", ""))
		else:
			_spawn_float_text(ti, eff.get("value", 0), eff["kind"], eff.get("dmg_type", "physical"), eff.get("is_crit", false))
		_refresh_slot(ti)
	if result.get("relayout", false):
		_relayout_slots()
	for eff in effects:
		var ti2: int = eff["target_idx"]
		if not fighters[ti2].get("alive", false) and eff.get("kind", "") == "damage":
			await _play_death(ti2)
	await get_tree().create_timer(0.25).timeout


# 级联死亡: 主人阵亡 → 随从一同倒下 (PoC processSummonDeath)
func _check_summon_cascade() -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("_isSummon", false) and f.get("alive", false):
			var owner = f.get("_owner", null)
			if owner is Dictionary and not owner.get("alive", false):
				if f.get("_isCandyBomb", false):
					_detonate_candy_bomb(i)   # 糖果炸弹: 主人阵亡→立即引爆 (非一同阵亡) 1:1 PoC
					continue
				f["alive"] = false
				f["hp"] = 0
				await _play_death(i)
				battle_log.append_text("  [color=#ff6b6b]☠ 主人阵亡, 随从 %s 一同阵亡[/color]\n" % f.get("name", "?"))


func _is_boss_side(side: String) -> bool:
	# 1:1 PoC isBossSide (BattleScene.ts:2135): boss/boss-pick 模式 或 深海 boss 关; 恒右侧。
	#   旧版只认 dungeon → 指定Boss/Boss模式 boss 只动 1 次 (输出腰斩)。补 boss/boss-pick。
	return side == "right" and ((GameState.mode in ["boss", "boss-pick"]) \
		or (GameState.mode == "dungeon" and GameState.is_dungeon_boss_stage()))


# 眩晕跳过 (消耗一次行动) — 从 _take_turn 提出, 便于 boss 整回合跳两次
func _do_stun_skip(idx: int) -> void:
	var actor: Dictionary = fighters[idx]
	actor["_stunUsed"] = true
	Buffs.remove_all(actor, "stun")
	_remove_stun_overhead(idx)   # 出手消耗眩晕 → 撤头顶星星
	_spawn_passive_text(idx, "💫 眩晕")
	battle_log.append_text("[color=#c9a0ff]💫 %s 被眩晕, 跳过回合[/color]\n" % actor.get("name", "?"))
	await get_tree().create_timer(0.9).timeout   # 1:1 PoC 眩晕跳过 delayedCall(900) (BattleScene.ts:2324) — 原0.4


## 混乱(confused): 不能选技能(_skill_ready 已全置灰) → 强制 skill 0(基础) 攻击随机敌人 (用户新状态)
func _do_confused_action(idx: int) -> void:
	if idx < 0 or idx >= fighters.size():
		return
	var actor: Dictionary = fighters[idx]
	_spawn_passive_text(idx, "😵 混乱")
	if is_instance_valid(battle_log):
		battle_log.append_text("[color=#c39bd3]😵 %s 陷入混乱, 胡乱攻击![/color]\n" % actor.get("name", "?"))
	var enemies: Array = _alive_enemies_of(actor)
	if enemies.is_empty():
		await get_tree().create_timer(0.3).timeout
		return
	await _take_turn(idx, 0, fighters.find(enemies[randi() % enemies.size()]))


# ── 熔岩龟变身状态机 (1:1 PoC processLavaRage BattleScene.ts:6065-6213) ──
func _process_lava_rage(idx: int) -> void:
	var f: Dictionary = fighters[idx]
	if not f.get("alive", false):
		return
	var p = f.get("passive", null)
	if not (p is Dictionary) or p.get("type", "") != "lavaRage":
		return
	# 已变身: 每【回合】倒计时 -1 (turn 闸防 boss 双减), 归 0 还原
	if f.get("_lavaTransformed", false):
		if int(f.get("_lastLavaTransformTickTurn", -1)) == turn:
			return
		f["_lastLavaTransformTickTurn"] = turn
		var t2: int = int(f.get("_lavaTransformTurns", 0)) - 1
		f["_lavaTransformTurns"] = t2
		if t2 <= 0:
			f["_lavaTransformed"] = false
			f["_lavaSpent"] = false   # 允许下次变身
			f["_lavaRage"] = 0
			var om: float = f.get("maxHp", 0)
			f["maxHp"] = maxi(1, int(om) - int(f.get("_lavaHpGain", 0)))
			f["hp"] = maxi(1, roundi(float(f.get("hp", 0)) * f["maxHp"] / maxf(1.0, om)))
			f["baseAtk"] = f.get("baseAtk", 0) - int(f.get("_lavaAtkGain", 0)); f["atk"] = f["baseAtk"]
			f["baseDef"] = f.get("baseDef", 0) - int(f.get("_lavaDefGain", 0)); f["def"] = f["baseDef"]
			f["baseMr"] = maxi(0, int(f.get("baseMr", f.get("baseDef", 0))) - int(f.get("_lavaMrGain", 0))); f["mr"] = f["baseMr"]
			if f.has("_lavaSmallSkills"):
				f["skills"] = f["_lavaSmallSkills"]
			if f.has("_lavaSmallName"):
				f["name"] = f["_lavaSmallName"]
			StatsRecalc.recalc(f)
			# J6: 还原小形态立绘 (1:1 PoC swapPetTexture 'pet-body-lava', BattleScene.ts:6100)
			_swap_avatar(idx, str(f.get("id", "lava")))
			_refresh_slot(idx)
			# 1:1 PoC(BattleScene.ts:6086-6104): 火山形态恢复只 log 不飘"恢复小形态"文字 (原自创)
			battle_log.append_text("[color=#ff9966]🌋 %s 火山形态结束[/color]\n" % f.get("name", "?"))
		return
	# 未变身: 怒气满则变身
	if not f.get("_lavaRageReady", false) or f.get("_lavaSpent", false):
		return
	f["_lavaRage"] = 0
	f["_lavaRageReady"] = false
	f["_lavaSpent"] = true
	f["_lavaTransformed"] = true
	f["_lavaTransformTurns"] = int(p.get("transformDuration", 6))
	f["_lavaSmallSkills"] = f.get("skills", [])
	f["_lavaSmallName"] = f.get("name", "")
	var pre_atk: float = f.get("atk", 0)
	var hp_gain: int = roundi(pre_atk * p.get("transformHpScale", 2.5))
	var atk_gain: int = roundi(pre_atk * p.get("transformAtkScale", 0.2))
	var def_gain: int = roundi(pre_atk * p.get("transformDefScale", 0.2))
	var mr_gain: int = roundi(pre_atk * p.get("transformMrScale", 0.2))
	f["_lavaHpGain"] = hp_gain; f["_lavaAtkGain"] = atk_gain; f["_lavaDefGain"] = def_gain; f["_lavaMrGain"] = mr_gain
	var om2: float = f.get("maxHp", 0)
	f["maxHp"] = int(om2) + hp_gain
	f["hp"] = roundi(float(f.get("hp", 0)) * f["maxHp"] / maxf(1.0, om2))
	f["baseAtk"] = f.get("baseAtk", 0) + atk_gain; f["atk"] = f["baseAtk"]
	f["baseDef"] = f.get("baseDef", 0) + def_gain; f["def"] = f["baseDef"]
	f["baseMr"] = int(f.get("baseMr", f.get("baseDef", 0))) + mr_gain; f["mr"] = f["baseMr"]
	# 切 volcanoSkills 按 _equippedIdxs 配对 (滤 passiveSkill)
	var volc = f.get("_volcanoSkills", [])
	if volc is Array and not (volc as Array).is_empty():
		var eq: Array = f.get("_equippedIdxs", [0, 1, 2])
		var paired: Array = []
		for i in eq:
			if i >= 0 and i < volc.size() and not volc[i].get("passiveSkill", false):
				var sc: Dictionary = volc[i].duplicate(true); sc["cdLeft"] = 0; paired.append(sc)
		if paired.is_empty():
			for s in volc:
				if not s.get("passiveSkill", false):
					var sc2: Dictionary = s.duplicate(true); sc2["cdLeft"] = 0; paired.append(sc2)
					if paired.size() >= 3:
						break
		f["skills"] = paired
	f["name"] = "火山龟"
	StatsRecalc.recalc(f)
	_refresh_slot(idx)
	# J6: 换火山形态立绘 (1:1 PoC swapPetTexture 'pet-form-volcano', BattleScene.ts:6153)
	_swap_avatar(idx, "volcano")
	# 变身 VFX (橙闪 + 飘字, 与 PoC 占位一致)
	_flash_transform(idx, Color(1.0, 0.4, 0.0))
	_spawn_passive_text(idx, "🌋 变身!")
	# 换形羁绊: 变身后护盾 (+tier3 首次 ATK)
	var lshift := Synergies.apply_shift(f)
	if lshift["shieldAdded"] > 0:
		_spawn_passive_text(idx, "+%d🛡" % lshift["shieldAdded"])
	if lshift["atkAdded"] > 0:
		_spawn_passive_text(idx, "换形 +%dATK" % lshift["atkAdded"], "#ff9d5c")   # 1:1 PoC grantShiftSynergy float (BattleScene.ts:6029) — 原漏
	battle_log.append_text("[color=#ff6600]🌋 %s 变身! +%dHP +%dATK +%dDEF +%dMR (%d 回合)[/color]\n" % [f.get("name", "?"), hp_gain, atk_gain, def_gain, mr_gain, f["_lavaTransformTurns"]])
	# 变身 AOE: round(atk×1.2) magic 全敌 + burn + 每烧敌回 8% 已损
	var aoe_dmg: int = roundi(f.get("atk", 0) * p.get("transformAoeDmgScale", 1.2))
	for j in range(fighters.size()):
		var e: Dictionary = fighters[j]
		if e.get("side", "") == f.get("side", "") or not e.get("alive", false):
			continue
		var d: int = Damage.calc_damage(f, e, aoe_dmg, "magic")
		var r: Dictionary = Damage.apply_raw_damage(e, d, "magic")
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		if shown > 0:
			_spawn_dot_text(j, shown, "dot-dmg")
			_refresh_slot(j)
		var e_burn_immune = e.get("_burnImmune", false)
		var ep = e.get("passive", null)
		if ep is Dictionary and ep.get("burnImmune", false):
			e_burn_immune = true
		if not e_burn_immune:
			Dot.apply_stacks(e, "burn", Dot.default_burn_stacks(f))
			var lost: int = int(f.get("maxHp", 0)) - int(f.get("hp", 0))
			var bh: int = roundi(lost * 0.08)
			if bh > 0:
				f["hp"] = mini(int(f.get("maxHp", 0)), int(f.get("hp", 0)) + bh)
		if not e.get("alive", false):
			await _play_death(j)
	_refresh_slot(idx)


# 攻击端怒气累积 (PoC passive-triggers: 熔岩龟造成伤害 +rageDmgPct%)
func _accumulate_attack_rage(actor: Dictionary, dmg: int) -> void:
	if dmg <= 0:
		return
	var p = actor.get("passive", null)
	if not (p is Dictionary) or p.get("type", "") != "lavaRage":
		return
	if actor.get("_lavaSpent", false) or actor.get("_lavaTransformed", false):
		return
	var rmax: int = p.get("rageMax", 100)
	var nxt: int = mini(rmax, int(actor.get("_lavaRage", 0)) + roundi(dmg * p.get("rageDmgPct", 25) / 100.0))
	actor["_lavaRage"] = nxt
	if nxt >= rmax:
		actor["_lavaRageReady"] = true


# 反伤/反击落地 helper (子伤害走 apply_raw_damage 不回流 on-hit 链, 防递归)
func _reflect_to(victim: Dictionary, dmg: int, dmg_type: String, victim_idx: int, bonus_effects: Array) -> void:
	if not victim.get("alive", false) or dmg <= 0:
		return
	var r: Dictionary = Damage.apply_raw_damage(victim, dmg, dmg_type)
	var sh: int = r["hpLoss"] + r["shieldAbs"]
	if sh > 0:
		bonus_effects.append({"target_idx": victim_idx, "value": sh, "kind": "damage", "dmg_type": dmg_type, "is_crit": false})


# on-hit 链 A 组 (1:1 PoC passive-triggers.ts, 仅自洽项; 依赖墨迹/经济/觉醒的留待后批)
func _on_hit_chain(attacker: Dictionary, target: Dictionary, dmg: int, _dmg_type: String, attacker_idx: int, ti: int, bonus_effects: Array, hits: int = 1) -> void:
	var same_side: bool = attacker.get("side", "") == target.get("side", "")
	var ap = attacker.get("passive", null)
	var seg_hits: int = maxi(1, hits)
	# 黑礁猎团 8档处决: 黑礁队攻击猎物, 命中后其 HP<20% → 直接处决 (蛋/不沉之锚免疫斩杀的不处决)
	if int(attacker.get("_huntTier", 0)) >= 3 and target.get("_huntTarget", false) and target.get("alive", false) \
			and not target.get("_eggImmune", false) and not target.get("_p2AnchorImmune", false) \
			and float(target.get("hp", 0)) < float(target.get("maxHp", 1)) * 0.2:
		target["hp"] = 0
		target["alive"] = false
		_play_execute_flash(ti)   # 羁绊·黑礁猎团 8档处决: 斩首白闪 (ghost-touch + 强白闪 + 小震)
	# 极地小队[冰封]学派: 攻击者带 _iceFreezeChance → X% 冻结目标(stun 1回合, 无法行动)。
	#   防永冻: 目标已 stun 或在免疫窗内不再冻; 冻结后设 1 回合免疫窗。
	var ice_fc: float = float(attacker.get("_iceFreezeChance", 0.0))
	if ice_fc > 0.0 and not same_side and target.get("alive", false) and not target.get("_isEgg", false) and not Buffs.is_stunned(target) and int(target.get("_iceFreezeImmuneTurn", -99)) < turn and randf() < ice_fc:
		Buffs.add(target, "stun", 1, 2, "overwrite")
		target["_stunUsed"] = false
		target["_iceFreezeImmuneTurn"] = turn + 2
		if ice_fc >= 0.40:   # 9档(冻结率0.40)易碎: 冻结时标记目标, 被冻/眩晕时受伤 +25% (damage.gd 消费)
			target["_iceShatter"] = true
		_play_freeze_flash(ti)   # 羁绊·极地小队 冰封: 冻结目标处青蓝冰罩脉冲 (复用几何+tint, 无新资源)
		if is_instance_valid(battle_log):
			battle_log.append_text("[color=#7fdfff]❄ %s 冻结了 %s[/color]\n" % [str(attacker.get("name","?")), str(target.get("name","?"))])
	# 极地小队 6档僵硬: 每段攻击给目标 +seg_hits 层僵硬(max20, 每层 -2%攻; StatsRecalc 消费 _stiffnessStacks)
	if ice_fc >= 0.25 and not same_side and target.get("alive", false) and not target.get("_isEgg", false):
		target["_stiffnessStacks"] = mini(20, int(target.get("_stiffnessStacks", 0)) + seg_hits)
		target["_stiffnessExpireTurn"] = turn + 4   # 修(审计): 持续4回合, 叠加刷新全部时长 (原永不消失=比设计强)
		StatsRecalc.recalc(target)
	# 水晶结晶: attacker crystalResonance 命中 → target 叠层, 满 max 引爆 maxHp×hpPct% 魔法 + mrDown.
	#   PoC passive-triggers.ts:214-216 在 triggerOnHitEffects 内 → 每段命中各叠 1 层 (per-hit).
	if ap is Dictionary and ap.get("type", "") == "crystalResonance" and target.get("alive", false) and not same_side:
		for _ch in range(seg_hits):
			if not target.get("alive", false):
				break
			var nxtc: int = int(target.get("_crystallize", 0)) + 1
			if nxtc < int(ap.get("crystallizeMax", 4)):
				target["_crystallize"] = nxtc
			else:
				target["_crystallize"] = 0
				_play_screen_shake(0.30, 11.0)   # 1:1 PoC spawnCrystalDetonate cam.shake(300, 0.011) — 原引爆无震屏
				_flash_hit(ti)                    # 引爆中心 avatar 白脉冲
				_play_crystal_detonate(ti)        # 1:1 PoC spawnCrystalDetonate: 白闪圈 + 双层紫环 + 46碎晶粒子
				var det: int = Damage.calc_damage(attacker, target, roundi(target.get("maxHp", 0) * ap.get("crystallizeHpPct", 19) / 100.0), "magic")
				var rc: Dictionary = Damage.apply_raw_damage(target, det, "magic")
				var shc: int = rc["hpLoss"] + rc["shieldAbs"]
				if shc > 0:
					bonus_effects.append({"target_idx": ti, "value": shc, "kind": "damage", "dmg_type": "magic", "is_crit": false})
				Buffs.add(target, "mrDown", ap.get("crystallizeMrDown", 20), int(ap.get("crystallizeMrTurns", 3)) + 1, "overwrite")
				StatsRecalc.recalc(target)
	if not target.get("alive", false):
		return
	var tp = target.get("passive", null)
	# ── target 受击触发 (反伤/反击需攻击者活, 跨阵营) ──
	if attacker.get("alive", false) and not same_side and dmg > 0:
		# reflect buff (round(dmg×value%), 过攻击者护甲)
		var rb = Buffs.find(target, "reflect")
		if rb != null and int(rb.get("value", 0)) > 0:
			_reflect_to(attacker, maxi(1, Damage.calc_damage(target, attacker, roundi(dmg * rb.get("value", 0) / 100.0), "physical")), "physical", attacker_idx, bonus_effects)
		# trap buff (定值×attacker.def减免, 消耗)
		var trb = Buffs.find(target, "trap")
		if trb != null:
			_reflect_to(attacker, maxi(1, roundi(trb.get("value", 0) * Damage.calc_dmg_mult(attacker.get("def", 0)))), "physical", attacker_idx, bonus_effects)
			Buffs.remove_all(target, "trap")
		# counter buff (定值魔法, 需 target 有盾; lightningStorm 额外叠电击)
		var cb = Buffs.find(target, "counter")
		if cb != null and int(target.get("shield", 0)) > 0:
			_reflect_to(attacker, int(cb.get("value", 0)), "magic", attacker_idx, bonus_effects)
			if tp is Dictionary and tp.get("type", "") == "lightningStorm":
				attacker["_shockStacks"] = int(attacker.get("_shockStacks", 0)) + 1
		# 海胆反伤 e_urchin (_equipReflect%, 过攻击者护甲)
		if int(target.get("_equipReflect", 0)) > 0:
			var er: int = roundi(dmg * target.get("_equipReflect", 0) / 100.0)
			if er > 0:
				_reflect_to(attacker, maxi(1, Damage.calc_damage(target, attacker, er, "physical")), "physical", attacker_idx, bonus_effects)
		# 二阶段装备 reflectPct 反伤 (013炙烤海胆=物理过甲 / 015荆棘海胆=真伤+流血)
		if float(target.get("reflectPct", 0.0)) > 0.0:
			var p2r: int = roundi(dmg * float(target.get("reflectPct", 0.0)) / 100.0)
			if p2r > 0:
				if target.get("_p2ReflectTrue", false):
					_reflect_to(attacker, p2r, "true", attacker_idx, bonus_effects)   # 015: 真伤(不过甲)
					var p2bleed: int = roundi(float(target.get("_p2ReflectBleed", 0.0)))
					if p2bleed > 0:
						Dot.apply_stacks(attacker, "bleed", p2bleed)
					# 015荆棘海胆 反伤VFX: 攻击者处荆棘刺 (墨绿刺环) + 血滴溅射 (反伤真伤+流血). 直接渲染, 无需marker.
					_play_aoe_ring(attacker_idx, Color(0.20, 0.55, 0.18, 0.6))   # 荆棘墨绿刺扩散环
					_play_blood_splatter(attacker_idx)                          # 反伤流血血滴
				else:
					# 013炙烤海胆: 物理"过甲" — 反伤不吃攻击者护甲 (规格 PHASE2-EQUIP-SHIELD-SPEC.md "物理过甲").
					#   直接走 _reflect_to(physical) → apply_raw_damage 不减甲; 原走 calc_damage 会吃 attacker.def 被砍成个位数.
					_reflect_to(attacker, p2r, "physical", attacker_idx, bonus_effects)
					# 013 反伤VFX: 攻击者处橙红小溅射环 + 血滴 (复用现成几何, 无新资源), 让反伤看得见.
					_play_aoe_ring(attacker_idx, Color(0.92, 0.40, 0.12, 0.55))   # 炙烤橙红扩散环
					_play_blood_splatter(attacker_idx)
		# 圣甲议会[圣盾]学派: 圣光护盾存在时(_holyShield 携带者且有盾), 反击攻击者 2×(1+0.5×件数) 点真伤
		if target.get("_holyShield", false) and int(target.get("shield", 0)) > 0:
			var holy_r: int = roundi(2.0 * (1.0 + 0.5 * int(target.get("_holyCount", 3))))
			if holy_r > 0:
				_reflect_to(attacker, holy_r, "true", attacker_idx, bonus_effects)
				# 圣盾反击演出: 攻击者处放盾击弧+白闪 (复用 basic-shieldbash-arc 既有帧, 无新资源)
				_play_vfx_at_slot("basic-shieldbash-arc", attacker_idx, 0.9)
				_flash_hit(attacker_idx)
		# 熔岩盾反击 (phoenixShield): 持 _lavaShieldVal → 反击 round(target.atk×counter) 魔法
		if int(target.get("_lavaShieldVal", 0)) > 0 and target.get("_lavaShieldCounter", 0.0) > 0:
			_reflect_to(attacker, roundi(target.get("atk", 0) * target.get("_lavaShieldCounter", 0.14)), "magic", attacker_idx, bonus_effects)
		# 墨记 inkMark: 墨迹是【目标 debuff】— 任意非同侧 attacker 命中带墨敌都放大 round(dmg×层×5%)
		#   (原 bug: 限 ap.type==inkMark = 只线条龟本体命中才触发 → 队友打带墨敌没吃放大; PoC 在 triggerOnHitEffects 对任意 attacker 触发)
		if not same_side and int(target.get("_inkStacks", 0)) > 0:
			var ink_type := "true" if target.get("_inkRapidActive", false) else "magic"
			var ib: int = roundi(dmg * int(target.get("_inkStacks", 0)) * 0.05)
			if ink_type == "magic":
				ib = Damage.calc_damage(attacker, target, ib, "magic")
			_reflect_to(target, ib, ink_type, ti, bonus_effects)
		# counterAttack 被动 (%, 直接扣 hp 不走减免) — PoC passive-triggers.ts:546-560 在 triggerOnHitEffects
		#   内 → 每段命中各 roll 一次概率反击 (per-hit 概率).
		if tp is Dictionary and tp.get("type", "") == "counterAttack":
			for _xh in range(seg_hits):
				if not attacker.get("alive", false):
					break
				if randf() * 100.0 < tp.get("pct", 0):
					var cd: int = roundi(target.get("baseAtk", 0) * 0.5)
					var bf: int = attacker.get("hp", 0)
					attacker["hp"] = maxi(0, bf - cd)
					if int(attacker["hp"]) <= 0:
						attacker["alive"] = false
					if bf - int(attacker["hp"]) > 0:
						bonus_effects.append({"target_idx": attacker_idx, "value": bf - int(attacker["hp"]), "kind": "damage", "dmg_type": "physical", "is_crit": false})
						# 反击纯VFX(无文字): 攻击者处反击弧 (伤害数字已够看出反击, 用户要求不加文字标) — 需F5
						_play_vfx_at_slot("basic-shieldbash-arc", attacker_idx, 0.8)
	# ── target 受击得益 (盾/层) ──
	if tp is Dictionary and tp.get("type", "") == "shieldOnHit" and not target.get("_shieldOnHitUsedTurn", false):
		var amt: int = tp.get("amount", roundi(target.get("maxHp", 0) * 0.05))
		amt = Buffs.grant_shield(target, amt)
		target["_shieldOnHitUsedTurn"] = true
		bonus_effects.append({"target_idx": ti, "value": amt, "kind": "shield"})
	if tp is Dictionary and tp.get("type", "") == "twoHeadVitality" and not target.get("_twoHeadHalfTriggered", false) \
			and target.get("maxHp", 0) > 0 and float(target.get("hp", 0)) / float(target.get("maxHp", 1)) < 0.5:
		target["_twoHeadHalfTriggered"] = true
		var s2: int = roundi(target.get("maxHp", 0) * tp.get("shieldPct", 20) / 100.0)
		s2 = Buffs.grant_shield(target, s2)
		bonus_effects.append({"target_idx": ti, "value": s2, "kind": "shield"})
	# bambooCharged: 受击 +1 层 (cap) — PoC passive-triggers.ts:237-241 每段命中 +1 (per-hit)
	if tp is Dictionary and tp.get("type", "") == "bambooCharged":
		for _bah in range(seg_hits):
			target["_bambooStacks"] = mini(tp.get("maxStacks", 5), int(target.get("_bambooStacks", 0)) + 1)
	# bubbleBind buff: 每段永久 -perHitLoss 甲/抗 (cap) — PoC passive-triggers.ts:300-316 每段命中各减一次 (per-hit, lossUsed 累积封顶)
	var bind = Buffs.find(target, "bubbleBind")
	if bind != null and dmg > 0:
		var per: int = int(bind.get("perHitLoss", 0))
		if per > 0:
			for _bbh in range(seg_hits):
				var loss: int = mini(per, int(bind.get("lossCap", 30)) - int(bind.get("lossUsed", 0)))
				if loss <= 0:
					break
				target["baseDef"] = target.get("baseDef", 0) - loss; target["def"] = target.get("def", 0) - loss
				target["baseMr"] = int(target.get("baseMr", target.get("baseDef", 0))) - loss; target["mr"] = target.get("mr", 0) - loss
				bind["lossUsed"] = int(bind.get("lossUsed", 0)) + loss
	# ── attacker-side 装备/被动追打 (概率类: 每段命中各 roll 一次, 1:1 PoC per-hit) ──
	if not same_side and target.get("alive", false):
		# e_jelly 眩晕 — PoC passive-triggers.ts:439-452 每段 roll 一次 (命中已有 stun 则不再叠)
		if int(attacker.get("_equipStun", 0)) > 0:
			for _sh in range(seg_hits):
				if Buffs.has(target, "stun"):
					break
				if randf() * 100.0 < attacker.get("_equipStun", 0):
					Buffs.add(target, "stun", 1, 2, "ignore"); target["_stunUsed"] = false
					bonus_effects.append({"target_idx": ti, "kind": "passive", "label": "❄️眩晕"})
		# e_octo 多击 _equipMultiHit — PoC passive-triggers.ts:454-464 每段 roll 一次
		if int(attacker.get("_equipMultiHit", 0)) > 0:
			for _mh in range(seg_hits):
				if not target.get("alive", false):
					break
				if randf() * 100.0 < attacker.get("_equipMultiHit", 0):
					var rmh: Dictionary = Damage.apply_raw_damage(target, Damage.calc_damage(attacker, target, roundi(attacker.get("atk", 0) * 0.5), "physical"), "physical")
					var shm: int = rmh["hpLoss"] + rmh["shieldAbs"]
					if shm > 0:
						bonus_effects.append({"target_idx": ti, "value": shm, "kind": "damage", "dmg_type": "physical", "is_crit": false})
		# 赌徒连击 gamblerMultiHit (每段命中各起一条递减追打链, chance ×0.8) — PoC passive-triggers.ts:565-586 每段一次
		if ap is Dictionary and ap.get("type", "") == "gamblerMultiHit":
			for _gh in range(seg_hits):
				var chance: float = ap.get("chance", 0) + attacker.get("_multiBonus", 0)
				var safety: int = 0
				while target.get("alive", false) and attacker.get("alive", false) and randf() * 100.0 < chance and safety < 10:
					safety += 1
					var isc: bool = randf() < attacker.get("crit", 0.0)
					var gb: int = Damage.calc_damage(attacker, target, roundi(attacker.get("atk", 0) * ap.get("dmgScale", 0.5)) * (1.5 if isc else 1.0), "physical")
					var rgb: Dictionary = Damage.apply_raw_damage(target, gb, "physical")
					var shg: int = rgb["hpLoss"] + rgb["shieldAbs"]
					if shg > 0:
						bonus_effects.append({"target_idx": ti, "value": shg, "kind": "damage", "dmg_type": "physical", "is_crit": isc})
					chance *= 0.8
				if not target.get("alive", false):
					break


# inkLink 分流回调 (Damage.ink_transfer_hook): 给被传递的 partner 飘字 + 战绩归功线条龟 (1:1 PoC BattleScene.ts:775-786)
func _on_ink_transfer(partner: Dictionary, shown: int, dmg_type: String, owner) -> void:
	if shown <= 0:
		return
	var pi: int = fighters.find(partner)
	if pi < 0:
		return
	_spawn_float_text(pi, shown, "damage", dmg_type, false)
	_refresh_slot(pi)
	if owner is Dictionary:
		battle_stats.record_damage(owner, partner, shown, "tru" if dmg_type == "true" else "mag")
		if not partner.get("alive", false):
			battle_stats.record_kill(owner, partner)


# 变身演出 — 1:1 PoC BattleScene.ts:6155-6169: 震屏 + 全屏橙闪 + 28 粒子 ADD 爆 + avatar 染色脉冲。
func _flash_transform(idx: int, col: Color) -> void:
	if idx < 0 or idx >= slot_nodes.size():
		return
	var node: Node2D = slot_nodes[idx]
	var avatar = node.get_meta("avatar") if node.has_meta("avatar") else null
	# avatar 染色脉冲 (原占位保留)
	if avatar != null:
		var tw := create_tween()
		tw.tween_property(avatar, "modulate", col, 0.12)
		tw.tween_property(avatar, "modulate", Color.WHITE, 0.3)
	# 震屏 (PoC cameras.shake(500, 0.02); Godot strength≈×1000 → 20px, 0.5s)
	_play_screen_shake(0.5, 20.0)
	# 全屏橙闪 0xff6600 α0.45 → 0, 500ms (PoC add.rectangle + tween alpha; 普通混合非 ADD)
	if is_instance_valid(fx_layer):
		var flash := ColorRect.new()
		flash.color = Color(1.0, 0.4, 0.0, 0.45)   # 0xff6600
		flash.size = get_viewport().get_visible_rect().size   # 盖满真实视口 (ENVELOP 下 > 1280×720)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx_layer.add_child(flash)
		var ftw := flash.create_tween()
		ftw.tween_property(flash, "color:a", 0.0, 0.5)
		ftw.tween_callback(flash.queue_free)
	# 28 粒子 ADD 爆 (PoC speed100-400 scale1.5→0 tint橙琥珀 quantity28 blendMode ADD lifespan800)
	var burst := CPUParticles2D.new()
	burst.position = avatar.position if avatar != null else Vector2(0, -40)
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 28
	burst.lifetime = 0.8
	burst.explosiveness = 1.0
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0                 # 全方向爆
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = 100.0
	burst.initial_velocity_max = 400.0
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 1.5
	burst.scale_amount_curve = _make_decay_curve()   # 1.5 → 0
	burst.color = Color(1.0, 0.53, 0.2)   # 琥珀橙 (PoC tint 中段 0xff8800)
	var bmat := CanvasItemMaterial.new()
	bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	burst.material = bmat
	burst.z_index = 45
	node.add_child(burst)
	get_tree().create_timer(1.2).timeout.connect(burst.queue_free)


# 水晶结晶引爆 VFX — 1:1 PoC spawnCrystalDetonate(vfx/skills.ts:560): 中心白闪 + 双层扩散紫环 + 46 碎晶 ADD 粒子。
#   震屏在调用点已放 (_play_screen_shake 0.30,11 = PoC cam.shake 300,.011)。比例/色需 F5 眼验。
func _play_crystal_detonate(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var node: Node2D = slot_nodes[idx]
	var avatar = node.get_meta("avatar") if node.has_meta("avatar") else null
	var pos: Vector2 = avatar.position if avatar != null else Vector2(0, -60)
	# 中心白闪 (PoC circle r30 #fff α0.9 → scale 2.2 α0 200ms)
	var flash := Polygon2D.new()
	flash.polygon = _circle_points(30.0)
	flash.color = Color(1, 1, 1, 0.9)
	flash.position = pos
	flash.z_index = 48
	node.add_child(flash)
	var ft := flash.create_tween().set_parallel(true)
	ft.tween_property(flash, "scale", Vector2(2.2, 2.2), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ft.tween_property(flash, "modulate:a", 0.0, 0.2)
	get_tree().create_timer(0.25).timeout.connect(flash.queue_free)
	# 双层扩散紫环 (PoC ring r14 stroke4 #d8b0ff→scale8 460ms / ring2 r10 stroke3 #b478ff→scale5 320ms delay80)
	_spawn_crystal_ring(node, pos, 14.0, 4.0, Color(0.847, 0.690, 1.0, 0.9), 8.0, 0.46, 0.0)
	_spawn_crystal_ring(node, pos, 10.0, 3.0, Color(0.706, 0.471, 1.0, 0.7), 5.0, 0.32, 0.08)
	# 46 碎晶 ADD 粒子 (PoC speed 120-360 scale1.5→0 tint 紫/白 quantity46 lifespan520)
	var burst := CPUParticles2D.new()
	burst.position = pos
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 46
	burst.lifetime = 0.52
	burst.explosiveness = 1.0
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = 120.0
	burst.initial_velocity_max = 360.0
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 1.5
	burst.scale_amount_curve = _make_decay_curve()
	burst.color = Color(0.706, 0.471, 1.0)   # #b478ff 紫
	var bmat := CanvasItemMaterial.new()
	bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	burst.material = bmat
	burst.z_index = 47
	node.add_child(burst)
	get_tree().create_timer(0.9).timeout.connect(burst.queue_free)


# 扩散圆环助手 (Line2D 圆 scale 1→end + 淡出); delay 秒后起。
func _spawn_crystal_ring(parent: Node2D, pos: Vector2, radius: float, width: float, col: Color, end_scale: float, dur: float, delay: float) -> void:
	var ring := Line2D.new()
	ring.points = _circle_points(radius)
	ring.width = width
	ring.default_color = col
	ring.position = pos
	ring.z_index = 46
	parent.add_child(ring)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector2(end_scale, end_scale), dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, dur).set_delay(delay)
	get_tree().create_timer(delay + dur + 0.05).timeout.connect(ring.queue_free)


# 圆周采样点 (VFX 圆环/圆面用; 末点=首点闭合)
func _circle_points(radius: float, segments: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


# 直线飞镖/子弹 VFX — 1:1 PoC fireStraightProjectile(vfx/skills.ts:522): Sprite2D 旋转指向目标, 线性飞行 dur 落地销毁.
func _fire_projectile(from_idx: int, to_idx: int, tex_path: String, size: float, dur: float) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	if not ResourceLoader.exists(tex_path):
		return
	# home_pos 兜底取 .position (对齐 _play_slash_at): 防个别 slot(召唤物/边缘)缺 meta 时 get_meta 报错中断画弹。
	var from_pos: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -55)
	var to_pos: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -55)
	var proj := Sprite2D.new()
	proj.texture = load(tex_path)
	proj.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 1:1 PoC NEAREST 像素滤波
	var th: float = proj.texture.get_height()
	if th > 0:
		proj.scale = Vector2(size / th, size / th)   # 等比缩放 height≈size (PoC setDisplaySize)
	proj.position = from_pos
	proj.rotation = (to_pos - from_pos).angle()   # 朝向目标 (PoC setRotation atan2)
	# z 须高过龟身: 龟身 z_index=int(home.y) 最深排达 ~497 (y=69%×720). 原 48 远低于龟身 → 弹珠在飞行途经的
	#   敌龟立绘【背后】被完全遮住 (子弹画了但看不见, =048/049/050/052/056/058 全枪系/弹/弩通病). 抬到 600 盖过全龟。
	proj.z_index = 600
	slots_root.add_child(proj)
	var tw := create_tween()
	tw.tween_property(proj, "position", to_pos, dur).set_trans(Tween.TRANS_LINEAR)
	await tw.finished
	if is_instance_valid(proj):
		proj.queue_free()


## 霰弹贝 053 扇形弹幕 VFX (装备VFX视觉规格.md) — 从携带者中心 40°扇形(-20°~+20°等分N份)发 N 发弹珠飞向敌方,
##   + 枪口火焰开火特效(CPUParticles 火光, ADD)。复用 revolver-bullet 弹珠贴图; 纯演出 fire-and-forget。
func _play_shotgun_blast(from_idx: int, pellets: int) -> void:
	if from_idx < 0 or from_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[from_idx]):
		return
	pellets = maxi(1, pellets)
	var node: Node2D = slot_nodes[from_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	# 龟身中心 (世界坐标, 与 _fire_projectile 同一空间)
	var center: Vector2 = node.get_meta("home_pos", node.position) + (av.position if av != null else Vector2(0, -50))
	# 朝向敌方: 左队(x<640)朝右(+x), 右队朝左(-x)
	var dir_x: float = 1.0 if center.x < 640.0 else -1.0
	var base_ang: float = 0.0 if dir_x > 0.0 else PI   # 0=朝右, PI=朝左
	# 枪口火光 (火焰开火特效): 枪口处 ADD 橙火粒子, 朝敌方喷
	var muzzle := CPUParticles2D.new()
	muzzle.position = center + Vector2(dir_x * 26.0, 0)
	muzzle.emitting = true
	muzzle.one_shot = true
	muzzle.amount = 18
	muzzle.lifetime = 0.32
	muzzle.explosiveness = 1.0
	muzzle.direction = Vector2(dir_x, 0)
	muzzle.spread = 32.0
	muzzle.gravity = Vector2.ZERO
	muzzle.initial_velocity_min = 80.0
	muzzle.initial_velocity_max = 260.0
	muzzle.scale_amount_min = 1.6
	muzzle.scale_amount_max = 1.6
	muzzle.scale_amount_curve = _make_decay_curve()
	muzzle.color = Color(1.0, 0.62, 0.18)   # 橙红枪口火
	var mmat := CanvasItemMaterial.new()
	mmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	muzzle.material = mmat
	muzzle.z_index = 601   # 枪口火高过龟身(最深 ~497, 同 _play_muzzle_flash): 原 49 被遮
	slots_root.add_child(muzzle)
	get_tree().create_timer(0.6).timeout.connect(muzzle.queue_free)
	Audio.play_sfx("hit-physical", 0.4)
	# 弹珠贴图 (复用左轮子弹)
	var bullet_path := "res://assets/sprites/vfx/revolver-bullet.png"
	var bullet_tex: Texture2D = load(bullet_path) if ResourceLoader.exists(bullet_path) else null
	# 40°扇形等分: N 颗夹角相同, 从 -20° 到 +20° 等分 (N>1 时含两端, N=1 时居中)
	var fan: float = deg_to_rad(40.0)
	var travel: float = 520.0   # 飞行距离 (飞出屏外即可, 命中由逻辑处理)
	for i in range(pellets):
		var frac: float = (float(i) / float(pellets - 1)) if pellets > 1 else 0.5
		var ang: float = base_ang + (-fan / 2.0 + fan * frac) * dir_x   # 扇形角 (按朝向镜像)
		var end_pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * travel
		var pel := Sprite2D.new()
		if bullet_tex != null:
			pel.texture = bullet_tex
			pel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var bh: float = bullet_tex.get_height()
			if bh > 0:
				pel.scale = Vector2(14.0 / bh, 14.0 / bh)   # 小弹珠 ~14px
			pel.rotation = ang
		else:
			# 兜底: 无贴图用小橙圆
			pel.texture = null
		pel.position = center
		pel.z_index = 600   # 霰弹弹珠高过龟身(最深 ~497, 同 _fire_projectile): 原 48 被遮
		slots_root.add_child(pel)
		if bullet_tex == null:   # 几何兜底弹珠
			var dot := Polygon2D.new()
			dot.polygon = _circle_points(4.0)
			dot.color = Color(1.0, 0.85, 0.4)
			pel.add_child(dot)
		var pt := create_tween()
		pt.tween_property(pel, "position", end_pos, 0.26 + frac * 0.04).set_trans(Tween.TRANS_LINEAR)
		pt.tween_callback(pel.queue_free)


# ════════════════════════════════════════════════════════════════════
#  枪系弹道/激光 VFX (批2: 048手铳/049弩/050幽灵加特林/051激光手枪/057狙击/058穿甲遗弹).
#    复用 _fire_projectile 直线弹 / Line2D 光束 / CPUParticles 枪口火光, 不下外部素材.
#    全 fire-and-forget, 纯演出 (伤害由 runtime 标记 effect 各自飘字), 数值不动.
# ════════════════════════════════════════════════════════════════════
## 一发枪口火光 (小, ADD 橙火): 在 carrier 枪口处朝目标方向喷一束短火 — 复用 _play_shotgun_blast 枪口火光做法.
func _play_muzzle_flash(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or from_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[from_idx]):
		return
	if to_idx < 0 or to_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[to_idx]):
		return
	# home_pos 兜底取 .position (对齐 _play_slash_at): 防缺 meta 时 get_meta 报错中断。
	var from_pos: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -55)
	var to_pos: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -55)
	var dir: Vector2 = (to_pos - from_pos).normalized()
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	var muzzle := CPUParticles2D.new()
	muzzle.position = from_pos + dir * 26.0
	muzzle.emitting = true
	muzzle.one_shot = true
	muzzle.amount = 8
	muzzle.lifetime = 0.18
	muzzle.explosiveness = 1.0
	muzzle.direction = dir
	muzzle.spread = 26.0
	muzzle.gravity = Vector2.ZERO
	muzzle.initial_velocity_min = 70.0
	muzzle.initial_velocity_max = 200.0
	muzzle.scale_amount_min = 1.1
	muzzle.scale_amount_max = 1.1
	muzzle.scale_amount_curve = _make_decay_curve()
	muzzle.color = Color(1.0, 0.66, 0.22)   # 橙红枪口火
	var mmat := CanvasItemMaterial.new()
	mmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	muzzle.material = mmat
	muzzle.z_index = 601   # 高过龟身(最深 ~497, 同 _fire_projectile 弹珠), 否则枪口火也被龟立绘遮掉
	slots_root.add_child(muzzle)
	get_tree().create_timer(0.4).timeout.connect(muzzle.queue_free)


## 枪系一发直线弹/弩箭 (048/049/050): 枪口火光 + 直线弹珠从携带者飞向目标 — 复用 _fire_projectile.
func _play_gun_shot(from_idx: int, to_idx: int, tex_path: String, size: float, dur: float) -> void:
	_play_muzzle_flash(from_idx, to_idx)
	_fire_projectile(from_idx, to_idx, tex_path, size, dur)   # fire-and-forget 直线弹


## 错开发射版 (048/050 连发 stagger): 等 delay 秒后再放一发 — fire-and-forget, 调用处不 await (不阻塞主循环节奏).
func _play_gun_shot_delayed(from_idx: int, to_idx: int, tex_path: String, size: float, dur: float, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	_play_gun_shot(from_idx, to_idx, tex_path, size, dur)


## 枪[神枪手]金弹弹道 (羁绊 goldbullet): 金色子弹从枪携带者(from_idx)飞向目标(to_idx) — 金弹是子弹, 走真弹道非砸击帧.
##   = 金色枪口火光 + 金 tint 的 revolver-bullet 直线飞 + 命中处金色爆点环. from_idx<0 (无携带者) → 只播目标处金弹爆点+金环.
##   复用 _play_muzzle_flash/revolver-bullet 贴图+ADD金 modulate/_play_aoe_ring, 无新资源, fire-and-forget.
func _play_gold_bullet(from_idx: int, to_idx: int) -> void:
	if to_idx < 0 or to_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[to_idx]):
		return
	var gold := Color(1.0, 0.84, 0.28)
	# 有携带者 → 飞一颗金弹弹道 (枪口火光 + 金 tint 弹珠飞向目标)
	if from_idx >= 0 and from_idx < slot_nodes.size() and is_instance_valid(slot_nodes[from_idx]) and from_idx != to_idx:
		_play_muzzle_flash(from_idx, to_idx)
		var bullet_path := "res://assets/sprites/vfx/revolver-bullet.png"
		if ResourceLoader.exists(bullet_path):
			var from_pos: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -55)
			var to_pos: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -55)
			var proj := Sprite2D.new()
			proj.texture = load(bullet_path)
			proj.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var th: float = proj.texture.get_height()
			if th > 0:
				proj.scale = Vector2(18.0 / th, 18.0 / th)   # 金弹略大 ~18px (枪羁绊高光发)
			proj.modulate = gold                              # 金 tint
			var pmat := CanvasItemMaterial.new()
			pmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # ADD 发光金弹
			proj.material = pmat
			proj.position = from_pos
			proj.rotation = (to_pos - from_pos).angle()
			proj.z_index = 600   # 高过龟身(同 _fire_projectile), 否则金弹也被龟立绘遮掉
			slots_root.add_child(proj)
			var pt := create_tween()
			pt.tween_property(proj, "position", to_pos, 0.20).set_trans(Tween.TRANS_LINEAR)
			pt.tween_callback(proj.queue_free)
	# 命中处金色爆点环 (无携带者也播, 作金弹落点)
	_play_aoe_ring(to_idx, Color(1.0, 0.84, 0.28, 0.6))


## 枪系激光束 (051 红 / 057 青白细): 从携带者朝目标射一道 Line2D 光束, 短暂亮起后淡出 — 复用 crystal-beam 发射相结构.
##   color=束色, width=束宽px, dur=持续s. 纯演出, 不阻塞.
func _play_laser_beam(from_idx: int, to_idx: int, color: Color, width: float, dur: float, pierce: bool = false) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	var from_pos: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -55)
	var to_pos: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -55)
	# 057 狙击穿透: 终点沿 from→target 方向延长到屏幕边缘 (射到尽头, 而非止于目标点)。
	#   光束起点不变 (枪口), 命中闪光仍打真目标 to_idx; 只是束身贯穿过去。
	if pierce:
		var dir: Vector2 = (to_pos - from_pos)
		if dir.length() > 0.001:
			dir = dir.normalized()
			# 沿方向求到屏幕外框 (含 ENVELOP 留白余量) 的最远交点: 取够大的 t 直接外推到 VIEW 边外。
			var far_x: float = float(VIEW_W) + 200.0 if dir.x >= 0.0 else -200.0   # 朝右→右边外 / 朝左→左边外
			var t_edge: float = (far_x - from_pos.x) / dir.x if absf(dir.x) > 0.001 else 4000.0
			to_pos = from_pos + dir * absf(t_edge)
	_play_muzzle_flash(from_idx, to_idx)
	# 外层辉光束 (宽, 半透明) + 内层亮芯 (细, ADD) → 激光质感
	var glow := Line2D.new()
	glow.points = PackedVector2Array([from_pos, to_pos])
	glow.width = width * 2.2
	glow.default_color = Color(color.r, color.g, color.b, 0.28)
	glow.z_index = 600   # 高过龟身(最深 ~497): 原 46 被龟立绘遮死
	var gmat := CanvasItemMaterial.new()
	gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gmat
	slots_root.add_child(glow)
	var beam := Line2D.new()
	beam.points = PackedVector2Array([from_pos, to_pos])
	beam.width = width
	beam.default_color = Color(color.r, color.g, color.b, 0.95)
	beam.z_index = 601   # 亮芯叠在辉光之上, 均高过龟身 (原 47 被遮)
	var bmat := CanvasItemMaterial.new()
	bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam.material = bmat
	slots_root.add_child(beam)
	_flash_hit(to_idx)   # 命中点 avatar 白脉冲
	var tw := beam.create_tween().set_parallel(true)
	tw.tween_property(beam, "modulate:a", 0.0, dur)
	tw.tween_property(glow, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(beam.queue_free)
	tw.chain().tween_callback(glow.queue_free)


## 穿甲遗弹 058 贯穿弹道: 一发弹珠从携带者飞过前敌【贯穿】打到身后同列敌 (终点=behind 处, 飞行直线穿过前排) — 复用 _fire_projectile.
func _play_gun_pierce(from_idx: int, to_idx: int, tex_path: String) -> void:
	_play_muzzle_flash(from_idx, to_idx)
	_fire_projectile(from_idx, to_idx, tex_path, 18.0, 0.24)   # 直线弹穿到身后敌 (视觉=穿透弹道)


# 火球飞行 VFX — 1:1 PoC castFireball(vfx/skills.ts:8505): 橙球(r12 #ff6a00)+光晕(r22 #ffaa33)+ADD拖尾
#   从 caster 飞向 target 350ms power2.in, 命中爆 24 粒子 + 震屏(180,.012). 比例/色需 F5 眼验.
func _play_fireball(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	Audio.play_sfx("hit-physical", 0.4)   # 1:1 PoC sfx-hit vol 0.4
	var from_pos: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -55)
	var to_pos: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -55)
	var glow := Polygon2D.new()
	glow.polygon = _circle_points(22.0)
	glow.color = Color(1.0, 0.667, 0.2, 0.55)   # #ffaa33 α.55
	glow.position = from_pos
	glow.z_index = 600   # 高过龟身(最深 ~497): 原 48 火球光晕被龟立绘遮死
	slots_root.add_child(glow)
	var fb := Polygon2D.new()
	fb.polygon = _circle_points(12.0)
	fb.color = Color(1.0, 0.416, 0.0)   # #ff6a00
	fb.position = from_pos
	fb.z_index = 601   # 火球本体叠在光晕之上 (原 49 被遮)
	slots_root.add_child(fb)
	# ADD 拖尾 (跟随火球: 挂 fb 子级 + local_coords=false → 粒子留在世界形成尾迹)
	var trail := CPUParticles2D.new()
	trail.local_coords = false
	trail.emitting = true
	trail.amount = 20
	trail.lifetime = 0.35
	trail.spread = 180.0
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 10.0
	trail.initial_velocity_max = 40.0
	trail.scale_amount_curve = _make_decay_curve()
	trail.color = Color(1.0, 0.53, 0.2)
	var tmat := CanvasItemMaterial.new()
	tmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	trail.material = tmat
	fb.add_child(trail)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(fb, "position", to_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(glow, "position", to_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if is_instance_valid(glow):
		glow.queue_free()
	if is_instance_valid(fb):
		fb.queue_free()
	_play_screen_shake(0.18, 12.0)   # 1:1 PoC cam.shake(180, 0.012)
	# 命中爆 24 ADD 粒子 (PoC speed80-220 scale1→0 红橙 lifespan500)
	var burst := CPUParticles2D.new()
	burst.position = to_pos
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 24
	burst.lifetime = 0.5
	burst.explosiveness = 1.0
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = 80.0
	burst.initial_velocity_max = 220.0
	burst.scale_amount_curve = _make_decay_curve()
	burst.color = Color(1.0, 0.27, 0.0)   # #ff4400
	var bmat := CanvasItemMaterial.new()
	bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	burst.material = bmat
	burst.z_index = 600   # 命中爆粒高过龟身(最深 ~497): 原 48 被遮
	slots_root.add_child(burst)
	get_tree().create_timer(0.7).timeout.connect(burst.queue_free)


# 链式闪电单段 VFX — 1:1 PoC drawLightningBolt: 起→终 7段锯齿折线 (青外发光 ADD + 白内芯), 闪现后~180ms淡出.
#   chain_idx = 第几跳 (0-based) → 渲染整体延 chain_idx*0.22s 错峰亮起, 形成"链式逐跳依次劈过"观感 (1:1 PoC skills.ts:208 idx*220ms).
#   伤害飘字/血条已在主循环按原时机走 (本函数只管视觉, 伤害数值不动); cast 音效在首跳(idx 0)播一次.
func _play_chain_bolt(from_idx: int, to_idx: int, chain_idx: int = 0) -> void:
	if chain_idx <= 0:
		Audio.play_sfx("hit-crit", 0.5)   # 链起手暴音 (1:1 PoC scene.sound.play('sfx-crit', 0.5) → Godot hit-crit); 仅首跳一次
	if chain_idx > 0:
		await get_tree().create_timer(float(chain_idx) * 0.22).timeout   # 逐跳递增延时: 第 idx 跳延 idx*0.22s 再亮 (核心)
	_render_chain_bolt(from_idx, to_idx)


# 链式闪电单段实际渲染 (延时后调) — 锯齿闪电线 + 命中点白圈 + 麻痹青白 tint.
func _render_chain_bolt(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	var p1: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -55)
	var p2: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -55)
	var d: Vector2 = p2 - p1
	var ln: float = maxf(1.0, d.length())
	var perp: Vector2 = Vector2(-d.y, d.x) / ln   # 垂直方向 → 锯齿偏移
	var seg: int = 7
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		var tt: float = float(i) / float(seg)
		var off: float = 0.0 if (i == 0 or i == seg) else randf_range(-13.0, 13.0)   # PoC ±13 (26宽)
		pts.append(p1 + d * tt + perp * off)
	var lmat := CanvasItemMaterial.new()
	lmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var glow := Line2D.new()   # 青外发光
	glow.points = pts
	glow.width = 6.0
	glow.default_color = Color(0.3, 0.85, 1.0, 0.6)   # #4dd9ff
	glow.material = lmat
	glow.z_index = 600   # 高过龟身(最深 ~497, 同 _fire_projectile 弹珠): 原 47 被龟立绘遮死 → "法器啥也没有"
	slots_root.add_child(glow)
	var core := Line2D.new()   # 白内芯
	core.points = pts
	core.width = 2.0
	core.default_color = Color(1, 1, 1, 0.95)
	core.material = lmat
	core.z_index = 601   # 内芯叠在外发光之上 (原 48 同被龟遮)
	slots_root.add_child(core)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(glow, "modulate:a", 0.0, 0.18)
	tw.tween_property(core, "modulate:a", 0.0, 0.18)
	get_tree().create_timer(0.22).timeout.connect(glow.queue_free)
	get_tree().create_timer(0.22).timeout.connect(core.queue_free)
	# 命中点白光圈 (1:1 PoC skills.ts:231: r30 白圆 α0.8, 200ms 淡出) — 让每跳"咬"在目标身上.
	var to_node: Node2D = slot_nodes[to_idx]
	var to_av: Sprite2D = to_node.get_meta("avatar", null)
	var hit_pos: Vector2 = to_av.position if to_av != null else Vector2(0, -50)
	var flash := Polygon2D.new()
	flash.polygon = _circle_points(30.0)
	flash.color = Color(1, 1, 1, 0.8)
	flash.position = hit_pos
	flash.z_index = 602   # 圈在闪电线之上, 同高过龟身
	to_node.add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "modulate:a", 0.0, 0.2)   # 200ms 淡出
	ft.tween_callback(flash.queue_free)
	# 麻痹青白 tint (1:1 PoC skills.ts:236: setTint #a5f3fc 约 300ms 后清) — 雷电主题贴, 复用 avatar tint 同 _play_freeze_flash 手法.
	if to_av != null:
		var a2: float = to_av.modulate.a
		to_av.modulate = Color(0.647, 0.953, 0.988, a2)   # #a5f3fc 青白
		var tt := create_tween()
		tt.tween_interval(0.3)
		tt.tween_property(to_av, "modulate", Color(1, 1, 1, a2), 0.12)   # 300ms 后回白


# 火柱横扫 VFX — 1:1 PoC spawnFireSweep(vfx/skills.ts:544): 火色 CPUParticles2D 从起点扫向终点 600ms Cubic.easeOut.
#   tint #ff3300 ADD, lifespan420 speed20-90 scale1.3→0; local_coords=false 让粒子留世界空间 → 扫过留火尾迹.
func _play_fire_sweep(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	var from_pos: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -55)
	var to_pos: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -55)
	var sweep := CPUParticles2D.new()
	sweep.local_coords = false   # 粒子留世界空间 → 扫过留火尾迹 (非跟随发射器)
	sweep.position = from_pos
	sweep.emitting = true
	sweep.amount = 36
	sweep.lifetime = 0.42   # PoC lifespan 420ms
	sweep.spread = 180.0
	sweep.gravity = Vector2.ZERO
	sweep.initial_velocity_min = 20.0
	sweep.initial_velocity_max = 90.0
	sweep.scale_amount_min = 1.3
	sweep.scale_amount_max = 1.3
	sweep.scale_amount_curve = _make_decay_curve()
	sweep.color = Color(1.0, 0.2, 0.0)   # #ff3300 火色
	var tmat := CanvasItemMaterial.new()
	tmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sweep.material = tmat
	sweep.z_index = 600   # 高过龟身(最深 ~497): 原 46 火柱横扫被龟立绘遮死
	slots_root.add_child(sweep)
	var tw := create_tween()
	tw.tween_property(sweep, "position", to_pos, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	sweep.emitting = false
	get_tree().create_timer(0.46).timeout.connect(sweep.queue_free)


# 水晶光束 VFX — 1:1 PoC castCrystalBeam(vfx/skills.ts): 红警告相(260ms 14px #ff5050) → 蓝紫发射相(350ms 6px #b478ff→#5028b4 淡出).
#   (Godot: Line2D 直线束 from→to; 用真节点 Line2D 替 Phaser graphics.fillRect — agent原码用了Godot没有的 Graphics 类已弃.)
func _play_crystal_beam(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	var from_pos: Vector2 = slot_nodes[from_idx].get_meta("home_pos", slot_nodes[from_idx].position) + Vector2(0, -55)
	var to_pos: Vector2 = slot_nodes[to_idx].get_meta("home_pos", slot_nodes[to_idx].position) + Vector2(0, -55)
	# 警告相: 红光束 14px, 260ms 淡出 (PoC rgba(255,80,80) α0.7→0)
	var warn := Line2D.new()
	warn.points = PackedVector2Array([from_pos, to_pos])
	warn.width = 14.0
	warn.default_color = Color(1.0, 0.314, 0.314, 0.7)   # #ff5050 α0.7
	warn.z_index = 600   # 高过龟身(最深 ~497): 原 46 被龟立绘遮死 → "法器啥也没有"
	slots_root.add_child(warn)
	var wtw := warn.create_tween()
	wtw.tween_property(warn, "modulate:a", 0.0, 0.26)
	await get_tree().create_timer(0.26).timeout
	if is_instance_valid(warn):
		warn.queue_free()
	# 发射相: 蓝紫光束 6px, 350ms 渐变 #b478ff→#5028b4 + 淡出 (PoC 发射光)
	var beam := Line2D.new()
	beam.points = PackedVector2Array([from_pos, to_pos])
	beam.width = 6.0
	beam.default_color = Color(0.706, 0.471, 1.0, 0.95)   # #b478ff α0.95
	beam.z_index = 601   # 发射束叠在警告相之上, 均高过龟身 (原 47 被遮)
	var bmat := CanvasItemMaterial.new()
	bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam.material = bmat
	slots_root.add_child(beam)
	_flash_hit(to_idx)   # 命中点 avatar 白脉冲
	var btw := beam.create_tween().set_parallel(true)
	btw.tween_property(beam, "default_color", Color(0.314, 0.157, 0.706, 0.4), 0.35)   # → #5028b4 α0.4
	btw.tween_property(beam, "modulate:a", 0.0, 0.35)
	await btw.finished
	if is_instance_valid(beam):
		beam.queue_free()


# ════════════════════════════════════════════════════════════════════
#  斩击弧 VFX (剑系装备 001/005/006/007/009/010/011) — 通用程序化月牙刃光.
#    无外部素材: Line2D 画月牙弧 (内外两条弧边) + 加色发光, 快速扫出后淡出 ~250ms.
#    视觉=一道弯月刀光从挥砍起点扫向目标方向, 随挥砍方向倾斜.
# ════════════════════════════════════════════════════════════════════
## 月牙弧顶点: 沿 dir 方向的一段圆弧 (内/外两条弧边接成月牙形). 返回闭合多边线顶点.
##   span=弧张角(rad), radius=外弧半径, thick=月牙厚度. dir=Vector2 挥砍朝向(已归一).
func _slash_arc_points(dir: Vector2, radius: float, thick: float, span: float, segs: int = 14) -> PackedVector2Array:
	var base_ang: float = dir.angle()                 # 月牙正对挥砍方向
	var a0: float = base_ang - span * 0.5
	var a1: float = base_ang + span * 0.5
	var pts := PackedVector2Array()
	# 外弧 (a0 → a1)
	for i in range(segs + 1):
		var a: float = lerpf(a0, a1, float(i) / float(segs))
		pts.append(Vector2(cos(a), sin(a)) * radius)
	# 内弧 (a1 → a0, 半径收缩 → 形成弯月厚度)
	for i in range(segs + 1):
		var a: float = lerpf(a1, a0, float(i) / float(segs))
		pts.append(Vector2(cos(a), sin(a)) * (radius - thick))
	return pts


## 在世界坐标 center 播一道斩击弧月牙: 沿 dir 挥出 (快速扫出 30°→sweep + 淡出 ~250ms).
##   color=刃光色 (锈剑灰白/吸血红/激光青等). scale=整体大小. 纯视觉, 不阻塞主流程.
func _play_slash_arc(center: Vector2, dir: Vector2, color: Color, scale: float = 1.0) -> void:
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var radius: float = 56.0 * scale
	var thick: float = 20.0 * scale
	var arc := Line2D.new()
	arc.points = _slash_arc_points(dir, radius, thick, deg_to_rad(70.0))
	arc.closed = true
	arc.width = 4.0 * scale
	arc.default_color = color
	arc.joint_mode = Line2D.LINE_JOINT_ROUND
	arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arc.end_cap_mode = Line2D.LINE_CAP_ROUND
	arc.position = center
	arc.z_index = 600   # 斩击月牙刃光高过龟身(最深 ~497): 原 140 被龟立绘遮死
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	arc.material = mat
	# 挥砍出刀: 弧从挥砍反向(-perp)起手, 快速旋扫到正位, 同时放大一点 → 刀光划过感
	var perp := dir.orthogonal()
	arc.rotation = -0.55                              # 起手回刀角
	arc.scale = Vector2(0.7, 0.7)
	arc.position = center - perp * 10.0 * scale
	slots_root.add_child(arc)
	var tw := arc.create_tween().set_parallel(true)
	tw.tween_property(arc, "rotation", 0.35, 0.16).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(arc, "scale", Vector2(1.0, 1.0), 0.16).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(arc, "position", center + perp * 10.0 * scale, 0.16)
	tw.chain().tween_property(arc, "modulate:a", 0.0, 0.10)   # 总 ~260ms
	tw.chain().tween_callback(arc.queue_free)


## 在某 slot 处播斩击弧, 方向 = 携带者→目标 (从 carrier 朝向被斩者; carrier<0 则按目标 side 朝己方外).
func _play_slash_at(target_idx: int, color: Color, carrier_idx: int = -1, scale: float = 1.0) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var tpos: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position) + Vector2(0, -50)
	var dir: Vector2
	if carrier_idx >= 0 and carrier_idx < slot_nodes.size() and is_instance_valid(slot_nodes[carrier_idx]):
		var cpos: Vector2 = slot_nodes[carrier_idx].get_meta("home_pos", slot_nodes[carrier_idx].position) + Vector2(0, -50)
		dir = (tpos - cpos)
		if dir.length() < 1.0:
			dir = Vector2.RIGHT
	else:
		# 无 carrier: 按目标侧朝其敌方方向 (右队目标=刀从左劈来 → dir 朝右)
		dir = Vector2.LEFT if fighters[target_idx].get("side", "left") == "left" else Vector2.RIGHT
	_play_slash_arc(tpos, dir, color, scale)


## 斩击弧扫一组目标 (006千刃排穿/007横劈/009刃能列扫/010横扫): 从 carrier 朝各目标方向各劈一道月牙弧,
##   并沿目标连线拉一条快速扫过的刃光 (排扫感). color=刃光主色.
func _play_slash_sweep(carrier_idx: int, target_idxs: Array, color: Color, scale: float = 1.0) -> void:
	if carrier_idx < 0 or carrier_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[carrier_idx]):
		# 无有效 carrier → 逐目标单斩兜底
		for ti in target_idxs:
			_play_slash_at(int(ti), color, -1, scale)
		return
	var cpos: Vector2 = slot_nodes[carrier_idx].get_meta("home_pos", slot_nodes[carrier_idx].position) + Vector2(0, -50)
	var pts: Array[Vector2] = []
	for ti in target_idxs:
		var i: int = int(ti)
		if i < 0 or i >= slot_nodes.size() or not is_instance_valid(slot_nodes[i]):
			continue
		var tp: Vector2 = slot_nodes[i].get_meta("home_pos", slot_nodes[i].position) + Vector2(0, -50)
		pts.append(tp)
		_play_slash_arc(tp, (tp - cpos), color, scale)
	if pts.size() < 2:
		return
	# 排扫刃光: 一条沿目标的弧线极快扫过 (头尾按 y 排序, 月牙样横扫) → 多目标"一排剑刃风暴"感
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	var sweep := Line2D.new()
	sweep.width = 7.0 * scale
	sweep.default_color = Color(color.r, color.g, color.b, 0.0)   # 起手透明 → 扫入时显
	sweep.joint_mode = Line2D.LINE_JOINT_ROUND
	sweep.begin_cap_mode = Line2D.LINE_CAP_ROUND
	sweep.end_cap_mode = Line2D.LINE_CAP_ROUND
	var smat := CanvasItemMaterial.new()
	smat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sweep.material = smat
	sweep.z_index = 600   # 横扫斩击高过龟身(最深 ~497): 原 139 被龟立绘遮死
	slots_root.add_child(sweep)
	# 从首目标起逐点延伸 (刃光扫过整列) — 与 _play_rainbow_snake 同手法
	sweep.add_point(pts[0])
	var tw := sweep.create_tween()
	tw.tween_property(sweep, "default_color", Color(color.r, color.g, color.b, 0.9), 0.06)
	for i in range(1, pts.size()):
		sweep.add_point(pts[i - 1])
		var pi: int = sweep.get_point_count() - 1
		tw.parallel().tween_method(func(p: Vector2) -> void: sweep.set_point_position(pi, p), pts[i - 1], pts[i], 0.07 * float(pts.size()))
	tw.tween_interval(0.06)
	tw.tween_property(sweep, "modulate:a", 0.0, 0.14)
	tw.tween_callback(sweep.queue_free)


# 迷你水晶球B 旋转扫描束 VFX — 1:1 PoC launchMiniCrystalBeam(vfx/skills.ts:406): 径向红光从 owner 旋转 180° 扫敌.
#   左队 -90°→90° / 右队 90°→270°, 1400ms cubic.inOut + 140ms 淡入淡出. (伤害已由 031 逻辑一次施加, 此纯视觉)
func _play_mini_crystal_beam(owner_idx: int) -> void:
	if owner_idx < 0 or owner_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[owner_idx]):
		return
	var owner_f: Dictionary = fighters[owner_idx]
	var owner_pos: Vector2 = slot_nodes[owner_idx].get_meta("home_pos", slot_nodes[owner_idx].position) + Vector2(0, -55)
	var enemies := _alive_enemies_of(owner_f)
	if enemies.is_empty():
		return
	var max_dist: float = 80.0   # PoC: 最远敌距 + 80
	for e in enemies:
		var ei: int = fighters.find(e)
		if ei >= 0 and ei < slot_nodes.size() and is_instance_valid(slot_nodes[ei]):
			var ep: Vector2 = slot_nodes[ei].get_meta("home_pos", slot_nodes[ei].position) + Vector2(0, -55)
			max_dist = maxf(max_dist, owner_pos.distance_to(ep) + 80.0)
	var on_left: bool = str(owner_f.get("side", "left")) == "left"
	var start_ang: float = deg_to_rad(-90.0 if on_left else 90.0)
	var end_ang: float = deg_to_rad(90.0 if on_left else 270.0)
	# 径向红光束 (Line2D 从 0 到 maxDist, width 8 #ff2828)
	var beam := Line2D.new()
	beam.points = PackedVector2Array([Vector2.ZERO, Vector2(max_dist, 0)])
	beam.width = 8.0
	beam.default_color = Color(1.0, 0.157, 0.157, 0.85)   # #ff2828
	beam.position = owner_pos
	beam.rotation = start_ang
	beam.z_index = 600   # 高过龟身(最深 ~497): 原 46 被龟立绘遮死 → 法器径向束看不见
	beam.modulate.a = 0.0
	slots_root.add_child(beam)
	beam.create_tween().tween_property(beam, "modulate:a", 1.0, 0.14)   # 淡入 140ms (与旋转并行)
	var rot := beam.create_tween()
	rot.tween_property(beam, "rotation", end_ang, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await rot.finished
	if is_instance_valid(beam):
		var fout := beam.create_tween()
		fout.tween_property(beam, "modulate:a", 0.0, 0.14)
		await fout.finished
		if is_instance_valid(beam):
			beam.queue_free()


# 战斗开始一次性被动 (PoC 登场期): lavaEnhancedRage 满怒 / twoHead resilience 标记 / fusion 加成
func _apply_start_passives() -> void:
	for f in fighters:
		var ps: Array = f.get("_passiveSkills", [])
		var has_lava_enh := false
		var has_th_res := false
		var has_th_fusion := false
		var has_cyber_enh := false
		var has_hiding_enh := false
		var has_chest_greed := false
		var has_dice_convert := false
		var has_gambler_enh := false
		for s in ps:
			match s.get("type", ""):
				"lavaEnhancedRage": has_lava_enh = true
				"twoHeadResilience": has_th_res = true
				"twoHeadFusion": has_th_fusion = true
				"cyberEnhancedDrone": has_cyber_enh = true
				"hidingEnhancedSummon": has_hiding_enh = true
				# B组 强化被动 flag (读取逻辑已存在, 之前 flag 从不被设 → 永不生效)
				"diamondEnhanced": f["_diamondEnhanced"] = true          # 自身甲抗amp+100% (damage.gd:166读)
				"rainbowEnhancedPrism": f["_enhancedPrism"] = true       # 棱镜7色每回合2选 (_apply_rainbow_prism读)
				"chestIntuition": f["_chestIntuition"] = true            # 开箱阈值降低 (equipment_runtime:976读)
				"chestGreed": has_chest_greed = true
				"diceGamblerConvert": has_dice_convert = true
				"crystalImmortal": f["_crystalImmortal"] = true          # 第10回合 +5000HP+400ATK (round-start触发)
				"gamblerFateWheel": f["_fateWheel"] = true               # 每回合抽花色永久加属性 (round-start触发)
				"gamblerEnhancedMulti": has_gambler_enh = true
				"lineRapid":                                             # 墨迹上限7+全转真伤
					f["_inkTrueDmg"] = true
					f["_inkCapOverride"] = 7
				"ninjaFeet":   # 忍者足: 登场 +25%闪避 +40%暴击 (1:1 PoC; 原 passiveSkill 从不接)
					f["_extraDodge"] = int(f.get("_extraDodge", 0)) + 25
					f["crit"] = minf(1.0, f.get("crit", 0.0) + 0.40); f["_baseCrit"] = f.get("_baseCrit", 0.0) + 0.40
				"iceBurnImmune":   # 极寒: 燃烧免疫 + frostAura加成 20→40 (原 passiveSkill 从不接)
					f["_burnImmune"] = true
					if f.get("passive", {}) is Dictionary and f["passive"].get("type", "") == "frostAura":
						f["passive"]["bonusDmgPct"] = 40
				"angelRevive":   # 圣光: 首次阵亡 25%HP 复活一次 (原 passiveSkill 从不接; _check_revives 接)
					f["_angelRevive"] = true
				"bambooCharged":   # 强化生长: 充能追击 atkPct75→100/selfHp8→13/heal8→12/hpGain60→105 (_fire_bamboo_charge 读 _bambooEnhanced; 原 passiveSkill 从不接=强化无效)
					f["_bambooEnhanced"] = true
		# 强化喊龟: 登场 owner -50% maxHp, 记原始血供随从×110%, passive.hpPct 40→110
		if has_hiding_enh and f.get("passive", {}) is Dictionary and f["passive"].get("type", "") == "summonAlly":
			f["_summonHpBase"] = f.get("maxHp", 0)
			var loss: int = roundi(f.get("maxHp", 0) * 0.5)
			f["maxHp"] = maxi(1, int(f.get("maxHp", 0)) - loss)
			f["hp"] = mini(int(f.get("hp", 0)), int(f["maxHp"]))
			f["passive"]["hpPct"] = 110
			f["_enhancedSummon"] = true
		# 强化浮游炮: _cyberEnhanced + 改 passive (maxDrones20/droneScale0.12/dronesPerTurn2)
		if has_cyber_enh and f.get("passive", {}) is Dictionary and f["passive"].get("type", "") == "cyberDrone":
			f["_cyberEnhanced"] = true
			f["passive"]["maxDrones"] = 20
			f["passive"]["droneScale"] = 0.12
			f["passive"]["dronesPerTurn"] = 2
		# 强化熔岩之心: 开局即满怒 → 首动立即变身
		if has_lava_enh and f.get("passive", {}) is Dictionary and f["passive"].get("type", "") == "lavaRage":
			f["_lavaRage"] = f["passive"].get("rageMax", 100)
			f["_lavaRageReady"] = true
		# 双头坚韧: 标记受击叠甲抗 (累积逻辑在 Damage.apply_raw_damage)
		if has_th_res:
			f["_twoHeadResilience"] = true
			f["_twoHeadResStacks"] = 0
		# 双头融合: 登场一次性 +HP/Def/Mr/Shield 常驻 (不可换形), 用 baseAtk
		if has_th_fusion and f.get("passive", {}) is Dictionary:
			var tp = f["passive"]
			var ba: float = f.get("baseAtk", 0)
			f["maxHp"] = int(f.get("maxHp", 0)) + roundi(ba * tp.get("hpScale", 1.5))
			f["hp"] = int(f.get("hp", 0)) + roundi(ba * tp.get("hpScale", 1.5))
			f["baseDef"] = f.get("baseDef", 0) + roundi(ba * tp.get("defScale", 0.25)); f["def"] = f["baseDef"]
			f["baseMr"] = int(f.get("baseMr", f.get("baseDef", 0))) + roundi(ba * tp.get("defScale", 0.25)); f["mr"] = f["baseMr"]
			Buffs.grant_shield(f, roundi(ba * tp.get("shieldScale", 1.1)))
			f["_twoHeadFusion"] = true
		# 贪婪(chestGreed): 每件装备永久 +4%baseAtk +7%maxHp (登场一次性结算, 1:1 PoC:1394-1405)
		if has_chest_greed:
			f["_chestGreed"] = true
			var eqc: int = (f.get("_equipped_ids", []) as Array).size()
			if eqc > 0:
				var atk_gain: int = roundi(float(f.get("baseAtk", 0)) * 0.04 * eqc)
				var hp_gain: int = roundi(float(f.get("maxHp", 0)) * 0.07 * eqc)
				f["baseAtk"] = int(f.get("baseAtk", 0)) + atk_gain; f["atk"] = f["baseAtk"]
				f["maxHp"] = int(f.get("maxHp", 0)) + hp_gain
				f["hp"] = int(f.get("hp", 0)) + hp_gain
		# 真正的赌徒(diceGamblerConvert): 全部 DEF+MR → 护甲穿透, 甲/抗归零 (1:1 PoC:1354-1369)
		if has_dice_convert:
			var tot: int = int(f.get("baseDef", 0)) + int(f.get("baseMr", f.get("baseDef", 0)))
			f["armorPen"] = int(f.get("armorPen", 0)) + tot
			f["_baseArmorPen"] = int(f.get("armorPen", 0))
			f["baseDef"] = 0; f["def"] = 0
			f["baseMr"] = 0; f["mr"] = 0
			f["_diceGamblerConverted"] = true
		# 强化多重打击(gamblerEnhancedMulti): 登场扣当前HP30% + 多重概率40→60 (1:1 PoC:1283-1289)
		if has_gambler_enh:
			f["_gamblerEnhancedMulti"] = true
			var hp_loss: int = roundi(int(f.get("hp", 0)) * 0.3)
			f["hp"] = maxi(1, int(f.get("hp", 0)) - hp_loss)
			if f.get("passive", {}) is Dictionary and f["passive"].get("type", "") == "gamblerMultiHit":
				f["passive"]["chance"] = 60
		# ── 登场期 passive (1:1 PoC BattleScene 1255-1197) ──
		var pp = f.get("passive", null)
		if pp is Dictionary:
			match pp.get("type", ""):
				"ninjaInstinct":  # 开局 +暴击/+暴伤永久/+穿甲
					f["crit"] = minf(1.0, f.get("crit", 0.0) + pp.get("critBonus", 30) / 100.0)
					f["_extraCritDmgPerm"] = f.get("_extraCritDmgPerm", 0.0) + pp.get("critDmgBonus", 20) / 100.0
					f["armorPen"] = f.get("armorPen", 0) + pp.get("armorPen", 8)
				"frostAura":  # 登场冰寒全敌 (chilled -20%ATK, atkDownTurns+1)
					for e in fighters:
						if e.get("side", "") != f.get("side", "") and e.get("alive", false):
							Buffs.add(e, "chilled", 1, int(pp.get("atkDownTurns", 6)) + 1, "refresh")
				"ghostCurse":  # 登场诅咒全敌 (value=round(maxHp×hpPct%), turns+1)
					for e in fighters:
						if e.get("side", "") != f.get("side", "") and e.get("alive", false):
							(e["buffs"] as Array).append({"type": "curse", "value": roundi(e.get("maxHp", 0) * pp.get("hpPct", 5) / 100.0), "duration": int(pp.get("turns", 3)) + 1})
				"undeadRage":  # 登场固定 22% 基础吸血 (HP-scaling ATK PoC recalc 已删)
					f["lifestealPct"] = pp.get("lifestealBase", 22) / 100.0
					f["_baseLifesteal"] = f.get("lifestealPct", 0.0)
				"twoHeadVitality":  # 登场 shieldPct% maxHp 盾
					Buffs.grant_shield(f, roundi(f.get("maxHp", 0) * pp.get("shieldPct", 20) / 100.0))


# ── 战斗资源: 龟能(蓝量, 大部分龟) / 熔岩龟怒气(橙, lavaRage) ──
## 技能资源消耗信息: {} (免费) 或 {field, cost, cur, max, color, icon}
##   龟能(_energy/_maxEnergy 蓝⚡) 或 熔岩龟怒气(_lavaRage/rageMax 橙🔥). 火山形态技能无 rageCost → 不计(走CD).
func _skill_cost_info(f: Dictionary, skill: Dictionary) -> Dictionary:
	if int(f.get("_maxEnergy", 0)) > 0:
		var ec := int(skill.get("energyCost", 0))
		if ec > 0:
			return {"field": "_energy", "cost": ec, "cur": int(f.get("_energy", 0)), "max": int(f.get("_maxEnergy", 0)), "color": "#5aa9ff", "icon": "⚡"}
	var rc := int(skill.get("rageCost", 0))
	if rc > 0:
		var pd = f.get("passive")
		var rmax := int((pd as Dictionary).get("rageMax", 100)) if pd is Dictionary else 100
		return {"field": "_lavaRage", "cost": rc, "cur": int(f.get("_lavaRage", 0)), "max": rmax, "color": "#ff7a3c", "icon": "🔥"}
	return {}

## 能否负担 (免费恒 true)
func _can_afford_energy(f: Dictionary, skill: Dictionary) -> bool:
	var info := _skill_cost_info(f, skill)
	return info.is_empty() or int(info["cur"]) >= int(info["cost"])

## 扣资源 (放技能时调)
func _spend_energy(f: Dictionary, skill: Dictionary) -> void:
	var info := _skill_cost_info(f, skill)
	if not info.is_empty():
		f[info["field"]] = maxi(0, int(f.get(info["field"], 0)) - int(info["cost"]))

## 资源条填充更新 (条宽 = cur/max; res_field/res_max 存于 node meta)
func _update_energy_bar(node: Node, f: Dictionary) -> void:
	if node == null or not node.has_meta("energy_fill"):
		return
	var fill = node.get_meta("energy_fill")
	if not is_instance_valid(fill):
		return
	var field: String = node.get_meta("res_field", "_energy")
	var mx := maxi(1, int(node.get_meta("res_max", 1)))
	var cur := clampi(int(f.get(field, 0)), 0, mx)
	# 熔岩龟变身火山形态: 红条改显变身时长倒计时 (登场满→每回合降→0 恢复小形态)
	if field == "_lavaRage" and bool(f.get("_lavaTransformed", false)):
		var pd = f.get("passive")
		mx = maxi(1, int((pd as Dictionary).get("transformDuration", 6))) if pd is Dictionary else 6
		cur = clampi(int(f.get("_lavaTransformTurns", 0)), 0, mx)
	var w: float = node.get_meta("energy_w", 88.0)
	(fill as ColorRect).size.x = w * float(cur) / float(mx)

## 刷新一只龟的资源条 (recovery/spend/攒怒气 后调; 按 fighter 找 slot)
func _refresh_energy_for(f: Dictionary) -> void:
	var i: int = fighters.find(f)
	if i >= 0 and i < slot_nodes.size() and is_instance_valid(slot_nodes[i]):
		_update_energy_bar(slot_nodes[i], f)


func _take_turn(actor_idx: int, forced_skill_idx: int = -1, forced_target_idx: int = -1) -> void:
	_clear_turn_timer()   # 真出手(玩家选定 or AI/超时接管) → 停倒计时
	var actor: Dictionary = fighters[actor_idx]
	if not actor["alive"]:
		return

	# 眩晕已在 _run_side_turn 的 turn-begin 处理 (_do_stun_skip), 此处不再判

	# 技能+目标: 玩家手动传入 (forced_*), 否则 AI 选 (濒死治疗 / 无盾加盾 / 否则攻击, 优先大招)
	var skill_idx: int
	var target_idx: int
	if forced_skill_idx >= 0:
		skill_idx = forced_skill_idx
		target_idx = forced_target_idx
	else:
		var choice: Variant = SkillHandlers.ai_pick(actor, fighters)
		if choice == null:
			return
		skill_idx = choice["skill_idx"]
		target_idx = choice["target_idx"]
	var skills: Array = actor["skills"]
	if skill_idx < 0 or skill_idx >= skills.size():
		return
	var skill: Dictionary = skills[skill_idx]
	if target_idx < 0 or target_idx >= fighters.size():   # 修(审计): ai_pick/_pick_enemy_target 无合法目标→-1, 原 fighters[-1] 打错单位/越界, 改跳过此手
		return
	var target: Dictionary = fighters[target_idx]
	_spend_energy(actor, skill)   # 龟能消耗 (基础/无龟能宠物=0; 玩家端面板已置灰放不起的, AI 已只选放得起的)
	_refresh_energy_for(actor)

	# ── 出招演出 (per-skill choreography, 1:1 PoC BattleScene.ts/skill-handlers.ts) ──
	#   windup: caster 摆位/蓄力, 返回时已到"命中帧" (PoC ATTACK_DAMAGE_SYNC_MS 等)。
	#   伤害仍由 SkillHandlers.execute (纯逻辑) 算, 飘字/受击在命中帧后展示。
	#   post: 击飞/抛投/归位 (juggle / lunge return), 在伤害展示后跑。
	# P17 1:1 PoC executeAttack (BattleScene.ts:3366-3368): 出手前报技能名 + 600ms 蓄势 (含 AI/玩家两路)
	_show_skill_announce(actor, str(skill.get("name", "")))
	await get_tree().create_timer(0.6).timeout
	if not actor.get("alive", false):
		return

	var skill_type: String = skill.get("type", "")
	await _skill_windup(actor_idx, target_idx, skill_type)

	# 派发: SkillHandlers 处理 physical/magic/heal/shield
	var result: Dictionary = SkillHandlers.execute(actor, target, fighters, skill)
	# C1 招财进宝: 抽中装备进玩家装备席 (1:1 PoC fortuneBuyEquip→addToBench; 引擎返 fortune_buy_eq, 不即时上身)
	if result.has("fortune_buy_eq") and actor.get("side", "") == "left":
		# 装备席满 (10/10) → 不硬塞, 改全员 +10%HP 补偿 (装备遗失) — 1:1 PoC addToBench(BattleScene.ts:8262-8280)
		if bench_inventory.size() < 10:
			bench_inventory.append(str(result["fortune_buy_eq"]))
			_rebuild_bench_rail()
		else:
			_bench_full_heal(actor.get("side", "left"))
	actor["_castIsAoe"] = skill_type in SKILL_AOE   # 雷电法杖 on_hit 读: AOE 充能减半 (PoC _castIsAoe)
	# W7 v1.1: 装备 hooks (PoC 1:1 — on_hit attacker 角度, on_hit_as_target target 角度)
	# 海带卷刀 / 火珊瑚 onHit; 炙烤海胆 / 珍珠耳环 onHitAsTarget
	var result_effects: Array = result.get("effects", [])
	# 法器·法力: 携带者本次技能打出的伤害总和 ×0.1 入每件法器法力 (≠龟能)。
	#   仅技能本体伤害(此时 result_effects 还没 append 装备 on_hit 派生/法器自身效果伤害 → 自动不计, 防连放)。
	if actor.get("_staff_mana") is Dictionary and not (actor["_staff_mana"] as Dictionary).is_empty():
		var _skill_dmg_sum: float = 0.0
		for _se in result_effects:
			if _se is Dictionary and str(_se.get("kind", "")) == "damage":
				_skill_dmg_sum += float(_se.get("value", 0))
		if _skill_dmg_sum > 0.0:
			Phase2EquipRuntime.staff_on_skill_damage(actor, _skill_dmg_sum)
			_refresh_staff_mana_for(actor)
	# 弹幕类 (打击/连珠箭): 按 result_effects 逐目标 staggered bolt (1:1 PoC basic.js/hunter.js
	#   N×280ms 错开飞 bolt). 其余技能走通用单 VFX。
	if skill_type == "basicBarrage" or skill_type == "hunterBarrage":
		_play_barrage_bolts(actor_idx, result_effects, skill_type, result.get("barrage_shots", []) if skill_type == "basicBarrage" else [])
	elif skill_type == "rainbowReflect":
		_play_rainbow_snake(actor_idx, result_effects)   # 彩虹蛇: 沿弹射路径飞行拖尾 (1:1 PoC makeRainbowSnake)
	elif skill_type == "p2Sweep":
		# 010 激光长刃【横扫】: 剑刃横扫弧 — 从携带者朝命中的一列/全体敌各劈月牙弧 + 一道激光刃光扫过整列.
		#   非 cyber-beam-sweep (那是赛博激光束, 视觉不对): 这是【剑在横扫】, 激光能量色月牙刃 (规格.md:31-36).
		var sweep_tgts: Array = []
		for _se in result_effects:
			if _se is Dictionary and str(_se.get("kind", "")) == "damage":
				var sti: int = int(_se.get("target_idx", -1))
				if sti >= 0 and sti != actor_idx and not sweep_tgts.has(sti):
					sweep_tgts.append(sti)
		_play_slash_sweep(actor_idx, sweep_tgts, Color("#7df5ff"), 1.25)   # 激光能量青色刃光
	else:
		_play_skill_vfx(skill_type, target_idx)   # 技能特效 (有映射的)

	# 技能进 CD (cd > 0 才进)
	var skill_cd: int = skill.get("cd", 0)
	if skill_cd > 0:
		skill["cdLeft"] = skill_cd
	# on-hit 链 (PoC passive-triggers): 通用吸血 / 神罚 / 磐石反伤 / 怒气 / 流血 / 岩层
	var bonus_effects: Array = []
	var lifesteal_total: int = 0
	var ap = actor.get("passive", null)
	for eff_r in result_effects:
		if eff_r.get("kind", "") != "damage":
			continue
		var dmg_v: int = eff_r["value"]
		var ti: int = eff_r["target_idx"]
		# 落地段数: 计数/概率类 on-hit proc 按段触发 (1:1 PoC — triggerOnHitEffects 在 for i<hits 内每段一次).
		#   线性类 (吸血/怒气/审判%/反伤/财宝) 仍按聚合 dmg_v 跑一次 (per-hit 累加 == 聚合, 不改平衡).
		var seg_hits: int = maxi(1, int(eff_r.get("hits", 1)))
		# 宝箱雷刃满层引爆: effect 带 lightning flag → 天降闪电 VFX
		if eff_r.get("lightning", false):
			_play_lightning_strike(ti)
		var tgt_f: Dictionary = fighters[ti]
		_accumulate_attack_rage(actor, dmg_v)
		# 通用吸血: 造成伤害 × lifestealPct → 治疗自己 (核心机制, 原完全没触发)
		if actor.get("lifestealPct", 0.0) > 0:
			lifesteal_total += roundi(dmg_v * actor.get("lifestealPct", 0.0))
		# relic[guwu] type bond: hp<50% -> relic-bond lifesteal doubles (extra +base once; only the relic portion, other sources unaffected)
		var relic_ls_base: float = float(actor.get("_relicLifestealBase", 0.0))
		if relic_ls_base > 0.0 and float(actor.get("hp", 0)) < float(actor.get("maxHp", 1)) * 0.5:
			lifesteal_total += roundi(dmg_v * relic_ls_base)
		# 宝箱龟 chestTreasure: 造成伤害 → 财宝累积 + 越阈值开箱(抽装备/设flag/回血) 1:1 PoC processChestTreasureGain
		if ap is Dictionary and ap.get("type", "") == "chestTreasure":
			var chest_fx: Array = EquipmentRuntime.process_chest_treasure_gain(actor, dmg_v, fighters)
			for cfx in chest_fx:
				var cti: int = int(cfx.get("target_idx", -1))
				if cti < 0:
					continue
				if cfx.get("kind", "") == "heal":
					_spawn_float_text(cti, int(cfx.get("value", 0)), "heal")
					_refresh_slot(cti)
				else:
					_spawn_passive_text(cti, str(cfx.get("label", "📦")))
		# 天使审判 judgement: 1:1 PoC triggerOnHitEffects — 每【物理段】命中各追加目标当时HP×hpPct%魔法.
		#   折进对应基础段: 该段血条 hp_after 多掉 judgment + 同段挂白魔法飘字(红物理+白魔法同 hit 各自跳).
		#   → 血条逐段下降【含】judgment (原把N段judgment聚合成1条魔法effect = 只掉一大段, 用户F5抓到).
		#   真伤段不触发(PoC angelEquality 第3段真伤无 triggerOnHitEffects), 仅把累计 judgment 反映到其 hp_after.
		#   无 segments 的单发判定技能 → 退回聚合飘字(单段无所谓).
		if ap is Dictionary and ap.get("type", "") == "judgement" \
				and tgt_f.get("side", "") != actor.get("side", ""):
			var jbase_segs: Array = eff_r.get("segments", [])
			if jbase_segs.size() >= 2:
				var j_cum: int = 0
				for jbs in jbase_segs:
					if not tgt_f.get("alive", false):
						break
					var jbsd: Dictionary = jbs
					if str(jbsd.get("dmg_type", "physical")) != "true":
						var j_raw: int = roundi(float(tgt_f.get("hp", 0)) * float(ap.get("hpPct", 11)) / 100.0 * Damage.calc_dmg_mult(Damage.calc_eff_mr(actor, tgt_f)))   # 审判吃目标魔抗减免 (原漏, PoC passive-triggers.ts:495)
						if j_raw > 0:
							var jshown: int = int(Damage.apply_raw_damage(tgt_f, j_raw, "magic")["hpLoss"])
							if jshown > 0:
								j_cum += jshown
								var jefs: Array = jbsd.get("extra_floats", [])
								jefs.append({"value": jshown, "dmg_type": "magic", "is_crit": false, "y_off": 22.0})
								jbsd["extra_floats"] = jefs
								# 天使平等吸血含【判定】部分 (1:1 PoC doLifesteal(shown+jDelta); 物理部分handler已逐段吸, 真伤不吸)
								if skill_type == "angelEquality" and actor.get("alive", false):
									var jbh: int = actor.get("hp", 0)
									actor["hp"] = mini(actor.get("maxHp", 0), jbh + Buffs.fatigue_amt(actor, roundi(jshown * float(skill.get("lifestealPct", 10)) / 100.0)))
									var jah: int = actor["hp"] - jbh
									if jah > 0:
										bonus_effects.append({"target_idx": actor_idx, "value": jah, "kind": "heal", "delay": float(jbsd.get("delay", 0.0)) + 0.12})
					# 每段 hp_after 反映累计 judgment (物理段含本段, 真伤段含之前全部) → 血条逐段含审判
					jbsd["hp_after"] = maxf(0.0, float(jbsd.get("hp_after", tgt_f.get("hp", 0))) - j_cum)
			else:
				var j_total: int = 0
				for _jh in range(seg_hits):
					if not tgt_f.get("alive", false):
						break
					var j_raw2: int = roundi(float(tgt_f.get("hp", 0)) * float(ap.get("hpPct", 11)) / 100.0 * Damage.calc_dmg_mult(Damage.calc_eff_mr(actor, tgt_f)))   # 审判吃目标魔抗减免 (原漏)
					if j_raw2 <= 0:
						continue
					j_total += int(Damage.apply_raw_damage(tgt_f, j_raw2, "magic")["hpLoss"])
				if j_total > 0:
					bonus_effects.append({"target_idx": ti, "value": j_total, "kind": "damage", "dmg_type": "magic", "is_crit": false})
		# 磐石之躯 stoneWall: 受击反弹【受到伤害 × pct%】给攻击者(物理, 吃攻击者护甲减免) — pct = base + perDef×def + perMr×mr
		#   (原 bug: 把 pct 当定值反弹且按 magic 无减免, 完全忽略 incomingDmg; PoC combat.js:646-659 / passive-triggers.ts:155-161)
		var tp = tgt_f.get("passive", null)
		if tp is Dictionary and tp.get("type", "") == "stoneWall" and actor.get("alive", false) \
				and actor.get("side", "") != tgt_f.get("side", ""):
			var sw_pct: float = float(tp.get("reflectBase", 5)) + float(tgt_f.get("def", 0)) * float(tp.get("reflectPerDef", 1)) + float(tgt_f.get("mr", tgt_f.get("def", 0))) * float(tp.get("reflectPerMr", 0.5))
			var refl_raw: int = roundi(float(eff_r.get("value", 0)) * sw_pct / 100.0)
			if refl_raw > 0:
				var refl_final: int = maxi(1, Damage.calc_damage(tgt_f, actor, float(refl_raw), "physical"))   # 吃攻击者护甲减免 (PoC calcDmgMult(calcEffArmor(target,attacker)))
				var rd: int = Damage.apply_raw_damage(actor, refl_final, "physical")["hpLoss"]
				if rd > 0:
					bonus_effects.append({"target_idx": actor_idx, "value": rd, "kind": "damage", "dmg_type": "physical", "is_crit": false})
		# 物理羁绊 tier3: 物理攻击附加流血 (PoC passive-triggers.ts:275-278 — 每段命中各叠 1 层
		#   max(1, round(atk×0.08)); Phaser PoC 已去掉 JS combat.js:559 的 per-cast dedup flag → per-hit).
		if actor.get("_synergyPhysBleed", false) and eff_r.get("dmg_type", "") == "physical" and tgt_f.get("alive", false) and dmg_v > 0:
			var bleed_amt: int = maxi(1, roundi(actor.get("atk", 0) * 0.08))
			for _bh in range(seg_hits):
				Dot.apply_stacks(tgt_f, "bleed", bleed_amt)
		# 磐石: 标准攻击命中 → +1 岩层 (cap 30) — PoC passive-triggers.ts:228 每段 +1 (在 triggerOnHitEffects 内)
		if tgt_f.get("_hasRockArmor", false):
			for _rh in range(seg_hits):
				if int(tgt_f.get("_rockLayers", 0)) >= 30:
					break
				tgt_f["_rockLayers"] = int(tgt_f.get("_rockLayers", 0)) + 1
		# on-hit 链其余项 (结晶/反伤buff/陷阱/反击/受击盾/半血盾/竹蓄/泡缚/装备眩晕反伤多击/赌徒连击)
		#   seg_hits = 落地段数; _on_hit_chain 内仅计数/概率类按段循环, 反伤/反击类仍按聚合 dmg 跑一次.
		_on_hit_chain(actor, tgt_f, dmg_v, eff_r.get("dmg_type", ""), actor_idx, ti, bonus_effects, seg_hits)
	# 吸血治疗自己
	if lifesteal_total > 0 and actor.get("alive", false):
		var lb: int = actor.get("hp", 0)
		actor["hp"] = mini(int(actor.get("maxHp", 0)), lb + lifesteal_total)
		var actual_ls: int = int(actor["hp"]) - lb
		if actual_ls > 0:
			# 吸血专属反馈 (用户点名"吸血没特效"): 攻击者处绿色治疗光 (vfx:lifesteal → _play_lifesteal_glow) +
			#   "🩸+N" 绿字 → 玩家看得出"触发了吸血"。满血时 actual_ls=0 静默 (1:1 PoC 忠实, 不改回血逻辑)。
			bonus_effects.append({"target_idx": actor_idx, "value": actual_ls, "kind": "heal", "vfx": "lifesteal"})
		# e_star 生命偷取海星: 溢出治疗(满血部分) _equipStarOverflow% 转护盾 (1:1 PoC passive-triggers.ts:606-609)
		var star_pct: int = int(actor.get("_equipStarOverflow", 0))
		if star_pct > 0 and lifesteal_total > actual_ls:
			var star_sh: int = roundi(float(lifesteal_total - actual_ls) * star_pct / 100.0)
			actor["shield"] = int(actor.get("shield", 0)) + star_sh
			if star_sh > 0:
				bonus_effects.append({"target_idx": actor_idx, "value": star_sh, "kind": "shield", "vfx": "shieldglow"})   # 溢出转盾可见化 (原静默) — 需F5
		# 饮血护符坠 011: 溢出治疗 → 血护盾 (累积 cap _p2BloodShieldCap)
		var blood_cap: int = int(actor.get("_p2BloodShieldCap", 0))
		if blood_cap > 0 and lifesteal_total > actual_ls:
			var blood_cur: int = int(actor.get("_p2BloodShieldCur", 0))
			var blood_add: int = mini(lifesteal_total - actual_ls, blood_cap - blood_cur)
			if blood_add > 0:
				actor["shield"] = int(actor.get("shield", 0)) + blood_add
				actor["_p2BloodShieldCur"] = blood_cur + blood_add
				bonus_effects.append({"target_idx": actor_idx, "value": blood_add, "kind": "shield", "vfx": "shieldglow"})   # 011 血盾溢出转盾可见化 (原静默) — 需F5
	for be in bonus_effects:
		result_effects.append(be)
	var actor_equips: Array = actor.get("_equipped_ids", [])
	var p2_extra: Array = []   # 二阶段装备 on_hit/on_cast 派生效果: 循环外 flush, 不在迭代中 append → 防级联
	for eff_d in result_effects:
		if eff_d.get("kind", "") != "damage":
			continue
		var t_idx_e: int = eff_d["target_idx"]
		var dmg_v: int = eff_d["value"]
		var hit_target: Dictionary = fighters[t_idx_e]
		# 法器·法力: 受害者若带法器 → 受伤值 ×0.1 入其每件法器法力 (≠龟能)。
		#   走 result_effects 技能伤害口 → 法器自身效果伤害(burn DoT 等走 side-end Dot, 不在此口)自动不计, 防连放。
		if hit_target.get("_staff_mana") is Dictionary and not (hit_target["_staff_mana"] as Dictionary).is_empty() and dmg_v > 0:
			Phase2EquipRuntime.staff_on_damaged(hit_target, float(dmg_v))
			_refresh_staff_mana_for(hit_target)
		# 盾[守护]怒气: 受害者带盾 → 每【次受伤】+盾件数怒气, 满10 → 冲击波(对一敌真伤+自盾)。一伤害实例调一次。
		if float(hit_target.get("_shieldRageThr", 0.0)) > 0.0 and dmg_v > 0:
			p2_extra.append_array(Phase2EquipRuntime.shield_rage_on_damaged(hit_target, fighters))
		# 落地段数: 计数型装备 proc (e_blade 流血叠层 / e_carapace 受击叠甲) 按段触发 (1:1 PoC per-hit);
		#   per-cast 型 (e_fire 灼烧) 仅第 1 段 (is_first_hit_this_skill=true) 触发一次.
		var eff_hits: int = maxi(1, int(eff_d.get("hits", 1)))
		# attacker 装备 onHit
		for eq_id in actor_equips:
			for h in range(eff_hits):
				var proc_effects: Array = EquipmentRuntime.on_hit(actor, hit_target, dmg_v, eq_id, fighters, h == 0)
				for pe in proc_effects:
					result_effects.append(pe)
		# 二阶段装备 on_hit (海藻流血/鲨齿溅射/暴君处决/双生追击/宽刃刃能) → p2_extra (循环外 flush)
		for p2 in actor.get("_p2_equips", []):
			for h3 in range(eff_hits):
				p2_extra.append_array(Phase2EquipRuntime.on_hit(actor, hit_target, dmg_v, str(p2["id"]), int(p2["star"]), fighters, h3 == 0))
		# target 装备 onHitAsTarget
		var target_equips: Array = hit_target.get("_equipped_ids", [])
		for eq_id_t in target_equips:
			for h2 in range(eff_hits):
				var proc_effects_t: Array = EquipmentRuntime.on_hit_as_target(hit_target, actor, dmg_v, eq_id_t, fighters)
				for pet in proc_effects_t:
					result_effects.append(pet)
		# 二阶段装备 on_hit_as_target (硬化叠甲/奶最低血友军) → p2_extra
		for p2t in hit_target.get("_p2_equips", []):
			for h4 in range(eff_hits):
				p2_extra.append_array(Phase2EquipRuntime.on_hit_as_target(hit_target, actor, dmg_v, str(p2t["id"]), int(p2t["star"]), fighters))
		# 雷盾 lightningShield: 持盾受击 → 反击攻击者 round(atk×counterScale) 魔法 + 叠 1 层电击
		if hit_target.get("_lightningShieldCounter", 0.0) > 0 and int(hit_target.get("shield", 0)) > 0 \
				and actor.get("alive", false) and actor.get("side", "") != hit_target.get("side", ""):
			var cdmg: int = Damage.calc_damage(hit_target, actor, hit_target.get("atk", 0) * hit_target.get("_lightningShieldCounter", 0.1), "magic")
			var cr: Dictionary = Damage.apply_raw_damage(actor, cdmg, "magic")
			var cshown: int = cr["hpLoss"] + cr["shieldAbs"]
			if cshown > 0:
				result_effects.append({"target_idx": actor_idx, "value": cshown, "kind": "damage", "dmg_type": "magic", "is_crit": false})
			SkillHandlers._lightning_apply_shock(hit_target, actor, fighters, result_effects)

	# 二阶段装备 on_cast (千刃排穿/阔剑横排盾/珊瑚最远敌): 每次施法一次, 循环外 append → 不再触发 on_hit
	for p2c in actor.get("_p2_equips", []):
		p2_extra.append_array(Phase2EquipRuntime.on_cast(actor, str(p2c["id"]), int(p2c["star"]), fighters))
	for pe2 in p2_extra:
		result_effects.append(pe2)

	# 视觉: 每个 effect 一条飘字 + 刷新槽位 + 暴击 hit-stop + 震屏分级
	#   多段同目标伤害(chestStorm等发独立effect)合并成 segments 错开显示 → 修"节奏全挤一帧/血条trail互kill"
	var effects: Array = _coalesce_multihit_segments(result_effects, float(skill.get("hitStaggerMs", 500)) / 1000.0)
	# 逐段演出时长: 等所有 segments 飘完再判死亡/换下一个 (1:1 PoC await 完整动画; 防"技能没放完就出手 / 血没空就倒下")
	var _seg_t0: int = Time.get_ticks_msec()
	var _seg_end: float = 0.0
	for _se in effects:
		if _se is Dictionary:
			# 投射物落地延迟叠在各段 delay 之上 → 等待时长须含它, 否则子弹还在飞就判死/换手 (节奏脱节)
			var _se_arr: float = maxf(0.0, float(_se.get("arrival_delay", 0.0)))
			var _segs_se: Array = _se.get("segments", [])
			if _segs_se.is_empty() and _se_arr > 0.0 and _se.get("kind", "") == "damage":
				_seg_end = maxf(_seg_end, _se_arr)   # 单发投射(无并段): 落地延迟本身就是显示时点
			for _sg in _segs_se:
				_seg_end = maxf(_seg_end, _se_arr + float((_sg as Dictionary).get("delay", 0.0)))
	for eff in effects:
		var t_idx: int = eff["target_idx"]
		var v: int = eff.get("value", 0)   # passive/miss 类可能无 value
		var kind: String = eff["kind"]
		var dmg_type_eff: String = eff.get("dmg_type", "physical")
		var is_crit_eff: bool = eff.get("is_crit", false)
		# 水晶光束 VFX 标记 (迷你水晶球 030 沿列): 纯标记 — 从 vfx_from 朝目标射线性束后跳过 (不飘字)
		if str(eff.get("vfx", "")) == "crystalbeam":
			_play_crystal_beam(int(eff.get("vfx_from", -1)), t_idx)
			continue
		# 迷你水晶球 031 旋转扫描束: 从 vfx_from 旋转 180° 扫全敌 (纯标记)
		if str(eff.get("vfx", "")) == "minicrystalbeam":
			_play_mini_crystal_beam(int(eff.get("vfx_from", -1)))
			continue
		# 霰弹贝 053 扇形弹幕: 从 vfx_from 中心 40° 扇形发 N 发弹珠 + 枪口火光 (纯标记)
		if str(eff.get("vfx", "")) == "shotgun":
			_play_shotgun_blast(int(eff.get("vfx_from", -1)), int(eff.get("vfx_pellets", 12)))
			continue
		# 竹叶 039 生命球: 绿球从 vfx_from(被击敌) 抛物线飞回携带者(回血/永久生命) — 同竹叶龟充能追击 (纯标记)
		if str(eff.get("vfx", "")) == "bambooorb":
			_spawn_bamboo_orb(int(eff.get("vfx_from", -1)), t_idx)
			continue
		# 枪系直线弹/弩箭 (048手铳/049弩/050加特林): 枪口火光 + 直线弹珠从携带者飞向目标 (纯标记, 不飘字)
		#   vfx_delay>0 → 逐发错开发射 (048/050 连发, 每颗都看得到); fire-and-forget 不阻塞主循环.
		if str(eff.get("vfx", "")) == "gunshot":
			var _gs_from: int = int(eff.get("vfx_from", -1))
			var _gs_path: String = str(eff.get("vfx_path", ""))
			var _gs_size: float = float(eff.get("vfx_size", 16.0))
			var _gs_dur: float = float(eff.get("vfx_dur", 0.18))
			var _gs_delay: float = float(eff.get("vfx_delay", 0.0))
			if _gs_delay > 0.0:
				_play_gun_shot_delayed(_gs_from, t_idx, _gs_path, _gs_size, _gs_dur, _gs_delay)   # 错开发射 (await 内含, 不阻塞: call_deferred 式)
			else:
				_play_gun_shot(_gs_from, t_idx, _gs_path, _gs_size, _gs_dur)
			continue
		# 枪系激光束 (051激光手枪红束/057狙击青白细束): 从携带者朝目标射一道光束 (纯标记, 不飘字)
		#   vfx_pierce → 沿 from→target 方向延长贯穿到屏幕边缘 (057 狙击穿透感, 射到尽头).
		if str(eff.get("vfx", "")) == "laserbeam":
			_play_laser_beam(int(eff.get("vfx_from", -1)), t_idx, Color(str(eff.get("vfx_color", "#ff3838"))), float(eff.get("vfx_width", 7.0)), float(eff.get("vfx_dur", 0.30)), bool(eff.get("vfx_pierce", false)))
			continue
		# 穿甲遗弹 058 贯穿: 一道穿透弹从携带者飞过前敌打到身后同列敌 (纯标记, 不飘字)
		if str(eff.get("vfx", "")) == "gunpierce":
			_play_gun_pierce(int(eff.get("vfx_from", -1)), t_idx, str(eff.get("vfx_path", "")))
			continue
		# 剑系斩击弧 (005双生匕首/011饮血护符坠 等单体斩): 目标处月牙刃光, 方向=携带者→目标.
		#   vfx_from=携带者idx (无则用 actor_idx). vfx_color=刃光色(吸血红/锈灰等). 本身是伤害effect, 不 continue → 继续飘字.
		if str(eff.get("vfx", "")) == "slash":
			var sc_from: int = int(eff.get("vfx_from", actor_idx))
			_play_slash_at(t_idx, Color(str(eff.get("vfx_color", "#e8eef5"))), sc_from, float(eff.get("vfx_scale", 1.0)))
		# 火球 proc VFX (生命珍珠 e_pearl 等): 从 vfx_from 飞向本 effect 目标 (fire-and-forget, 不阻塞飘字)
		if str(eff.get("vfx", "")) == "fireball":
			_play_fireball(int(eff.get("vfx_from", -1)), t_idx)
		# 链式闪电 (雷电法杖 026): 从上一目标画锯齿闪电到本目标 (本身是真伤effect, 不 continue → 继续飘字)
		#   chain_idx = 第几跳 → 渲染延 chain_idx*0.22s 错峰亮 (1:1 PoC idx*220ms 链式逐跳). 飘字/血条也随之逐跳延 (见下 arr_base, 数值不动).
		if str(eff.get("vfx", "")) == "chainbolt":
			_play_chain_bolt(int(eff.get("vfx_from", -1)), t_idx, int(eff.get("chain_idx", 0)))
		# 天降闪电 (电棍 027 等 lightning): 命中目标处劈下 (本身是伤害effect, 不 continue → 继续飘字)
		if str(eff.get("vfx", "")) == "lightning":
			_play_lightning_strike(t_idx)
		# 弓箭[神射手]羁绊处决 / 暴君之牙处决 (004): 目标处斩首白闪 (ghost-touch + 白闪 + 小震; 本身是真伤effect, 不 continue)
		if str(eff.get("vfx", "")) == "execute":
			_play_execute_flash(t_idx)
		# 火焰喷溅 (022余烬燃油瓶/023灼热火珊瑚每段灼烧标记): 目标处橙红火焰喷吐 (纯VFX标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "flameburst":
			_play_flame_burst(t_idx)
			continue
		# 血滴溅射 (002海带卷刀/015荆棘海胆 命中流血标记): 目标处红血滴喷溅 (纯VFX标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "blood":
			_play_blood_splatter(t_idx)
			continue
		# 冰晶/寒霜爆点 (028冰霜冻露瓶魔法+冰寒 / 029冰封水母额外魔法冻结标记): 目标处冰封冻结闪 (纯VFX标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "freeze":
			_play_freeze_flash(t_idx)
			continue
		# 盾[守护]怒气冲击波: 目标处扩散冲击波环 (双层 _play_aoe_ring 由内向外 + 震屏; "波"=扩散环, 比砸击帧贴切; 本身是真伤effect, 不 continue)
		if str(eff.get("vfx", "")) == "shockwave":
			_play_aoe_ring(t_idx, Color(0.62, 0.82, 1.0, 0.6))   # 内圈淡蓝冲击波
			_play_aoe_ring(t_idx, Color(0.9, 0.96, 1.0, 0.35))   # 外圈白雾扩散
			_play_screen_shake(0.16, 9.0)
		# 盾[守护]怒气自获护盾: 携带者处真盾光护罩 (_play_shield_glow 盾蓝护罩环+底光; 本身是 shield effect)
		if str(eff.get("vfx", "")) == "shieldgain":
			_play_shield_glow(t_idx)
		# 护盾光 (013炙烤海胆满层/036温泉蛋满级 等护盾 effect; 本身是 shield effect, 不 continue → 续飘字)
		if str(eff.get("vfx", "")) == "shieldglow":
			_play_shield_glow(t_idx)
		# 治疗绿光 (044深海项链首次<50% 等回血 effect; 本身是 heal effect, 不 continue → 续飘字)
		if str(eff.get("vfx", "")) == "healglow":
			_play_heal_glow(t_idx)
		# 吸血专属反馈 (用户点名): 攻击者处吸血绿光 + 红血滴 (复用 _play_heal_glow + 血滴环, 不造新资源)。
		#   本身是 heal effect, 不 continue → 续飘"+N"绿字, 玩家看得出触发了吸血。
		if str(eff.get("vfx", "")) == "lifesteal":
			_play_lifesteal_glow(t_idx)
		# 连接光链 (021守护贝母连接友军: 携带者→友军青蓝能量链; 本身常伴 shield effect, 不 continue → 续飘字)
		if str(eff.get("vfx", "")) == "shieldlink":
			_play_link_chain(int(eff.get("vfx_from", -1)), t_idx)
			_play_shield_glow(t_idx)
		# 剑[回响]: 目标处二次斩击弧 (_play_slash_at 月牙刃光; 剑该是斩击弧非砸击帧. vfx_from=携带者→刃光方向, 银白回响色, 略小0.85; 本身是真伤effect, 不 continue)
		if str(eff.get("vfx", "")) == "swordecho":
			_play_slash_at(t_idx, Color("#d8e6f5"), int(eff.get("vfx_from", actor_idx)), 0.85)
		# 枪[神枪手]金弹: 携带者→目标金色子弹弹道 (金弹是子弹该走弹道非砸击; vfx_from=枪携带者idx) + 命中金环 (本身是伤害effect, 不 continue → 继续飘字)
		if str(eff.get("vfx", "")) == "goldbullet":
			_play_gold_bullet(int(eff.get("vfx_from", actor_idx)), t_idx)
		# ── 批6 杂项 VFX 标记 ──
		# 008 双穿珊瑚刺: 携带者→最远敌 细长珊瑚刺穿刺射线 (纯标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "coralpierce":
			_play_coral_pierce(int(eff.get("vfx_from", actor_idx)), t_idx)
			continue
		# 014 深海堡垒: 敌→携带者 紫色魔法吸取束 (纯标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "drainbeam":
			_play_drain_beam(int(eff.get("vfx_from", -1)), t_idx)
			continue
		# 017 不沉之锚: 携带者→最前敌 铁锚砸击 + 锚链 (纯标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "anchorslam":
			_play_anchor_slam(int(eff.get("vfx_from", actor_idx)), t_idx)
			continue
		# 055 靶向器: 目标处红色准星十字标记 (纯标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "reticle":
			_play_target_reticle(t_idx)
			continue
		# 003 锋利鲨齿: 主命中目标撕咬白闪 (纯标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "bite":
			_play_bite_flash(t_idx)
			continue
		# 003 锋利鲨齿: 邻格受溅射处白色溅射弧 (纯标记, 不飘字 → continue)
		if str(eff.get("vfx", "")) == "splashring":
			_play_aoe_ring(t_idx, Color(0.95, 0.96, 1.0, 0.5))
			continue
		# 046 幽灵墨鱼: 闪避→墨汁烟雾 + 盾光 (本身是 shield effect, 不 continue → 续飘字"+N盾")
		if str(eff.get("vfx", "")) == "inkdodge":
			_play_ink_dodge(t_idx)
			_play_shield_glow(t_idx)
		# passive kind (diceFate/diamondFortify 等) 用 label 飘绿字, 不走伤害飘字
		if kind == "passive":
			# 控制类施加闪 (眩晕/冻结): passive 标可带 flash="freeze" → 同飘 label 同播冰罩闪 (前面 vfx=="freeze" 分支会 continue 吞掉 label, 故走独立 flash 字段)。
			if str(eff.get("flash", "")) == "freeze":
				_play_freeze_flash(t_idx)
			_spawn_passive_text(t_idx, eff.get("label", "+%d" % v), str(eff.get("color", "")))   # 可选 color (换形紫/金等)
			_refresh_slot(t_idx)
			continue
		# 局内统计埋点 (PoC battleStats.recordDamage/Heal/Shield) — 攻击者按侧归属:
		#   命中敌方 → actor; 反伤/反噬打到本侧 → caster=null(只记承受方)
		#   立即按聚合值记录 (不随飘字 stagger), 避免多段时序影响统计准确性。
		var st_tgt: Dictionary = fighters[t_idx]
		if kind == "damage":
			var st_caster = actor if st_tgt.get("side", "") != actor.get("side", "") else null
			battle_stats.record_damage(st_caster, st_tgt, v, _stat_type(dmg_type_eff))
			# 暴击列: 多段(并段)技能按【每段命中】各记一次暴击 (1:1 PoC actor.stats.crits++ per hit) —
			#   原只看 merged is_crit_eff 记 1 次 → 多段全暴只记 1 (低估). 单段无 segments 时 fallback 单记.
			if st_caster != null:
				var _crit_segs: Array = eff.get("segments", [])
				if not _crit_segs.is_empty():
					for _cs in _crit_segs:
						if bool((_cs as Dictionary).get("is_crit", false)):
							battle_stats.record_crit(st_caster)
				elif is_crit_eff:
					battle_stats.record_crit(st_caster)   # 结算面板"暴击"列 (1:1 PoC)
		elif kind == "heal":
			battle_stats.record_heal(actor, st_tgt, v)
		elif kind == "shield":
			battle_stats.record_shield(st_tgt, v)
		# 多段伤害(segments): 逐段错开飘字 + 血条逐段下降 (1:1 PoC 每 hit 一个 floatNum + 段间 sleep)。
		#   段数据由 handler 提供(value/dmg_type/is_crit/delay/y_off/hp_after/shield_after)。无段→单条(原行为)。
		var segs: Array = eff.get("segments", [])
		# 投射物落地延迟: 枪弹/弩箭/霰弹弹珠 是纯视觉飞行, 伤害飘字+血条 step 须延到子弹落地时刻才显
		#   (修"血在子弹落地前就掉"脱节)。气波同理(波头到达目标才掉血)。两者都把延迟叠到各段 delay 基线。
		var arr_base: float = 0.0
		if skill_type == "basicChiWave":
			arr_base = _chiwave_arrival_delay(actor_idx, target_idx, t_idx)
		elif str(eff.get("vfx", "")) == "chainbolt":
			# 链式闪电 (雷电法杖 026): 飘字+血条随逐跳闪电亮起的时刻显 — 第 idx 跳延 idx*0.22s (1:1 _play_chain_bolt 逐跳延, 数值不动)。
			arr_base = float(int(eff.get("chain_idx", 0))) * 0.22
		elif eff.has("arrival_delay"):
			arr_base = maxf(0.0, float(eff.get("arrival_delay", 0.0)))
		if kind == "damage" and not segs.is_empty():
			if arr_base > 0.0:
				var shifted: Array = []
				for sg in segs:
					var sg2: Dictionary = (sg as Dictionary).duplicate()
					sg2["delay"] = float(sg2.get("delay", 0.0)) + arr_base
					shifted.append(sg2)
				segs = shifted
			_play_damage_segments(t_idx, segs, actor.get("side", "left"), skill_type in _NO_HIT_KNOCK)
		elif kind == "damage" and arr_base > 0.0:
			# 单发投射物伤害 (无并段): 把飘字+血条 step+juice 整体延到落地时刻 — 复用 segments 机制(delay=arr_base)。
			_play_damage_segments(t_idx, [{"value": v, "dmg_type": dmg_type_eff, "is_crit": is_crit_eff, "delay": arr_base}], actor.get("side", "left"), skill_type in _NO_HIT_KNOCK)
		else:
			_spawn_float_text(t_idx, v, kind, dmg_type_eff, is_crit_eff)
			_refresh_slot(t_idx)
			if kind == "damage":
				_flash_hit(t_idx)
				if not (skill_type in _NO_HIT_KNOCK):
					_hit_knockback(t_idx, actor.get("side", "left"))
				# Juice (Phaser BattleScene:2795-2798 同款):
				#   暴击 → hit-stop 70ms + 大震 150ms
				#   非暴击但伤害 > 12% target.maxHp → 中震 110ms
				var target_max_hp: float = fighters[t_idx]["maxHp"]
				var hp_ratio: float = float(v) / target_max_hp
				if is_crit_eff:
					_play_hit_stop(VisualConstants.HIT_STOP_MS_CRIT)
					_play_screen_shake(VisualConstants.SHAKE_CRIT_DURATION, VisualConstants.SHAKE_CRIT_STRENGTH)
					_spawn_crit_label(t_idx)
				elif hp_ratio > VisualConstants.BIG_HIT_HP_RATIO:
					_play_screen_shake(VisualConstants.SHAKE_BIG_DURATION, VisualConstants.SHAKE_BIG_STRENGTH)

	# 日志: 按结果 type 决定整条颜色 (伤害红 / 治疗绿 / 护盾蓝)
	var log_text_raw: String = result.get("log_text", "")
	var color_tag: String = "#ff8c8c"
	if result["type"] == "heal":
		color_tag = "#3cd97a"
	elif result["type"] == "shield":
		color_tag = "#5cb8ff"
	battle_log.append_text("[color=%s]%s[/color]\n" % [color_tag, log_text_raw])

	# ── 命中后演出 (caster 归位 / target 击飞抛投), 1:1 PoC ──
	#   juggle 把 target 节点弹起→倒地→走回 home, 跑完才让 _play_death 播 (节点已回到 home → 死亡旋转干净)
	await _skill_post_impact(actor_idx, target_idx, skill_type)

	# 等逐段飘字/弹幕全部放完(扣除已耗的演出时间)再判死亡/换下一个 — 多段技能(弹幕/气波/火山)必须等满
	if not auto_play_debug and _seg_end > 0.0:
		var _seg_remain: float = _seg_end + 0.15 - float(Time.get_ticks_msec() - _seg_t0) / 1000.0
		if _seg_remain > 0.0:
			await get_tree().create_timer(_seg_remain).timeout

	# 死亡 (任何 effect 把目标打死了就播) — 同批多龟连死: 先做各自记账(击杀/日志/羁绊), 再【并行】播死亡, 不逐只串行卡。
	var _dead_idxs: Array = []
	for eff in effects:
		var t_idx: int = eff["target_idx"]
		if not fighters[t_idx]["alive"] and eff["kind"] == "damage" and not _dead_idxs.has(t_idx):
			_dead_idxs.append(t_idx)
			battle_log.append_text("  [color=#ff6b6b]☠ %s 阵亡[/color]\n" % fighters[t_idx]["name"])
			# 统计击杀 (敌方死亡归功 actor) — PoC battleStats.recordKill
			if fighters[t_idx].get("side", "") != actor.get("side", ""):
				_award_and_record_kill(actor, fighters[t_idx])
			# 刺杀羁绊: 击杀 → 全队 +5% baseAtk 永久 (PoC passive-triggers.ts:282-290, 是整队不止攻击者)
			if actor.get("_synergyAssassinKillBonus", false) and fighters[t_idx].get("side", "") != actor.get("side", ""):
				if Synergies.apply_assassin_kill_bonus(_alive_allies_of(actor)):
					battle_log.append_text("[color=#c084fc]🗡 刺杀协同: 全队 +5% ATK[/color]\n")
	if not _dead_idxs.is_empty():
		# 死亡时机根治: 先等各致命那一下的血条 step (队列里, 受 _DISP_MIN_GAP 错峰) 显示完 → 血条走到 0。
		for _di in _dead_idxs:
			await _await_display_drained(_di)
		# 并行播死亡: bare-call void 协程(各自起死亡 tween 后挂起), 一起跑 → 多龟连死不串行卡(死3只≈1.2s 不是 ~11s)。
		for _di in _dead_idxs:
			_play_death(_di)
		await get_tree().create_timer(1.25).timeout   # 统一等最长一段死亡演出跑完 (≈1.2s deathHop)

	# 竹叶龟 生长: 持充能时, 技能后追加一发强化魔法攻击 (PoC fireBambooChargeIfReady:3244)
	await _fire_bamboo_charge(actor_idx, target_idx)
	# 施法后装备 (电棍/竹叶 等 post-cast, 1:1 PoC processSkillEquipEffects:3125): 渲染飘字+VFX+死亡
	await _apply_equip_post_cast(actor_idx, target_idx, not (skill_type in SKILL_AOE))
	actor.erase("_castIsAoe")   # 清雷电法杖 AOE 标志, 防泄漏到下次

	_check_revives()   # 凤凰涅槃: 死亡后立即复活 (在 _check_end 判负之前)

	# 换位 (starGravityWarp 满星): fighter._slotKey 已改, 重新摆放视图
	if result.get("relayout", false):
		_relayout_slots()

	# hidingCommand: 让随从立即额外行动一次 (本回合随从共出手 2 次)
	if result.get("command_summon", false):
		var summon = actor.get("_summon", null)
		if summon is Dictionary and summon.get("alive", false):
			await _summon_act(fighters.find(summon))


## 装备效果 VFX 分发 (回合末/post-cast 装备演出): key → 在 target 处播对应特效
func _play_equip_vfx(vfx_key: String, target_idx: int) -> void:
	if vfx_key == "" or target_idx < 0 or target_idx >= slot_nodes.size():
		return
	match vfx_key:
		"lightning":
			_play_lightning_strike(target_idx)   # 天降闪电 (电棍/雷壳/雷杖 electric)
		"fire", "burn":
			var node: Node2D = slot_nodes[target_idx]
			var av: Sprite2D = node.get_meta("avatar", null)
			var home: Vector2 = node.get_meta("home_pos", node.position)
			var c: Vector2 = home + (av.position if av != null else Vector2(0, -50))
			_play_vfx("burn-loop", c, 1.2)
		"goldbullet":
			# 枪[神枪手]金弹: 金色子弹弹道(无 vfx_from 时只在目标处金弹爆点+金环) — 金弹是子弹该走弹道
			_play_gold_bullet(-1, target_idx)
		"shieldglow":
			# 护盾光 (012龟苓膏块/016铁壁盾/036温泉蛋满级/013炙烤海胆满层): 盾蓝护罩环+盾罩底光
			_play_shield_glow(target_idx)
		"healglow":
			# 治疗绿光 (018守护贝壳/019海葵药膏/042涟漪药剂/044深海项链): 绿色上升治疗光+绿脉冲环
			_play_heal_glow(target_idx)
		"waterripple":
			# 涟漪药剂 042: 水波涟漪 (蓝青双环外扩) + 治疗绿光 (全队回已损血)
			_play_aoe_ring(target_idx, Color(0.36, 0.72, 1.0, 0.5))
			_play_heal_glow(target_idx)
		"flameburst":
			# 火焰喷溅 (022余烬燃油瓶灼烧/023灼热火珊瑚3★火幕/037蛋糕蜡烛燃烧段): 橙红火焰喷吐 + 火闪环
			_play_flame_burst(target_idx)
		"blood":
			# 血滴溅射 (002海带卷刀/015荆棘海胆 命中流血): 红血滴喷溅
			_play_blood_splatter(target_idx)
		"freeze":
			# 冰晶/寒霜爆点 (028冰霜冻露瓶魔法+冰寒): 复用冰封冻结闪 (青蓝tint + 冰罩脉冲圈)
			_play_freeze_flash(target_idx)
		"signalaura":
			# 信号放大器 038: 自身青色信号增益脉冲环 (回合开始获临时增伤)
			_play_aoe_ring(target_idx, Color(0.36, 0.94, 1.0, 0.55))
			_play_aoe_ring(target_idx, Color(0.55, 0.78, 1.0, 0.3))
		"bitflash":
			# FPGA 板 040: 抽中时电路/比特闪 (短电闪 + 青绿方块粒子)
			_play_bit_flash(target_idx)
		_:
			pass


## 在某 slot 的角色中心播一段帧动画 VFX (复用现有 vfx 库; 羁绊触发统一入口)。
func _play_vfx_at_slot(vfx_name: String, target_idx: int, scale: float = 1.0) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var home: Vector2 = node.get_meta("home_pos", node.position)
	var c: Vector2 = home + (av.position if av != null else Vector2(0, -50))
	_play_vfx(vfx_name, c, scale)


## 学派每回合效果可见化 (远古觉醒真伤 / 军火弹幕魔法 / 各学派盾·治疗·净化): Phase2Schools.on_round_begin 已结算但静默,
##   这里逐事件按 kind 渲染: damage→飘伤害字+刷血条+受击红闪+AOE爆破VFX(远古=紫幽暴风+金环 / 军火=蓝魔法冲击);
##   shield→飘盾字+护罩(玄甲/军械奇数/血牙=蓝盾shieldglow; 圣甲圣盾=白黄亮圣光holyshieldglow); heal→飘绿字+治疗光(潮汐回血/大潮); purify→飘"净化N"+绿光(大潮净化)。
##   数值逻辑不在此处, 只渲染传入的已结算事件 (伤害=[{target_idx,amount,type,vfx}] / 盾·治疗·净化=[{...,kind,vfx}])。
func _render_school_round_damage(events: Array) -> void:
	if events == null or events.is_empty():
		return
	var _killed: Array = []   # 本批被学派AOE致死的目标 idx → 末尾统一(并行)播死亡
	for ev in events:
		if not (ev is Dictionary):
			continue
		var t_idx: int = int(ev.get("target_idx", -1))
		var amount: int = int(ev.get("amount", 0))
		if t_idx < 0 or t_idx >= slot_nodes.size() or amount <= 0:
			continue
		# 非伤害分支: 学派每回合盾/治疗/净化 (圣甲圣盾·玄甲每回合盾·军械奇数盾·血牙保命盾·潮汐回血大潮·大潮净化)
		#   原 _render_school_round_damage 只渲染 damage → 这些全静默. 现按 kind 飘字 + 绿/盾光 + 刷血条/盾条.
		var ev_kind: String = str(ev.get("kind", "damage"))
		if ev_kind == "shield":
			var sh_vfx: String = str(ev.get("vfx", ""))
			if sh_vfx == "holyshieldglow":
				# 圣甲圣盾 = 白黄亮圣光色 (区别普通蓝盾): 金白盾光 + 金色"+N盾"标
				_play_shield_glow(t_idx, _HOLY_SHIELD_COLOR)
				_spawn_passive_text(t_idx, "+%d 盾" % amount, _HOLY_SHIELD_HEX)
			else:
				_spawn_float_text(t_idx, amount, "shield")
				if sh_vfx == "shieldglow":
					_play_shield_glow(t_idx)
			_refresh_slot(t_idx)
			continue
		if ev_kind == "heal":
			_spawn_float_text(t_idx, amount, "heal")
			if str(ev.get("vfx", "")) == "healglow":
				_play_heal_glow(t_idx)
			_refresh_slot(t_idx)
			continue
		if ev_kind == "purify":
			# 净化: 无回血数字, 飘"净化 N"标 + 绿光 (减益被移除, 玩家看得见)
			_spawn_passive_text(t_idx, "净化 %d" % amount, "#7bed9f")
			if str(ev.get("vfx", "")) == "healglow":
				_play_heal_glow(t_idx)
			_refresh_slot(t_idx)
			continue
		var dmg_type: String = str(ev.get("type", "true"))
		var vfx_kind: String = str(ev.get("vfx", ""))
		# 伤害走显示调度队列 → 同目标多源有序消费, 不抢血条. HP 已由 Phase2Schools.on_round_begin 静默扣到终值 → 取作 hp_after.
		_enqueue_display(t_idx, {"kind": "damage", "value": amount, "dmg_type": dmg_type, "is_crit": false, "hp_after": float(fighters[t_idx].get("hp", 0)), "shield_after": float(fighters[t_idx].get("shield", 0))})
		# AOE 爆破特效 (按学派区分; 复用既有 VFX sprite + 几何环)
		if vfx_kind == "ancient":
			_play_vfx_at_slot("ghost-storm", t_idx, 1.2)             # 远古觉醒: 紫幽暴风裹身
			_play_aoe_ring(t_idx, Color(1.0, 0.84, 0.28, 0.55))      # 金色远古之力扩散环
		elif vfx_kind == "armory":
			# 军火弹幕: 蓝色魔法弹幕冲击 (双层蓝青冲击波环, 非 basic-slam-impact 砸击尘帧) — 远程轰击落点更对"弹幕魔法"
			_play_aoe_ring(t_idx, Color(0.7, 0.88, 1.0, 0.6))        # 内圈亮蓝弹幕冲击
			_play_aoe_ring(t_idx, Color(0.45, 0.7, 1.0, 0.35))       # 外圈蓝青扩散环
		if not fighters[t_idx].get("alive", false) and not _killed.has(t_idx):
			_killed.append(t_idx)
	# 本批致死并行收尾: 先各等其致命掉血血条 step 显示完, 再【并行】播死亡 (多龟连死不串行卡; 死亡演出本就 ~1.2s)。
	if not _killed.is_empty():
		for _k in _killed:
			await _await_display_drained(_k)
		for _k in _killed:
			_play_death(_k)   # bare-call: void 协程并行起跑(各自起死亡 tween 后挂起), 不逐只 await
		await get_tree().create_timer(1.25).timeout   # 统一等最长一段死亡演出跑完 (≈1.2s deathHop)


## AOE 扩散圆环 (无新资源: _circle_points 几何 + 扩散淡出), 给学派每回合 AOE 加一层范围感。
func _play_aoe_ring(target_idx: int, col: Color) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var ring := Polygon2D.new()
	ring.polygon = _circle_points(34.0)
	ring.color = col
	ring.position = (av.position if av != null else Vector2(0, -50))
	ring.z_index = 199
	node.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.8, 1.8), 0.34).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.34)
	rt.chain().tween_callback(ring.queue_free)


## 孵化器升级特效 (蛋裂/金光升级): 满 100 进度 → 临时等级+1 瞬间放。
##   程序画 (不下素材): 金光爆环 (_play_aoe_ring 金色) + 蛋壳碎片 CPUParticles (米白/棕碎片向外迸).
func _play_incubator_hatch(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	# 金光爆环 (复用通用环, 金色)
	_play_aoe_ring(idx, Color(1.0, 0.86, 0.3, 0.85))
	var node: Node2D = slot_nodes[idx]
	var avatar = node.get_meta("avatar") if node.has_meta("avatar") else null
	var pos: Vector2 = avatar.position if avatar != null else Vector2(0, -55)
	# 蛋壳碎片迸射 (米白碎片, 一次性向外, 带重力下坠)
	var shards := CPUParticles2D.new()
	shards.position = pos
	shards.emitting = true
	shards.one_shot = true
	shards.amount = 22
	shards.lifetime = 0.6
	shards.explosiveness = 1.0
	shards.spread = 180.0
	shards.gravity = Vector2(0, 320.0)
	shards.initial_velocity_min = 80.0
	shards.initial_velocity_max = 240.0
	shards.scale_amount_min = 1.4
	shards.scale_amount_max = 2.6
	shards.scale_amount_curve = _make_decay_curve()
	shards.color = Color(0.96, 0.92, 0.78)   # #f5ebc7 蛋壳米白
	shards.z_index = 200
	node.add_child(shards)
	get_tree().create_timer(0.85).timeout.connect(shards.queue_free)
	# 金色升腾微光 (向上飘的金粒, 暗示"升级")
	var glow := CPUParticles2D.new()
	glow.position = pos
	glow.emitting = true
	glow.one_shot = true
	glow.amount = 16
	glow.lifetime = 0.7
	glow.explosiveness = 0.6
	glow.spread = 40.0
	glow.direction = Vector2(0, -1)
	glow.gravity = Vector2(0, -60.0)
	glow.initial_velocity_min = 40.0
	glow.initial_velocity_max = 110.0
	glow.scale_amount_curve = _make_decay_curve()
	glow.color = Color(1.0, 0.86, 0.35)   # 金光
	var gmat := CanvasItemMaterial.new()
	gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gmat
	glow.z_index = 201
	node.add_child(glow)
	get_tree().create_timer(0.95).timeout.connect(glow.queue_free)


## 冰封冻结闪 (羁绊·极地小队 / 装备无专属冰 sprite → 复用 _flash_hit 同款 avatar tint, 改青蓝色 + 残留半透蓝罩)。
##   纯节点 (无新资源): avatar 蓝白 tint 闪 + 角色上叠一层青色半透方块脉冲。
func _play_freeze_flash(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var avatar: Sprite2D = node.get_meta("avatar", null)
	if avatar == null:
		return
	# avatar 青蓝高光闪 (复用 _flash_hit 同手法, 不 kill 它的 flash_tw → 独立 tween 收尾回白)
	var a: float = avatar.modulate.a
	avatar.modulate = Color(0.7, 1.2, 1.6, a)   # 偏青蓝提亮
	var tw := create_tween()
	tw.tween_property(avatar, "modulate", Color(1, 1, 1, a), 0.28).set_ease(Tween.EASE_OUT)
	# 冰罩脉冲圈 (青色半透圆, 扩散淡出 — 用既有 _circle_points 几何, 无资源)
	var pos: Vector2 = avatar.position
	var ring := Polygon2D.new()
	ring.polygon = _circle_points(30.0)
	ring.color = Color(0.5, 0.85, 1.0, 0.45)   # #80d9ff α.45
	ring.position = pos
	ring.z_index = 60
	node.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.5, 1.5), 0.3).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.3)
	rt.chain().tween_callback(ring.queue_free)


## 处决白闪 (羁绊·弓箭神射手 / 黑礁猎团8档 / 圣甲非此 → 斩杀目标处 ghost-touch 帧动画 + 强白闪 + 小震)。
##   ghost-touch.png 是既有"幽灵触碰"贴图 (白幽灵爪), 贴切"秒杀"感; 复用不新建资源。
func _play_execute_flash(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size():
		return
	_flash_hit(target_idx)
	_play_vfx_at_slot("ghost-touch", target_idx, 1.1)
	_play_screen_shake(0.16, 9.0)


## 眩晕持续期·头顶转圈星星 (用户 2026-06-26): 单位有 stun buff 期间, 头顶上方 3 颗 💫 绕圈转;
##   解晕/出手消耗 stun 即消失。纯 VFX 无文字。挂 hud(不随龟身 hop 飞), 复用 Label emoji + 旋转 tween, 无新资源。
##   由 _sync_stun_overhead 按 buff 状态增删 (在 _refresh_slot + 各 stun 消耗点调)。
func _spawn_stun_overhead(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var node: Node2D = slot_nodes[idx]
	var hud = node.get_meta("hud", null)
	if hud == null or not is_instance_valid(hud):
		return
	# 已有 → 不重建 (持续显示, 幂等)
	if node.has_meta("stun_overhead") and is_instance_valid(node.get_meta("stun_overhead")):
		return
	var av: Sprite2D = node.get_meta("avatar", null)
	# 头顶上方: 身体中心(av.y) 再上抬到立绘头顶之上 (av.y 是身体中心, sprite_half≈51 → 头顶 ≈ av.y-51, 再上 22)
	var head_y: float = (av.position.y - 56.0) if av != null else -118.0
	var orbit := Node2D.new()
	orbit.position = Vector2(0, head_y)
	orbit.z_index = 250   # 在血条/ⓘ 之上
	# 3 颗星均布绕圈 (每颗 Label, 绕 orbit 中心半径 14)
	var n_star := 3
	for s in range(n_star):
		var star := Label.new()
		star.text = "💫"
		star.add_theme_font_size_override("font_size", 16)
		star.add_theme_font_override("font", _float_num_font())
		var ang: float = TAU * float(s) / float(n_star)
		star.position = Vector2(cos(ang) * 14.0 - 8.0, sin(ang) * 6.0 - 8.0)   # 椭圆轨道(横宽竖扁), -8 居中 16px 字
		orbit.add_child(star)
	hud.add_child(orbit)
	node.set_meta("stun_overhead", orbit)
	# 连续旋转 (绕 orbit 原点) — 持续到被 _remove_stun_overhead 释放
	var spin := orbit.create_tween().set_loops()
	spin.tween_property(orbit, "rotation", TAU, 1.1).from(0.0)


## 移除头顶眩晕星星 (解晕/出手消耗 stun 时调)。
func _remove_stun_overhead(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var node: Node2D = slot_nodes[idx]
	if node.has_meta("stun_overhead"):
		var orbit = node.get_meta("stun_overhead")
		if is_instance_valid(orbit):
			orbit.queue_free()
		node.remove_meta("stun_overhead")


## 同步头顶眩晕星星与 stun buff 状态: 有 stun(且存活非黑洞) → 显示; 否则移除。幂等, 可频繁调。
##   黑洞已有专属"不可出手"徽章/视觉 → 不再叠星星 (避免双重)。
func _sync_stun_overhead(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]) or idx >= fighters.size():
		return
	var f: Dictionary = fighters[idx]
	var want: bool = f.get("alive", false) and Buffs.has(f, "stun") and not Buffs.has(f, "blackhole")
	if want:
		_spawn_stun_overhead(idx)
	else:
		_remove_stun_overhead(idx)


# ════════════════════════════════════════════════════════════════════
#  护盾光 + 治疗绿光 VFX (批3: 012/013/016/018/019/021/036/042/044)
#    程序画 (Polygon2D 盾环 + Line2D 盾罩圈 / CPUParticles2D 绿色上升光), 不下外部素材.
#    护盾→盾光(护罩/盾环, 盾蓝), 治疗→绿光(绿色上升治疗光). 逻辑数值不动, 纯视觉.
# ════════════════════════════════════════════════════════════════════

## 护盾光: 目标处一道护盾罩光 — 盾蓝实心环外扩淡出 (ADD发光) + 一圈盾罩边线脉冲, 形成护罩感.
##   color=盾色 (默认盾蓝 #5cb8ff; 021 连接给盾用青蓝, 036/013 用统一盾蓝). 复用 _circle_points 几何, 无资源.
func _play_shield_glow(target_idx: int, color: Color = Color(0.36, 0.72, 1.0, 0.5)) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# ① 盾罩边线圈 (Line2D 圆环) — 从角色身上长出, 微扩张后淡出 = 护罩边缘亮起
	var ring := Line2D.new()
	ring.points = _circle_points(30.0)
	ring.width = 4.0
	ring.closed = true
	ring.default_color = Color(color.r, color.g, color.b, 0.95)
	ring.material = add_mat
	ring.position = pos
	ring.z_index = 198
	node.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.35, 1.35), 0.42).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.42)
	rt.chain().tween_callback(ring.queue_free)
	# ② 盾罩填充光 (Polygon2D 半透盾色圆) — 短暂铺一层护罩底光后淡出
	var dome := Polygon2D.new()
	dome.polygon = _circle_points(28.0)
	dome.color = Color(color.r, color.g, color.b, 0.28)
	dome.material = add_mat
	dome.position = pos
	dome.z_index = 197
	node.add_child(dome)
	var dt := create_tween().set_parallel(true)
	dt.tween_property(dome, "scale", Vector2(1.2, 1.2), 0.30).set_ease(Tween.EASE_OUT)
	dt.tween_property(dome, "modulate:a", 0.0, 0.30)
	dt.chain().tween_callback(dome.queue_free)


## 治疗绿光: 目标处一片绿色上升治疗光 — 绿色粒子向上飘 (gravity 向上) + 一圈绿色脉冲环, 复合治疗感.
##   CPUParticles2D 上升绿光 (ADD) + Polygon2D 绿环外扩. 无外部素材, 数值不动.
func _play_heal_glow(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# ① 绿色上升治疗光粒子 (从脚底~身体范围内升起, 向上飘 + 渐隐)
	var rise := CPUParticles2D.new()
	rise.position = pos + Vector2(0, 18)   # 从身体下方升起
	rise.emitting = true
	rise.one_shot = true
	rise.amount = 16
	rise.lifetime = 0.7
	rise.explosiveness = 0.25
	rise.spread = 0.0
	rise.gravity = Vector2(0, -70)   # 向上飘
	rise.direction = Vector2(0, -1)
	rise.initial_velocity_min = 30.0
	rise.initial_velocity_max = 70.0
	rise.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rise.emission_rect_extents = Vector2(22, 8)
	rise.scale_amount_min = 2.0
	rise.scale_amount_max = 4.0
	rise.scale_amount_curve = _make_decay_curve()
	rise.color = Color(0.36, 0.92, 0.5)   # #5cea80 治疗绿
	rise.material = add_mat
	rise.z_index = 198
	node.add_child(rise)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(rise):
			rise.queue_free(), CONNECT_ONE_SHOT)
	# ② 绿色治疗脉冲环 (外扩淡出, 强调"被治疗"瞬间)
	var ring := Polygon2D.new()
	ring.polygon = _circle_points(26.0)
	ring.color = Color(0.36, 0.92, 0.5, 0.4)
	ring.material = add_mat
	ring.position = pos
	ring.z_index = 197
	node.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.6, 1.6), 0.38).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.38)
	rt.chain().tween_callback(ring.queue_free)


## 吸血专属反馈 (用户点名"吸血没特效") — 攻击者处吸血绿光 + 一圈血红收束环, 玩家一眼看出"触发了吸血"。
##   复用既有 primitive (无新资源, 数值不动): ① _play_heal_glow 绿色上升治疗光 (回血感) +
##   ② 一圈血红环【向内收束】(scale 1.4→0.4, "吸取/汲血"语义, 区别于治疗的外扩环)。配合 +N 绿字, 吸血看得见。
func _play_lifesteal_glow(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	_play_heal_glow(target_idx)   # 绿色上升治疗光 (回血感)
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var ring := Polygon2D.new()
	ring.polygon = _circle_points(40.0)
	ring.color = Color(0.85, 0.16, 0.22, 0.55)   # 血红
	ring.material = add_mat
	ring.position = (av.position if av != null else Vector2(0, -50))
	ring.scale = Vector2(1.4, 1.4)
	ring.z_index = 199
	node.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(0.4, 0.4), 0.34).set_ease(Tween.EASE_IN)   # 向内收束 = 汲血/吸取语义
	rt.tween_property(ring, "modulate:a", 0.0, 0.34)
	rt.chain().tween_callback(ring.queue_free)


## 连接光链 (021 守护贝母): 携带者→连接友军 一道青蓝能量链 (Line2D ADD), 强调"连接/供给"关系, 短暂淡出.
func _play_link_chain(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if from_idx == to_idx:
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	var from_pos: Vector2 = _slot_center_world(from_idx)
	var to_pos: Vector2 = _slot_center_world(to_idx)
	var link := Line2D.new()
	link.points = PackedVector2Array([from_pos, to_pos])
	link.width = 5.0
	link.default_color = Color(0.45, 0.85, 1.0, 0.9)   # #73d9ff 青蓝能量链
	var lmat := CanvasItemMaterial.new()
	lmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	link.material = lmat
	link.z_index = 600   # 能量链高过龟身(最深 ~497): 原 196 被龟立绘遮死
	slots_root.add_child(link)
	var lt := create_tween().set_parallel(true)
	lt.tween_property(link, "width", 9.0, 0.18).set_ease(Tween.EASE_OUT)
	lt.tween_property(link, "modulate:a", 0.0, 0.40)
	lt.chain().tween_callback(link.queue_free)


# ════════════════════════════════════════════════════════════════════
#  火 / 血 VFX (批4: 022/023/037 火 · 002/015 血; 冰/处决复用既有 freeze/execute)
#    程序画 (CPUParticles2D 喷溅 + Polygon2D 闪环), 不下外部素材.
#    火→橙红火焰喷吐, 血→红血滴溅射. 逻辑数值不动, 纯视觉.
# ════════════════════════════════════════════════════════════════════

## 火焰喷溅: 目标处一团橙红火焰 — 向上+外扩的火粒 (ADD发光, 上飘抖动) + 一圈橙色火闪环.
##   color=火色 (默认 #ff5a14 橙红; 023 火幕用更深红可传). 复用 _circle_points + _make_decay_curve, 无外部素材.
func _play_flame_burst(target_idx: int, color: Color = Color(1.0, 0.35, 0.08, 1.0)) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# ① 火焰喷吐粒子 (从身体底部升腾, 向上飘 + 横向小抖, 火色渐隐)
	var flame := CPUParticles2D.new()
	flame.position = pos + Vector2(0, 12)
	flame.emitting = true
	flame.one_shot = true
	flame.amount = 24
	flame.lifetime = 0.5
	flame.explosiveness = 0.7
	flame.spread = 35.0
	flame.direction = Vector2(0, -1)
	flame.gravity = Vector2(0, -120.0)   # 火向上窜
	flame.initial_velocity_min = 50.0
	flame.initial_velocity_max = 140.0
	flame.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flame.emission_rect_extents = Vector2(16, 6)
	flame.scale_amount_min = 2.4
	flame.scale_amount_max = 4.2
	flame.scale_amount_curve = _make_decay_curve()
	flame.color = color   # 橙红火色
	flame.material = add_mat
	flame.z_index = 199
	node.add_child(flame)
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(flame):
			flame.queue_free(), CONNECT_ONE_SHOT)
	# ② 火焰爆闪环 (橙色实心环外扩淡出, 强调"被点燃/灼烧"瞬间)
	var ring := Polygon2D.new()
	ring.polygon = _circle_points(24.0)
	ring.color = Color(color.r, color.g * 0.85, color.b, 0.45)
	ring.material = add_mat
	ring.position = pos
	ring.z_index = 198
	node.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.7, 1.7), 0.32).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.32)
	rt.chain().tween_callback(ring.queue_free)


## 血滴溅射: 目标处一蓬红血滴 — 暗红血粒向外喷溅带重力下坠 (溅出后落下) + 一道短促血红闪.
##   命中流血 (002海带卷刀 / 015荆棘海胆) 用. CPUParticles2D 重力下坠喷溅, 无外部素材.
func _play_blood_splatter(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	# ① 血滴喷溅粒子 (四散喷出 + 重力下坠, 暗红, 不发光 = 实体血滴)
	var blood := CPUParticles2D.new()
	blood.position = pos
	blood.emitting = true
	blood.one_shot = true
	blood.amount = 18
	blood.lifetime = 0.55
	blood.explosiveness = 1.0
	blood.spread = 180.0
	blood.gravity = Vector2(0, 360.0)   # 血滴下坠
	blood.initial_velocity_min = 60.0
	blood.initial_velocity_max = 190.0
	blood.scale_amount_min = 1.6
	blood.scale_amount_max = 3.0
	blood.scale_amount_curve = _make_decay_curve()
	blood.color = Color(0.72, 0.05, 0.08)   # #b80d14 暗红血色
	blood.z_index = 200
	node.add_child(blood)
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(blood):
			blood.queue_free(), CONNECT_ONE_SHOT)
	# ② 血红溅点闪 (短促红色半透圆, 命中即现快速淡出)
	var splat := Polygon2D.new()
	splat.polygon = _circle_points(18.0)
	splat.color = Color(0.66, 0.04, 0.07, 0.5)
	splat.position = pos
	splat.z_index = 199
	node.add_child(splat)
	var st := create_tween().set_parallel(true)
	st.tween_property(splat, "scale", Vector2(1.5, 1.5), 0.22).set_ease(Tween.EASE_OUT)
	st.tween_property(splat, "modulate:a", 0.0, 0.22)
	st.chain().tween_callback(splat.queue_free)


# ════════════════════════════════════════════════════════════════════
#  批6 杂项装备 VFX (035/038/040/008/003/014/017/046/055)
#    全程序画 (Line2D ADD 射线 / Polygon2D 环 / CPUParticles 粒子), 不下外部素材, 数值不动.
# ════════════════════════════════════════════════════════════════════

## 008 双穿珊瑚刺: 携带者→最远敌 一道【细长珊瑚刺】穿刺射线 (Line2D ADD, 锐利刺尖感) + 命中点白闪.
##   珊瑚刺色=暖橙红珊瑚 #ff7a52, 起点细→快速伸长到目标后淡出.
func _play_coral_pierce(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	var from_pos: Vector2 = _slot_center_world(from_idx)
	var to_pos: Vector2 = _slot_center_world(to_idx)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 珊瑚刺主体 (从携带者快速伸到目标: 起点固定, 末端 0→to 伸长)
	var spike := Line2D.new()
	spike.points = PackedVector2Array([from_pos, from_pos])
	spike.width = 3.0
	spike.default_color = Color(1.0, 0.48, 0.32, 0.95)   # #ff7a52 珊瑚橙红
	spike.material = add_mat
	spike.z_index = 600   # 珊瑚刺穿刺线高过龟身(最深 ~497): 原 197 被龟立绘遮死
	spike.begin_cap_mode = Line2D.LINE_CAP_ROUND
	spike.end_cap_mode = Line2D.LINE_CAP_ROUND
	slots_root.add_child(spike)
	var gt := create_tween()
	gt.tween_method(func(p: float) -> void:
		if is_instance_valid(spike):
			spike.points = PackedVector2Array([from_pos, from_pos.lerp(to_pos, p)]), 0.0, 1.0, 0.16).set_ease(Tween.EASE_OUT)
	gt.tween_callback(func() -> void:
		_flash_hit(to_idx))
	gt.tween_property(spike, "modulate:a", 0.0, 0.22)
	gt.chain().tween_callback(spike.queue_free)


## 014 深海堡垒: 敌→携带者 一道【紫色魔法吸取束】(Line2D ADD), 暗示生命/魔法被汲取流向自己.
func _play_drain_beam(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or to_idx < 0 or from_idx >= slot_nodes.size() or to_idx >= slot_nodes.size():
		return
	if not is_instance_valid(slot_nodes[from_idx]) or not is_instance_valid(slot_nodes[to_idx]):
		return
	var from_pos: Vector2 = _slot_center_world(from_idx)
	var to_pos: Vector2 = _slot_center_world(to_idx)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var beam := Line2D.new()
	beam.points = PackedVector2Array([from_pos, to_pos])
	beam.width = 5.0
	beam.default_color = Color(0.74, 0.42, 1.0, 0.85)   # #bd6bff 魔法紫
	beam.material = add_mat
	beam.z_index = 600   # 吸取束高过龟身(最深 ~497): 原 196 被龟立绘遮死
	slots_root.add_child(beam)
	# 汲取流光珠 (沿束 敌→己 飞行, 强调"吸取"方向)
	var orb := Polygon2D.new()
	orb.polygon = _circle_points(6.0)
	orb.color = Color(0.86, 0.62, 1.0, 0.95)
	orb.material = add_mat
	orb.position = from_pos
	orb.z_index = 601   # 流光珠叠在束之上, 均高过龟身 (原 197 被遮)
	slots_root.add_child(orb)
	var bt := create_tween()
	bt.tween_property(orb, "position", to_pos, 0.26).set_ease(Tween.EASE_IN)
	bt.parallel().tween_property(beam, "modulate:a", 0.0, 0.30)
	bt.chain().tween_callback(beam.queue_free)
	bt.chain().tween_callback(orb.queue_free)


## 017 不沉之锚: 携带者→最前敌 铁锚下砸冲击 (目标处下砸震击环+震屏) + 一道铁灰锚链 Line2D 连到携带者.
func _play_anchor_slam(from_idx: int, to_idx: int) -> void:
	if to_idx < 0 or to_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[to_idx]):
		return
	# 锚链 (携带者→目标 铁灰链)
	if from_idx >= 0 and from_idx < slot_nodes.size() and is_instance_valid(slot_nodes[from_idx]):
		var from_pos: Vector2 = _slot_center_world(from_idx)
		var to_pos: Vector2 = _slot_center_world(to_idx)
		var chain := Line2D.new()
		chain.points = PackedVector2Array([from_pos, to_pos])
		chain.width = 6.0
		chain.default_color = Color(0.62, 0.66, 0.72, 0.9)   # 铁灰锚链
		chain.z_index = 600   # 锚链高过龟身(最深 ~497): 原 195 被龟立绘遮死
		slots_root.add_child(chain)
		var ct := create_tween().set_parallel(true)
		ct.tween_property(chain, "width", 2.0, 0.34).set_ease(Tween.EASE_IN)
		ct.tween_property(chain, "modulate:a", 0.0, 0.34)
		ct.chain().tween_callback(chain.queue_free)
	# 下砸冲击环 (双层灰白扩散) + 震屏 (砸击感)
	_play_aoe_ring(to_idx, Color(0.78, 0.82, 0.88, 0.6))
	_play_aoe_ring(to_idx, Color(0.5, 0.55, 0.62, 0.4))
	_play_screen_shake(0.18, 11.0)
	# 铁锚下砸: 一枚铁灰锚形块从上空快速砸落到目标 (程序方块, 无素材)
	var node: Node2D = slot_nodes[to_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	var anchor := Polygon2D.new()
	anchor.polygon = PackedVector2Array([Vector2(-9, -12), Vector2(9, -12), Vector2(9, 12), Vector2(-9, 12)])
	anchor.color = Color(0.55, 0.6, 0.68, 0.95)
	anchor.position = pos + Vector2(0, -90)
	anchor.z_index = 201
	node.add_child(anchor)
	var at := create_tween()
	at.tween_property(anchor, "position", pos, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	at.tween_property(anchor, "modulate:a", 0.0, 0.18)
	at.chain().tween_callback(anchor.queue_free)


## 055 靶向器: 目标处一圈【红色准星】= 红圆环 + 十字准线, 短暂收缩定位后淡出 (瞄准锁定感).
func _play_target_reticle(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var red := Color(1.0, 0.27, 0.27, 0.95)   # #ff4545 瞄准红
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = 202
	node.add_child(holder)
	# 准星圆环 (Line2D 圆)
	var ring := Line2D.new()
	ring.points = _circle_points(26.0)
	ring.width = 2.5
	ring.closed = true
	ring.default_color = red
	ring.material = add_mat
	holder.add_child(ring)
	# 十字准线 (4 段短线伸向圆心方向)
	for ang in [0.0, 90.0, 180.0, 270.0]:
		var d := Vector2.from_angle(deg_to_rad(ang))
		var tick := Line2D.new()
		tick.points = PackedVector2Array([d * 16.0, d * 30.0])
		tick.width = 2.5
		tick.default_color = red
		tick.material = add_mat
		holder.add_child(tick)
	# 从外向内收缩定位 (锁定感) 后淡出
	holder.scale = Vector2(1.5, 1.5)
	var rt := create_tween()
	rt.tween_property(holder, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rt.tween_interval(0.12)
	rt.tween_property(holder, "modulate:a", 0.0, 0.22)
	rt.chain().tween_callback(holder.queue_free)


## 003 锋利鲨齿: 主命中目标处【撕咬白闪】= 强白脉冲 + 一对锐齿白弧 (撕咬), 强调暴击破甲咬击.
func _play_bite_flash(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	_flash_hit(target_idx)
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 一对相向锐齿弧 (上下两道白色尖弧合咬)
	for sgn in [-1.0, 1.0]:
		var fang := Line2D.new()
		var pts := PackedVector2Array()
		for k in range(7):
			var fx2: float = -22.0 + 44.0 * float(k) / 6.0
			pts.append(Vector2(fx2, sgn * (16.0 - abs(fx2) * 0.45)))   # 中间深、两端浅 = 咬合弧
		fang.points = pts
		fang.width = 3.0
		fang.default_color = Color(1.0, 1.0, 1.0, 0.95)
		fang.material = add_mat
		fang.position = pos
		fang.z_index = 201
		node.add_child(fang)
		var ft := create_tween().set_parallel(true)
		ft.tween_property(fang, "position:y", pos.y + sgn * -6.0, 0.18).set_ease(Tween.EASE_OUT)   # 合咬靠拢
		ft.tween_property(fang, "modulate:a", 0.0, 0.22)
		ft.chain().tween_callback(fang.queue_free)


## 040 FPGA 板: 抽中时【电路/比特闪】= 短电闪 (天降闪电 sprite) + 青绿方块比特粒子向上飘.
func _play_bit_flash(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 青绿方块比特粒子 (向上飘散, 用 debris 方点纹理染青绿 = 数据/比特感)
	var bits := CPUParticles2D.new()
	bits.position = pos
	bits.emitting = true
	bits.one_shot = true
	bits.amount = 16
	bits.lifetime = 0.55
	bits.explosiveness = 0.85
	bits.spread = 50.0
	bits.direction = Vector2(0, -1)
	bits.gravity = Vector2(0, -90.0)
	bits.initial_velocity_min = 50.0
	bits.initial_velocity_max = 130.0
	bits.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	bits.emission_rect_extents = Vector2(20, 14)
	bits.scale_amount_min = 1.4
	bits.scale_amount_max = 2.4
	bits.scale_amount_curve = _make_decay_curve()
	bits.color = Color(0.49, 0.96, 0.75)   # #7df5c0 青绿比特
	bits.texture = _debris_tex()
	bits.material = add_mat
	bits.z_index = 200
	node.add_child(bits)
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(bits):
			bits.queue_free(), CONNECT_ONE_SHOT)
	# 短电闪 (青绿脉冲环, 快闪 — 电路通电感)
	var spark := Polygon2D.new()
	spark.polygon = _circle_points(22.0)
	spark.color = Color(0.49, 0.96, 0.75, 0.55)
	spark.material = add_mat
	spark.position = pos
	spark.z_index = 199
	node.add_child(spark)
	var st := create_tween().set_parallel(true)
	st.tween_property(spark, "scale", Vector2(1.5, 1.5), 0.2).set_ease(Tween.EASE_OUT)
	st.tween_property(spark, "modulate:a", 0.0, 0.2)
	st.chain().tween_callback(spark.queue_free)


## 046 幽灵墨鱼: 闪避时【墨汁烟雾】= 墨色烟雾粒子四散 + 暗紫墨团淡出 (烟雾遁避感; 盾光另由调用方播).
func _play_ink_dodge(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	# 墨色烟雾粒子 (四散 + 缓慢上浮, 不发光 = 实体墨烟; 暗紫黑)
	var ink := CPUParticles2D.new()
	ink.position = pos
	ink.emitting = true
	ink.one_shot = true
	ink.amount = 20
	ink.lifetime = 0.6
	ink.explosiveness = 0.9
	ink.spread = 180.0
	ink.gravity = Vector2(0, -40.0)
	ink.initial_velocity_min = 30.0
	ink.initial_velocity_max = 110.0
	ink.scale_amount_min = 2.4
	ink.scale_amount_max = 4.8
	ink.scale_amount_curve = _make_decay_curve()
	ink.color = Color(0.16, 0.1, 0.22)   # 暗紫墨色
	ink.texture = _debris_tex()
	ink.z_index = 200
	node.add_child(ink)
	get_tree().create_timer(0.85).timeout.connect(func() -> void:
		if is_instance_valid(ink):
			ink.queue_free(), CONNECT_ONE_SHOT)
	# 暗紫墨团 (快速铺一层后淡出 = 墨幕)
	var blob := Polygon2D.new()
	blob.polygon = _circle_points(26.0)
	blob.color = Color(0.2, 0.12, 0.28, 0.5)
	blob.position = pos
	blob.z_index = 199
	node.add_child(blob)
	var bt := create_tween().set_parallel(true)
	bt.tween_property(blob, "scale", Vector2(1.7, 1.7), 0.3).set_ease(Tween.EASE_OUT)
	bt.tween_property(blob, "modulate:a", 0.0, 0.3)
	bt.chain().tween_callback(blob.queue_free)


## 035 黄铜齿轮: 携带者死亡散落齿轮 → 金色齿轮/金币迸溅 (CPUParticles 金粒子向外迸 + 重力下坠 + 金光环).
##   死亡口在 coins 结算后调; node=死者 slot, pos=死者身体中心.
func _play_gear_burst(node: Node2D, pos: Vector2) -> void:
	if not is_instance_valid(node):
		return
	# 金色齿轮/金币粒子 (四散迸射 + 重力下坠 = 实体金属碎块掉落)
	var gears := CPUParticles2D.new()
	gears.position = pos
	gears.emitting = true
	gears.one_shot = true
	gears.amount = 20
	gears.lifetime = 0.7
	gears.explosiveness = 1.0
	gears.spread = 180.0
	gears.gravity = Vector2(0, 340.0)
	gears.initial_velocity_min = 80.0
	gears.initial_velocity_max = 230.0
	gears.scale_amount_min = 1.6
	gears.scale_amount_max = 3.0
	gears.scale_amount_curve = _make_decay_curve()
	gears.color = Color(1.0, 0.82, 0.28)   # #ffd147 金色
	gears.texture = _debris_tex()
	gears.z_index = 201
	node.add_child(gears)
	get_tree().create_timer(0.95).timeout.connect(func() -> void:
		if is_instance_valid(gears):
			gears.queue_free(), CONNECT_ONE_SHOT)
	# 金光爆环 (散落瞬间的金光)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var ring := Polygon2D.new()
	ring.polygon = _circle_points(24.0)
	ring.color = Color(1.0, 0.86, 0.35, 0.5)
	ring.material = add_mat
	ring.position = pos
	ring.z_index = 200
	node.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.7, 1.7), 0.32).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.32)
	rt.chain().tween_callback(ring.queue_free)


## 召唤/入场光环 (033复活海螺化形 / 034玩偶大熊登场 / 033分裂虫): 入场时一圈彩色召唤光环外扩 + 上升微粒,
##   补现状只有缩放pop无入场光效 (需F5 眼验). color=召唤体主题色. 复用通用环 + ADD 上升粒子, 无外部素材.
func _play_summon_burst(target_idx: int, color: Color) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = (av.position if av != null else Vector2(0, -50))
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 召唤光环 (主题色实心环外扩淡出)
	var ring := Polygon2D.new()
	ring.polygon = _circle_points(30.0)
	ring.color = Color(color.r, color.g, color.b, 0.5)
	ring.material = add_mat
	ring.position = pos
	ring.z_index = 198
	node.add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.9, 1.9), 0.4).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.4)
	rt.chain().tween_callback(ring.queue_free)
	# 召唤上升微粒 (从脚底升起的主题色光点, 强调"现身")
	var rise := CPUParticles2D.new()
	rise.position = pos + Vector2(0, 16)
	rise.emitting = true
	rise.one_shot = true
	rise.amount = 14
	rise.lifetime = 0.6
	rise.explosiveness = 0.4
	rise.spread = 25.0
	rise.direction = Vector2(0, -1)
	rise.gravity = Vector2(0, -80.0)
	rise.initial_velocity_min = 40.0
	rise.initial_velocity_max = 100.0
	rise.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rise.emission_rect_extents = Vector2(20, 8)
	rise.scale_amount_min = 1.6
	rise.scale_amount_max = 3.0
	rise.scale_amount_curve = _make_decay_curve()
	rise.color = color
	rise.texture = _debris_tex()
	rise.material = add_mat
	rise.z_index = 199
	node.add_child(rise)
	get_tree().create_timer(0.85).timeout.connect(func() -> void:
		if is_instance_valid(rise):
			rise.queue_free(), CONNECT_ONE_SHOT)


## 孵化器: 任意单位死亡 → 所有持孵化器存活者 +进度 (敌死+10/我死+15, 1:1 PoC processDeathPassives + _incubatorProgress)
func _incubator_on_death(dead: Dictionary) -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("alive", false) or not f.has("_incubatorProgress"):
			continue
		var delta: int = 15 if (f.get("side", "") == dead.get("side", "")) else 10
		if EquipmentRuntime._incubator_add(f, delta) > 0:
			_spawn_passive_text(i, "🥚 临时Lv+%d" % int(f.get("_incubatorTempLevel", 0)))
			_play_incubator_hatch(i)   # 满100升级瞬间: 金光爆环 + 蛋壳碎片升级特效
			_refresh_slot(i)
		else:
			_refresh_slot(i)           # 未升级也刷进度条 (进度涨了)


## 奇械[深海工坊] 死亡产装备 (规格#544): 我方(左)统领/小将阵亡 → 累计死亡数+1,
##   该侧【每件激活奇械】各产一件 cost=min(累计数,5) 费装备, 永久进背包(GameState.bench_inventory);
##   每个累计死亡档位一局仅触发一次。仅 duallane(有持久背包)生效; 召唤物/中立/蛋不计。
func _gadget_on_left_unit_death(dead: Dictionary) -> void:
	if GameState.mode != "duallane":
		return   # 只有双路有持久背包(GameState.bench_inventory); 其它模式无"永久进背包"语义
	if not (dead is Dictionary) or dead.get("side", "") != "left":
		return   # 规格#544 明文"我方"= 玩家方(左); 故意只对左产 —— 产出"永久进背包"(GameState.bench_inventory),
		#   而敌方(右)在 duallane PvE 每局程序重建、无持久背包=产出无落点。两侧都产是无效改动, 不对齐"两侧" (审计#7 已确认非bug)。
	if dead.get("_isEgg", false) or dead.get("_isSummon", false) or dead.get("_isNeutral", false):
		return   # 统领/小将 = 非蛋/非召唤/非中立 的我方单位 (含 _isMinion 小将)
	# 该侧有激活奇械才产 (件数=场上左侧激活奇械总和)。无奇械 → 累计也无意义, 不计。
	var pieces: int = Phase2EquipRuntime.gadget_piece_count(fighters, "left")
	if pieces <= 0:
		return
	_gadget_deaths_left += 1
	var cost: int = mini(_gadget_deaths_left, 5)   # 装备费用 = 当前累计失去数, 封顶5费
	if _gadget_tiers_fired.has(cost):
		return   # 该档位(累计死亡数)一局仅触发一次
	_gadget_tiers_fired[cost] = true
	_gadget_rng.randomize()
	var produced: Array = Phase2EquipRuntime.gadget_produce(fighters, "left", cost, DataRegistry.phase2_equipment, _gadget_rng)
	var added: int = 0
	for eid in produced:
		if GameState.bench_inventory.size() >= Phase2Config.BENCH_CAP:
			break   # 背包满 → 不再塞 (1:1 buy_shop_item 的 BENCH_CAP 约束)
		GameState.bench_inventory.append({"id": str(eid), "star": 1})
		added += 1
	if added > 0:
		GameState.try_merge_bench()   # 产出后顺手三合一(同 buy 流程一致), 防散件占满席
		battle_log.append_text("[color=#5fd0e6]🔧 奇械工坊: %s 阵亡 → 锻造 %d 件 %d费装备入背包[/color]
" % [dead.get("name", "?"), added, cost])


## 施法后装备效果 (电棍电击/竹叶强袭 等 post-cast) — 调 EquipmentRuntime.on_post_cast + 渲染飘字/VFX/死亡
func _apply_equip_post_cast(actor_idx: int, target_idx: int, is_single: bool) -> void:
	if actor_idx < 0 or actor_idx >= fighters.size():
		return
	var actor: Dictionary = fighters[actor_idx]
	var equips: Array = actor.get("_equipped_ids", [])
	if equips.is_empty():
		return
	var target = fighters[target_idx] if (target_idx >= 0 and target_idx < fighters.size()) else null
	for eq in equips:
		var fx: Array = EquipmentRuntime.on_post_cast(actor, str(eq), target, fighters, is_single)
		if fx.is_empty():
			continue
		for ef in fx:
			var ti: int = int(ef.get("target_idx", -1))
			if ti < 0 or ti >= fighters.size():
				continue
			var kind: String = str(ef.get("kind", ""))
			var lbl: String = str(ef.get("label", ""))
			if kind == "damage":
				_spawn_float_text(ti, int(ef.get("value", 0)), "damage", str(ef.get("dmg_type", "magic")), false)
				_flash_hit(ti)
				if lbl.contains("电棍"):
					_play_lightning_strike(ti)   # 电棍: 天降闪电 VFX (需F5)
			elif kind == "heal":
				var hdelay: float = float(ef.get("delay", 0.0))   # 逐段吸血: PoC doLifesteal(segDmg, delay) 逐hit绿字
				var hval: int = int(ef.get("value", 0))
				if hdelay > 0.0:
					get_tree().create_timer(hdelay).timeout.connect(func() -> void:
						_spawn_float_text(ti, hval, "heal"), CONNECT_ONE_SHOT)
				else:
					_spawn_float_text(ti, hval, "heal")
			else:
				_spawn_passive_text(ti, lbl)
			_refresh_slot(ti)
			if kind == "damage" and not fighters[ti].get("alive", false):
				await _play_death(ti)
				battle_log.append_text("  [color=#ff6b6b]☠ %s 阵亡[/color]\n" % fighters[ti].get("name", "?"))
				if fighters[ti].get("side", "") != actor.get("side", ""):
					_award_and_record_kill(actor, fighters[ti])
		await get_tree().create_timer(0.2).timeout   # 段间小停 (PoC sleep)


# 按各 fighter 当前 _slotKey 重新摆放 slot 视图 (换位/击退到前排 等改了 _slotKey 后调)
func _relayout_slots() -> void:
	for i in range(fighters.size()):
		if i >= slot_nodes.size():
			break
		var f: Dictionary = fighters[i]
		var node: Node2D = slot_nodes[i]
		var pos := _slot_to_coords(f.get("_slotKey", "front-0"), f.get("side", "left"))
		node.set_meta("home_pos", pos)
		node.z_index = int(pos.y)
		var tw := create_tween()
		tw.tween_property(node, "position", pos, 0.4).set_ease(Tween.EASE_OUT)
		# HUD sibling 同步换位 (否则换位后血条留在旧槽)
		var hud_l = node.get_meta("hud", null)
		if hud_l != null:
			hud_l.z_index = int(pos.y)
			tw.parallel().tween_property(hud_l, "position", pos, 0.4).set_ease(Tween.EASE_OUT)


## 删了 — 文案统一在 _spawn_float_text 里按 kind 拼, 不再独立 helper.


# 伤害类型 → 统计桶键 (PoC 'phy'|'mag'|'tru')
func _stat_type(dmg_type: String) -> String:
	if dmg_type == "magic":
		return "mag"
	if dmg_type == "true":
		return "tru"
	return "phy"


# 胜负判定的"战斗员": 排除 _untargetable(训龟大师) + _isNeutral(中立巨蟹/宝箱怪) — PoC nextActor:2094-2096
# 否则真龟全灭后中立仍存活 → 判该侧未败 → 卡死到 MAX_TURNS
func _is_combatant(f: Dictionary) -> bool:
	return f.get("alive", false) and not f.get("_untargetable", false) and not f.get("_isNeutral", false)


func _check_end() -> bool:
	var left_alive: int = 0
	var right_alive: int = 0
	for f in fighters:
		if not _is_combatant(f):
			continue
		if f["side"] == "left":
			left_alive += 1
		else:
			right_alive += 1
	# 二阶段双路: 某方真单位全灭【但龟蛋还活着】→ 龟蛋作为真 fighter 登场前排中间 →
	#   该方仍有 1 存活(蛋) → 战斗不结束, 胜方正常技能/普攻打蛋 (走完整伤害管线). 蛋 hp→0 才真败.
	#   (取代旧 _egg_attack_phase 假阶段: 蛋当特殊掉血逻辑 → 用户报"什么技能没放就掉血".)
	if GameState.mode == "duallane":
		var newly := false
		if left_alive == 0 and GameState.egg_alive("left") and not _egg_spawned("left"):
			if _spawn_egg_fighter("left") >= 0:
				left_alive += 1; newly = true
		if right_alive == 0 and GameState.egg_alive("right") and not _egg_spawned("right"):
			if _spawn_egg_fighter("right") >= 0:
				right_alive += 1; newly = true
		if newly:
			return false   # 蛋刚登场 → 战斗继续
	return left_alive == 0 or right_alive == 0


# ─── 动画 / 视觉 ───────────────────────────────────────────────

# 技能 type → vfx 资源名 (PoC 各技能触发的特效, 先接通默认loadout+常见技能)
#   注: basicSlam / basicChiWave / turtleShieldBash 已由 _skill_post_impact 编排自带 VFX, 移出此表防重复。
const SKILL_VFX := {
	# 注: basicBarrage/hunterBarrage 已改走 _play_barrage_bolts (逐目标 staggered bolt), 不在此表。
	# 注: cyberBeam 已改走 _play_cyber_beam_sweep (从 caster 贯穿到屏边的全屏光束, 见 _cyber_beam_windup 末尾),
	#     不在此表 — 否则会在目标点重复播一个小的 cyber-beam-sweep。
	# bambooSmack 不在此表: 原误把它映射到 bamboo-charge-orb(充能生命球) → 每次普通竹竿技能都放出本该只属
	#   被动的绿球(用户报"绿球每个技能都有, 只有被动有")。生命球只应由 _fire_bamboo_charge(持充能消费时) 经
	#   _spawn_bamboo_orb 放。bambooSmack 走默认命中反馈(无专属VFX; 如 PoC 有竹竿专属再补)。
	# 幽灵系列命中处 VFX (1:1 PoC ghost.js spawnGhostVfx, 在目标身上叠帧动画):
	#   ghostTouch 触碰(7帧128) / ghostStorm 风暴(8帧96). ghostPhantom 走自有 post-impact (幻影+juggle).
	"ghostTouch": "ghost-touch", "ghostStorm": "ghost-storm",
	# ninjaBomb 爆炸 sheet 在敌阵中心 (走 _ninja_bomb 编排, 不在此表; 见 windup case)。
	# p2Sweep (010激光长刃 横扫) 不在此表: 走 _take_turn 专属分发 _play_slash_sweep (从携带者朝整列敌劈月牙
	#   刃光 + 一道激光刃扫过) — 须是【剑横扫弧】(激光能量色), 不能套帧动画/cyber-beam (那是赛博激光束, 视觉不对)。
}


# VFX 帧率表 (1:1 PoC BootScene.ts:466-559 各 anims.create frameRate). 没列的 fallback 12.
#   旧 bug: _play_vfx 默认 12fps, 但幽灵系/光束等 PoC 是 10/8.33fps → 特效偏快 ~20%。
const VFX_FPS := {
	"cyber-beam-sweep": 8.333,                                # :496 6帧/720ms
	"ghost-touch": 10.0, "ghost-storm": 10.0, "ghost-phantom": 10.0,  # :542/535/528
	"common-lightning-strike": 9.0, "burn-loop": 10.0,        # :512/520
	"ninja-bomb": 10.0, "ninja-dash-trail": 20.0, "cyber-mech-birth": 11.0,  # :504/550/558
	"basic-shieldbash-arc": 17.0, "basic-shieldbash-impact": 20.0, "basic-slam-impact": 12.5,  # :472/480/488
	"bamboo-charge-orb": 14.0, "bamboo-charge-burst": 21.0,   # :459/463
}


## 通用 spritesheet VFX 播放: 在 world_pos 播一遍 vfx_name 帧动画后自动销毁. Aseprite 横向条, 方形帧.
##   fps<=0: 查 VFX_FPS 表 (PoC frameRate), 表里没有 fallback 12。fps>0: 调用方显式覆盖。
func _play_vfx(vfx_name: String, world_pos: Vector2, scale: float = 1.0, fps: float = -1.0, flip_x: bool = false) -> void:
	var path := "res://assets/sprites/vfx/%s.png" % vfx_name
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	var fw: int = tex.get_height()   # 方形帧 → 帧宽=高
	if fw <= 0:
		return
	var n: int = maxi(1, int(tex.get_width() / fw))
	var use_fps: float = fps if fps > 0.0 else float(VFX_FPS.get(vfx_name, 12.0))
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.hframes = n
	spr.frame = 0
	spr.position = world_pos
	spr.scale = Vector2(scale, scale)
	spr.flip_h = flip_x
	spr.z_index = 600   # 通用技能 VFX(SKILL_VFX 映射)高过龟身(最深 ~497): 原 200 被龟立绘遮死
	slots_root.add_child(spr)
	var tw := create_tween()
	tw.tween_method(func(fv: float): spr.frame = mini(n - 1, int(fv)), 0.0, float(n), n / use_fps)
	tw.tween_callback(spr.queue_free)


## ── 弹幕 staggered bolts (1:1 PoC basicBarrage/hunterBarrage) ──
##   逐 damage effect (每一击) 错开 280ms 发一颗 bolt 飞向其目标 (basic.js:135 forEach stagger 280)。
##   basicBarrage: 7帧 bolt sheet (basic-barrage-bolt), 从目标前 travelPx(250) 飞 220ms linear, 160×160。
##   hunterBarrage: 复用 hunter-arrow 投射物 (从 caster 飞向目标, 200ms)。
##   注: 演出 fire-and-forget 不阻塞主流程 (伤害飘字已在主流程命中帧展示, 与 PoC 节奏一致)。
func _play_barrage_bolts(actor_idx: int, effects: Array, skill_type: String, shots: Array = []) -> void:
	var stagger := 0.12 if skill_type == "hunterBarrage" else 0.28   # PoC: 连珠箭120ms / 打击280ms (skill-handlers.ts:4991/815)
	# basicBarrage 打击: 1:1 PoC 发 hits(10) 颗 bolt, 每颗按 handler 的 barrage_shots 目标(与飘字同序同敌→弹与数字对得上).
	#   (原按聚合 effect 数只飞1-3颗 = 用户报"不是这样"; 现每发一颗, 280ms 错开, 凭空在目标前生成飞入.)
	if skill_type == "basicBarrage" and not shots.is_empty():
		for i in range(shots.size()):
			var ti: int = int(shots[i])
			get_tree().create_timer(i * stagger).timeout.connect(
				func() -> void:
					_fire_barrage_bolt(actor_idx, ti),
				CONNECT_ONE_SHOT)
		return
	# hunterBarrage 等: 按 result_effects 逐目标 (顺序=逐段)
	var tgt_idxs: Array = []
	for eff in effects:
		if eff.get("kind", "") == "damage":
			tgt_idxs.append(int(eff.get("target_idx", -1)))
	if tgt_idxs.is_empty():
		return
	for i in range(tgt_idxs.size()):
		var ti: int = tgt_idxs[i]
		var delay: float = i * stagger
		if skill_type == "hunterBarrage":
			# 引导箭: 复用 _fire_arrow (从 caster 胸口飞向目标, 200ms)
			get_tree().create_timer(delay).timeout.connect(
				func() -> void:
					if ti >= 0 and ti < slot_nodes.size() and is_instance_valid(slot_nodes[ti]):
						_fire_arrow(actor_idx, ti, 0.2),
				CONNECT_ONE_SHOT)
		else:
			# basicBarrage bolt: 从目标前 travelPx 飞到身前 (PoC 不从 caster 出, 是凭空在目标前生成)
			get_tree().create_timer(delay).timeout.connect(
				func() -> void:
					_fire_barrage_bolt(actor_idx, ti),
				CONNECT_ONE_SHOT)


## 单颗 basic-barrage-bolt: 在 (目标前 travelPx, 目标 y-6) 生成, 飞 (travelPx-40) 落身前, 220ms linear, 边飞边播7帧。
func _fire_barrage_bolt(actor_idx: int, target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var path := "res://assets/sprites/vfx/basic-barrage-bolt.png"
	if not ResourceLoader.exists(path):
		return
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var t_home: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
	# PoC spawnY = sprite.y - 6 (sprite 中心 ≈ home.y - SPRITE_HALF). 立绘中心约抬 51 (box/2) → 取 -40 近似胸口。
	var spawn := Vector2(t_home.x - dir * 250.0, t_home.y - 46.0)   # travelPx 250
	var dest := Vector2(spawn.x + dir * (250.0 - 40.0), spawn.y)    # 飞 travelPx-40 = 210
	var tex: Texture2D = load(path)
	var fw: int = tex.get_height()   # 128 (方形帧)
	if fw <= 0:
		return
	var n: int = maxi(1, int(tex.get_width() / fw))   # 7 帧
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.hframes = n
	spr.frame = 0
	spr.position = spawn
	# PoC setDisplaySize(160,160): scale = 160/128
	var ds: float = 160.0 / float(fw)
	spr.scale = Vector2(ds * dir, ds)   # 右队 dir<0 → 水平镜像 (PoC setFlipX)
	spr.z_index = 600   # 弹幕 bolt 高过龟身(最深 ~497): 原 130 被龟立绘遮死
	slots_root.add_child(spr)
	var tw := spr.create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position:x", dest.x, 0.22)   # shotDuration 220ms linear
	tw.tween_method(func(fv: float): spr.frame = mini(n - 1, int(fv)), 0.0, float(n), 0.22)
	tw.chain().tween_callback(spr.queue_free)


## 彩虹蛇 (1:1 PoC makeRainbowSnake/hop/finish): 光头沿弹射路径(自身→敌→友→…)飞行, 身后留彩虹折线, 收尾淡出.
##   弹射顺序 = result_effects 顺序 (_rainbow_reflect 按序 emit). 纯视觉叠层(伤害/治疗已由结果循环飘字).
func _play_rainbow_snake(actor_idx: int, effs: Array) -> void:
	var pts: Array[Vector2] = []
	if actor_idx >= 0 and actor_idx < slot_nodes.size() and is_instance_valid(slot_nodes[actor_idx]):
		pts.append((slot_nodes[actor_idx].get_meta("home_pos", slot_nodes[actor_idx].position) as Vector2) + Vector2(0, -40))
	for eff in effs:
		var ti: int = int(eff.get("target_idx", -1))
		if ti >= 0 and ti < slot_nodes.size() and is_instance_valid(slot_nodes[ti]):
			pts.append((slot_nodes[ti].get_meta("home_pos", slot_nodes[ti].position) as Vector2) + Vector2(0, -40))
	if pts.size() < 2:
		return
	var line := Line2D.new()
	line.width = 5.0
	line.z_index = 600   # 彩虹蛇折线高过龟身(最深 ~497): 原 135 被龟立绘遮死
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color("#ff3b6b"), Color("#ff9e2c"), Color("#ffe14d"), Color("#49e06b"), Color("#3b82f6"), Color("#b06bff")])
	line.gradient = grad
	var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = mat
	slots_root.add_child(line)
	line.add_point(pts[0])
	# 逐跳延长: 每段末点从上一落点 tween 到当前目标 (光头飞行感)
	var tw := line.create_tween()
	for i in range(1, pts.size()):
		line.add_point(pts[i - 1])
		var pi: int = line.get_point_count() - 1
		tw.tween_method(func(p: Vector2) -> void: line.set_point_position(pi, p), pts[i - 1], pts[i], 0.22)
	tw.tween_interval(0.15)
	tw.tween_property(line, "modulate:a", 0.0, 0.3)
	tw.tween_callback(line.queue_free)


## 按技能 type 在目标位置播 VFX (无映射就不播)
func _play_skill_vfx(skill_type: String, target_idx: int) -> void:
	if not SKILL_VFX.has(skill_type) or target_idx < 0 or target_idx >= slot_nodes.size():
		return
	var pos: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
	_play_vfx(SKILL_VFX[skill_type], pos)


## 天降闪电 VFX — 1:1 PoC spawnLightningStrike (skill-handlers.ts:147-163 / combat.js:50-57)
##   5 帧 × 200×200 atlas, ~560ms, 底部锚定 target 脚下 (center = feet_y - 100), depth 35。
##   用途: 闪电龟 lightningStorm passive 每回合电击 / 8 层电击满层引爆 / 涌动(lightningSurgeBuff)即时电击。
func _play_lightning_strike(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size():
		return
	var feet: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
	# PoC sprite 200×200 底部贴脚 → center 上移 100px。9fps (5 帧 ≈ 560ms, BootScene.ts:507)。
	_play_vfx("common-lightning-strike", feet + Vector2(0.0, -100.0), 1.0, 9.0)


func _play_hop(idx: int, side: String) -> void:
	var node: Node2D = slot_nodes[idx]
	var home_pos: Vector2 = node.get_meta("home_pos", node.position)
	var hop_dx: int = HOP_DISTANCE if side == "left" else -HOP_DISTANCE
	var tween := create_tween()
	tween.tween_property(node, "position:x", home_pos.x + hop_dx, HOP_DURATION).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:x", home_pos.x, HOP_DURATION).set_ease(Tween.EASE_IN)


# ════════════════════════════════════════════════════════════════════
#  技能演出编排 (1:1 PoC) — 原语 + per-skill windup / post-impact
#    权威源: poc/src/scenes/BattleScene.ts + poc/src/engine/skill-handlers.ts
#    本块只做"视觉演出"; 伤害逻辑仍由 SkillHandlers.execute (纯逻辑) 算。
# ════════════════════════════════════════════════════════════════════

# 自驱位移技能 — caster 位移由各自 windup 编排, 不走通用前冲 hop
#   (1:1 PoC SKIP_POSITIONAL_HOP set, BattleScene.ts:3461)
const _SELF_DRIVE_SKILLS := ["basicSlam", "basicChiWave", "ninjaImpact", "ninjaBackstab", "ninjaBomb", "ghostPhase", "ghostPhantom"]

# 远程/魔法/AOE 技能 — caster 不冲到目标, 只在原地小幅 attack-hop 25px (1:1 PoC attack-hop, 非 80px melee dash)。
#   VFX/伤害在目标处展示; 多段/全体由 handler 内时序驱动。
#   (本批: 冰系全段魔法 / 神罚远程 / 竹刺阵全体 / 岩石冲击波横排; ghostStorm 风暴远程)
const _RANGED_SKILLS := [
	"iceFrost", "iceSpike", "iceFreeze", "ghostStorm", "angelSmite",
	"bambooSpikes", "rockShockwave", "ninjaShuriken",
	# ── 第 3 批 6 龟: 凤凰/熔岩/水晶/星际/彩虹 全为远程魔法/自施/AOE (1:1 PoC: 非 SKIP_POSITIONAL_HOP → 25px attack-hop) ──
	# 凤凰 (phoenix): 灼烧/烫伤 单体魔法 + 熔岩盾/净化 自施 (skill-handlers.ts:2048-2125 纯 floatNum, 无 caster 位移)
	"phoenixBurn", "phoenixScald", "phoenixShield", "phoenixPurify",
	# 熔岩 (lava): 岩浆弹/震击/涌动/飞溅 全单体/AOE 魔法 (skill-handlers.ts:2784-2900 纯 floatNum)。变身=passive, 不在此层
	"lavaBolt", "lavaQuake", "lavaSurge", "lavaSplash",
	# 水晶 (crystal): 结晶尖刺/碎晶爆破 魔法AOE + 壁垒自施盾 (skill-handlers.ts:3062-3144 纯 floatNum)
	"crystalSpike", "crystalBurst", "crystalBarrier", "crystalImmortal",
	# 星际 (star): 星光束/流星/虫洞/黑洞/引力 全魔法AOE (skill-handlers.ts:4218-4567; wormhole/gravityWarp 末尾 knockup, 黑洞带旋涡VFX — 见 post-impact)
	"starBeam", "starMeteor", "starWormhole", "starBlackhole", "starGravityWarp",
	# 彩虹 (rainbow): 七色光(magic)/七彩风暴/折射镜 魔法AOE + shield 自施 (skill-handlers.ts:3011-3060, 5127)
	"rainbowStorm", "rainbowReflect",
	# 赛博 (cyber): 部署无人机/虫群护盾 自施 (skill-handlers.ts:5707,5933 纯自增益; 不可 80px 冲向敌方)。
	#   注: 普攻 physical(5段拳) 仍走默认 80px melee dash; cyberBeam 走 KOF 专属编排 (见 windup/post-impact)。
	"cyberDeploy", "cyberSwarmShield",
	# 各龟"强化态" passive 技 (no-op handler, touched=[caster]): 万一被 AI/forced 选中, 走原地 hop 不 melee。
	"phoenixEnhancedRebirth", "lavaEnhancedRage", "cyberEnhancedDrone",
	"crystalBall", "rainbowEnhancedPrism",
	# 通用 magic/shield/heal type (彩虹[0]=magic 2段, [1]=shield; 1:1 PoC 远程, 非 80px melee)
	"magic", "shield", "heal",
	# ── 第 4 批 6 龟: 赌神/猎人/海盗/糖果/泡泡/线条 ──
	#   PoC 铁律 (BattleScene.ts:3461 SKIP_POSITIONAL_HOP 只含 basicSlam/basicChiWave/ninjaImpact/ninjaBackstab):
	#   其余所有有 type 的技能全走 25px attack-hop (非 80px melee dash, 那是无 type 的 legacy fallback ts:3518)。
	#   故本批"远程/魔法/AOE/自施"全列此处走 25px hop;
	#   基础普攻 physical (海盗弯刀/糖果锤/泡泡攻击) 沿用既有 Godot 约定 (前 3 批 physical 走 80px 冲锋) 不在此列。
	# 赌神 (gambler): 卡牌/万能牌/赌注 单体物理多段 + 命运之轮(passive). 卡牌/赌注有 pulse punch (见 windup)。
	"gamblerCards", "gamblerDraw", "gamblerBet", "gamblerFateWheel", "gamblerEnhancedMulti",
	# 猎人 (hunter): 射箭/连珠箭飞 hunter-arrow 投射物 (见 windup); 隐蔽自施/毒箭单体/印记单体。
	"hunterShot", "hunterStealth", "hunterBarrage", "hunterPoison", "hunterMark",
	# 海盗 (pirate): 火炮齐射 AOE / 朗姆酒自疗 / 掠夺单体 / 海盗船(passive)。(弯刀=physical 走 80px, 不在此)
	"pirateCannonBarrage", "piratePlunder", "pirateShipPassive",
	# 糖果 (candy): 焦糖铠自盾 / 糖衣炮弹 AOE / 糖果罐(陷阱 passive) / 糖果炸弹(passive)。(糖果锤=physical)
	"candyBarrage", "sweetTrap", "candyBombPassive",
	# 泡泡 (bubble): 泡泡盾自盾 / 束缚单体 / 爆破竖排 AOE / 治愈泡泡治疗。(泡泡攻击=physical)
	"bubbleShield", "bubbleBind", "bubbleBurst", "bubbleHeal",
	# 线条 (line): 素描多段单体 / 连笔双体(墨线 VFX 见 post) / 画龙点睛单体引爆 / 速写(passive) / 墨水炸弹 AOE。
	"lineSketch", "lineLink", "lineFinish", "lineRapid", "lineInkBomb",
	# ── 第 5 批 5 龟: 闪电/双头/钻石/财神/骰子 ──
	#   PoC 铁律 (BattleScene.ts:3461 SKIP_POSITIONAL_HOP 只含 basicSlam/basicChiWave/ninjaImpact/ninjaBackstab):
	#   本批所有"有 type 的技能"全走 25px attack-hop (handler 纯 floatNum/sleep, 无 caster 位移/juggle)。
	#   仅 2 个"裸 physical type"普攻 (双头psi近战 / 钻石切割cut) 不在此列 → 沿用既有 Godot 80px melee 约定。
	# 闪电 (lightning): 打击5段魔法+溅射 / 涌动(即时电击,天降闪电VFX 见 post) / 雷暴20随机 / 感电AOE真伤 / 雷盾自施
	#   (skill-handlers.ts:2873-2999 全 floatNum+sleep; 仅 lightningSurgeBuff 内 fireLightningVfx 天降闪电)
	"lightningStrike", "lightningSurgeBuff", "lightningBarrage", "lightningSurge", "lightningShield",
	# 双头 (two_head): 魔波4段(magic+真伤交替) / 换形melee(1.2×物理) / 精神冲击(magic+破盾+治疗削减)
	#   (skill-handlers.ts:4015-4172 全 floatNum+sleep180; twoHeadSwitch 切形态打 1.2× 物理一击, 非 SKIP → 25px hop)
	#   注: 双头psi"心灵冲击"近战 type=physical (aoe) → 走 80px melee, 不在此列。
	"twoHeadMagicWave", "twoHeadSwitch", "twoHeadMindBlast",
	# 钻石 (diamond): 坚不可摧自施盾 / 碰撞(累计眩晕) / 钻石冲撞(DEF+MR+流血)
	#   (skill-handlers.ts:2383-2440,5873 全 floatNum; 无 juggle/位移)。注: 钻石切割 type=physical → 80px melee, 不在此列。
	"diamondFortify", "diamondCollide", "diamondSmash",
	# 财神 (fortune): 金剑打击(物理2段,coin加成) / 骰子(掷币+回血+盾) / 梭哈(逐枚物理+真伤) / 财神到(买装,自施) / 聚财(自施)
	#   (skill-handlers.ts:3749-3797,5603-5668 全 floatNum+sleep; 无 caster 位移/VFX)
	"fortuneStrike", "fortuneDice", "fortuneAllIn", "fortuneBuyEquip", "fortuneGainCoins",
	# 骰子 (dice): 骰子攻击(3段物理) / 孤注一掷(AOE物理+吸血,自施全敌) / 命运骰子(暴击buff自施) / 闪现攻击(随机多段)
	#   (skill-handlers.ts:2638-2681,5029-5097 全 floatNum+sleep; 无 caster 位移/VFX)
	"diceAttack", "diceAllIn", "diceFate", "diceFlashStrike",
	# ── 第 6 批 4 龟 (最后一批, 特殊机制): 无头/缩头/龟壳/宝箱 ──
	#   PoC 铁律 (BattleScene.ts:3461 SKIP_POSITIONAL_HOP 只含 basicSlam/basicChiWave/ninjaImpact/ninjaBackstab):
	#   本批所有"有 type 的技能"全走 25px attack-hop。逐一审 skill-handlers.ts 均为纯 floatNum + sleep,
	#   无 caster 位移 / juggle / 专属 VFX (召唤/换装/储能/储能波/亡灵锁血等均为 passive/logic 层, 不在演出层)。
	#   仅 2 个"裸 physical type"普攻 (无头撕咬 headless-0 / 缩头攻击 hiding-0) 不在此列 → 沿用既有 Godot 80px melee 约定。
	# 无头 (headless): 恐吓(twoHeadFear, 物理+恐惧 5839) / 灵魂收割(soulReap AOE 物理 5393) /
	#   亡灵风暴(headlessStorm AOE 3段物理 3945) / 灵魂打击(headlessSoulStrike 单体魔法 5372)。撕咬=physical→80px melee。
	#   (亡灵锁血/损血加攻 = undeadRage passive, 不在演出层)
	"twoHeadFear", "soulReap", "headlessStorm", "headlessSoulStrike",
	# 缩头 (hiding): 防御(hidingDefend 自盾 3927) / 指挥(hidingCommand 命令随从额外出手 5510) /
	#   强化随从(hidingBuffSummon 自施 buff 5485) / 强化喊龟(hidingEnhancedSummon passive)。攻击=physical→80px melee。
	#   (召唤随从/变身护盾 = summonAlly passive + summonAutoAction, 已在别处实现; 此层只视觉 25px hop)
	"hidingDefend", "hidingCommand", "hidingBuffSummon", "hidingEnhancedSummon",
	# 龟壳 (shell): 攻击(shellStrike 2段phys/true交替+溅射 2298) / 复制(shellCopy 复制敌技 2139) /
	#   吸收(shellAbsorb 偷最大HP 2273) / 侵蚀(shellErode 多道弯波打整列魔法 2231) / 强化觉醒(shellEnhanceAwaken passive)。
	#   注: shellStrike 是龟壳普攻但 type=shellStrike(非裸 physical) → 1:1 铁律走 25px hop (PoC 无 caster dash, 纯 floatNum)。
	#   (气场觉醒/储能波 = auraAwaken passive + processEnergyWave, 不在演出层)
	"shellStrike", "shellCopy", "shellAbsorb", "shellErode", "shellEnhanceAwaken",
	# 宝箱 (chest, 玩家宠物宝箱; ≠中立 treasure_golem 宝箱怪): 宝箱砸击(chestSmash 3段物理 3820) /
	#   清点财宝(chestCount 自疗+自盾 5672) / 财宝风暴(chestStorm AOE 5段物理 4875) / 寻宝直觉(chestIntuition passive) / 贪婪(chestGreed passive)。
	#   注: chestSmash/chestStorm 命中的"雷刃(thunder)装备闪电劈下 VFX"(skill-handlers.ts:3854,4921) 依赖
	#   chestTreasure 装备变种系统 (_chestEquipThunder/_goldLightning), 该 logic 层未移植 → 此层不加 (避免自创); 见报告遗留项。
	"chestSmash", "chestCount", "chestStorm", "chestIntuition", "chestGreed",
]


## ── 原语: caster 前冲 lunge (再归位由 post 段负责) ──
##   1:1 PoC fallback dash (BattleScene.ts:3518): dashX = home ± 80px, 180ms power2.in.
func _lunge(idx: int, side: String, px: float, dur: float) -> void:
	var node: Node2D = slot_nodes[idx]
	var home_pos: Vector2 = node.get_meta("home_pos", node.position)
	var dir: float = 1.0 if side == "left" else -1.0
	var tw := create_tween()
	tw.tween_property(node, "position:x", home_pos.x + dir * px, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # power2.in


## ── 原语: caster 归位 (lunge 回程) — 1:1 PoC BattleScene.ts:3590-3593 280ms power2.out ──
func _lunge_return(idx: int, dur: float = 0.28) -> void:
	var node: Node2D = slot_nodes[idx]
	var home_pos: Vector2 = node.get_meta("home_pos", node.position)
	var tw := create_tween()
	tw.tween_property(node, "position:x", home_pos.x, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


## ── 原语: 通用攻击 hop (1:1 PoC playAttackHop, BattleScene.ts:3416-3500) ──
##   1200ms 自驱 (fire-and-forget, 节点自动归位), 时间轴 Linear, 6 关键帧逐段 smoothstep.
##   关键帧 dir=+1左/-1右: 0 → 15%(±18,-6) → 20%(±25,0 落240ms) → 80%(±25,0 hold960ms) → 95%(±5,-3) → 100%(home).
##   命中帧 = 400ms (ATTACK_DAMAGE_SYNC_MS, windup 在外面 await 0.40 后 execute). 旧版单段0.15s无hold=出手太快.
const _ATK_HOP_KF := [[0.0, 0.0, 0.0], [0.15, 18.0, -6.0], [0.20, 25.0, 0.0], [0.80, 25.0, 0.0], [0.95, 5.0, -3.0], [1.0, 0.0, 0.0]]
func _attack_hop(idx: int, side: String) -> void:
	if idx < 0 or idx >= slot_nodes.size():
		return
	var node: Node2D = slot_nodes[idx]
	var home: Vector2 = node.get_meta("home_pos", node.position)
	var dir: float = 1.0 if side == "left" else -1.0
	# 同节点上一段 hop 没跑完就再出手 (boss双动) → 先杀旧 tween 防叠加抖动
	if node.has_meta("atk_hop_tw"):
		var old = node.get_meta("atk_hop_tw")
		if old is Tween and old.is_valid():
			old.kill()
	# hop 期间影子【接地】: 节点 dy 抬起(-6/-3)时影子留地面, 只随 x 横移 — 1:1 PoC (循环里只 shadow.x=homeX+dx, 从不动 shadow.y)
	node.set_meta("_ground_shadow", true)
	var tw := node.create_tween()
	node.set_meta("atk_hop_tw", tw)
	tw.tween_method(_attack_hop_step.bind(node, home, dir), 0.0, 1.0, 1.2).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(_unground_shadow.bind(node))   # hop 结束: 撤接地标记 + 影子归位 home


func _attack_hop_step(p: float, node: Node2D, home: Vector2, dir: float) -> void:
	if not is_instance_valid(node):
		return
	var ki: int = 0
	for i in range(_ATK_HOP_KF.size() - 1):
		if p >= _ATK_HOP_KF[i][0] and p <= _ATK_HOP_KF[i + 1][0]:
			ki = i
			break
		if p > _ATK_HOP_KF[i + 1][0]:
			ki = i + 1
	var a: Array = _ATK_HOP_KF[ki]
	var b: Array = _ATK_HOP_KF[mini(ki + 1, _ATK_HOP_KF.size() - 1)]
	var span: float = b[0] - a[0]
	var lr: float = clampf((p - a[0]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var local: float = lr * lr * (3.0 - 2.0 * lr)   # smoothstep ≈ 逐段 ease-in-out
	node.position.x = home.x + dir * (a[1] + (b[1] - a[1]) * local)
	node.position.y = home.y + (a[2] + (b[2] - a[2]) * local)


## ── 原语: 击飞抛物 juggle (物理 sim, 1:1 PoC buildJugglePhysics, skill-handlers.ts:83-119) ──
##   3 段 (上+后) 冲量 (t=0/220/440ms, vy=-260/-310/-360, vx=knockX×1.6/1.3/0.9) + 重力 g=1500
##   → 落地砸 (snap y=0, rot=-82°) → 躺 560ms → 起身缓动归位 330ms. 共 2000ms, 采样 64 步。
##   knock_x = dir × 55 (PoC chiwave knockX). 移动 node (脚底锚) + 旋转 node。
const _JUGGLE_TOTAL_MS := 2000.0
func _build_juggle_physics(knock_x: float) -> Array:
	var g := 1500.0
	var hit_t := [0.0, 220.0, 440.0]
	var hit_vy := [-260.0, -310.0, -360.0]
	var hit_vx := [knock_x * 1.6, knock_x * 1.3, knock_x * 0.9]
	var rot_imp := [-45.0, 70.0, -95.0]
	var lie_pose_ms := 560.0
	var recover_ms := 330.0
	var slam_rot := -82.0
	var steps := 64
	var dt := _JUGGLE_TOTAL_MS / float(steps) / 1000.0
	var sx := 0.0
	var sy := 0.0
	var srot := 0.0
	var svx := 0.0
	var svy := 0.0
	var svrot := 0.0
	var hit_idx := 0
	var slam_t := -1.0
	var slam_x := 0.0
	var slam_pose_rot := 0.0
	var recover_t := -1.0
	var out: Array = []
	for i in range(steps + 1):
		var t_ms := (float(i) / float(steps)) * _JUGGLE_TOTAL_MS
		while hit_idx < hit_t.size() and t_ms >= hit_t[hit_idx]:
			svy = hit_vy[hit_idx]
			svx = hit_vx[hit_idx]
			svrot = rot_imp[hit_idx]
			hit_idx += 1
		if slam_t < 0.0:
			svy += g * dt
			sx += svx * dt
			sy += svy * dt
			srot += svrot * dt
			if sy >= 0.0 and hit_idx == hit_t.size() and t_ms > 500.0:
				sy = 0.0
				srot = slam_rot
				svx = 0.0; svy = 0.0; svrot = 0.0
				slam_t = t_ms
				slam_x = sx
				slam_pose_rot = slam_rot
		elif recover_t < 0.0:
			if t_ms >= slam_t + lie_pose_ms:
				recover_t = t_ms
		else:
			var p: float = clampf((t_ms - recover_t) / recover_ms, 0.0, 1.0)
			var e: float = (2.0 * p * p) if p < 0.5 else (1.0 - pow(-2.0 * p + 2.0, 2.0) / 2.0)
			sx = slam_x * (1.0 - e)
			sy = 0.0
			srot = slam_pose_rot * (1.0 - e)
		out.append(Vector3(sx, sy, srot))
	return out


func _sample_juggle(samples: Array, t01: float) -> Vector3:
	var n := samples.size() - 1
	var f := clampf(t01, 0.0, 1.0) * float(n)
	var i := int(floorf(f))
	var frac := f - float(i)
	var a: Vector3 = samples[i]
	var b: Vector3 = samples[mini(n, i + 1)]
	return a + (b - a) * frac


## 击飞 target 节点 (knock_x 已含方向). awaitable — 跑完 node 回 home。
func _juggle(target_idx: int, knock_x: float) -> void:
	var node: Node2D = slot_nodes[target_idx]
	if not is_instance_valid(node):
		return
	# 龟蛋免击飞 (静物基地, 不被抛入空中): 用蛋专属受击抖动代替 juggle 抛投
	if target_idx >= 0 and target_idx < fighters.size() and fighters[target_idx].get("_isEgg", false):
		_play_egg_hit(target_idx)
		return
	# 动 avatar(龟身)而非 root — 否则影子(root 子节点)随击飞一起抬起 = 影子离地 (1:1 PoC doJuggle 只动 sprite;
	#   同 _hit_knockback: 影子只跟横向 x, y 留在地面).
	var avatar: Sprite2D = node.get_meta("avatar", null)
	if avatar == null:
		return
	var a_home: Vector2 = avatar.get_meta("home", avatar.position)
	var shadow: Sprite2D = node.get_meta("shadow", null)
	var s_home: Vector2 = (shadow.get_meta("home", shadow.position) if shadow != null else Vector2.ZERO)
	var samples := _build_juggle_physics(knock_x)
	var dur := _JUGGLE_TOTAL_MS / 1000.0
	var tw := create_tween()
	tw.tween_method(
		func(p: float):
			if not is_instance_valid(avatar):
				return
			var s := _sample_juggle(samples, p)
			avatar.position = a_home + Vector2(s.x, s.y)
			avatar.rotation = deg_to_rad(s.z)
			if shadow != null and is_instance_valid(shadow):
				shadow.position = Vector2(s_home.x + s.x, s_home.y),   # 影子只跟横向, 不抬起
		0.0, 1.0, dur)
	await tw.finished
	if is_instance_valid(avatar):
		avatar.position = a_home
		avatar.rotation = 0.0
	if shadow != null and is_instance_valid(shadow):
		shadow.position = s_home


## ── per-skill windup: 命中前编排 (caster 摆位/前冲/蓄力). 返回时=命中帧 ──
func _skill_windup(actor_idx: int, target_idx: int, skill_type: String) -> void:
	var actor: Dictionary = fighters[actor_idx]
	var side: String = actor.get("side", "left")
	match skill_type:
		"basicChiWave":
			# 龟派气波 (skill-handlers.ts:888) — caster 不前冲, 滑到目标横排 (y→rowY) 发波。
			#   PoC: cut-in 500 + 走到排 280 + zoom 300 + windup 550 → 发射。压缩节奏: 滑到排 + 蓄力。
			await _chiwave_caster_to_row(actor_idx, target_idx)
		"basicSlam":
			# 过肩摔 (skill-handlers.ts:1077) — caster dash 到 target 旁 (gap 58px) 抓取。
			await _slam_caster_dash(actor_idx, target_idx)
		"turtleShieldBash":
			# 龟盾击飞 (skill-handlers.ts:678-719) — caster chop(4段440ms 旋转+Ybob) + 180ms金弧 + 250ms爆裂。
			#   (原缺整段 caster 演出, 只有 post 段 14 击飞; 金弧/爆裂 sprite 已注册但从不播)
			await _shield_bash_caster_chop(actor_idx, target_idx)
		"basicBarrage":
			# 打击 (skill-handlers.ts:809) — caster windup 280ms 后 N 段随机弹幕 (bolt VFX 走 _play_skill_vfx)。
			#   通用前冲 hop (PoC playAttackHop) + windup。bolt 飞行编排留待后续 (按 result_effects)。
			_lunge(actor_idx, side, 25.0, HOP_DURATION)
			await get_tree().create_timer(0.28).timeout
		"ninjaImpact":
			# 冲击 (ninja.js:155-374) — caster 跑到目标排→蓄力→dash 穿过目标列后排. 命中在飞行中段。
			#   伤害在 execute 算; 此处只编排 caster dash 位移 + dash.png 18帧序列叠层 + trail。
			await _ninja_impact_dash(actor_idx, target_idx)
		"ninjaBackstab":
			# 背刺 (ninja.js:382-515) — F1-3 蓄力300 → F4 闪现到目标后方 → 停留(3段戳刺时序由停留盖)。
			#   伤害在 execute 算; 此处编排闪现位移 + backstab.png 18帧序列叠层。
			await _ninja_backstab_dash(actor_idx, target_idx)
		"ninjaBomb":
			# 炸弹 (ninja.js:523-700) — bomb sprite 从 caster 抛物线飞向敌阵中心 (400ms) → 引信 400ms → 爆。
			#   伤害在 execute 算 (引爆点 800ms). 此处抛炸弹+引信等待, 让命中帧≈引爆。
			_lunge(actor_idx, side, 25.0, HOP_DURATION)   # 投掷预备小跳 (PoC attack-hop)
			await _ninja_bomb_throw(actor_idx)
		"ninjaShuriken":
			# 飞镖 (ninja.js:1-60) — attack-hop 25px → 260ms 后飞镖 sprite 飞向目标 (280ms, 命中 240ms)。
			_lunge(actor_idx, side, 25.0, HOP_DURATION)
			await get_tree().create_timer(0.26).timeout          # PoC sleep(260) hop apex
			await _ninja_shuriken_throw(actor_idx, target_idx)   # 飞 240ms 至命中帧
		"ghostPhase":
			# 虚化 (ghost.js:62) — 自施 physImmune + 2段真伤; phase.png 13帧序列盖在 caster 身上, 不前冲。
			# PoC BootScene:425 frameRate=10 → 13帧/10fps=1300ms (非13fps)
			_play_action_sheet_overlay(actor_idx, "pets/animations/ghost/phase.png", 64, 10.0)
			await get_tree().create_timer(0.2).timeout
		"ghostPhantom":
			# 幽冥突袭 (ghost.js:382 / skill-handlers.ts:1382) — 不前冲, caster 不动, 伤害立即:
			#   1:1 PoC handler 在 dealMagic 前【无】windup sleep(原自加 0.18 已撤)。幻影+触碰 VFX 在 post 段。
			pass
		"cyberBeam":
			# 能量大炮 KOF 演出 (cyber.js:92-334 / skill-handlers.ts:3155) — 镜头 zoom 留后。
			#   1) KOF cut-in: 全屏青色闪 500ms + 中心 orb 扩散 (1:1 ts:3187-3202)
			#   2) caster Y-hop 抛物到目标横排 (460ms Sine.easeInOut, ts:3210-3224)
			#   3) windup 蓄力 tint 550ms (ts:3226-3230) → 发射 (beam sweep VFX 走 _play_skill_vfx)
			await _cyber_beam_windup(actor_idx, target_idx)
		"hunterShot":
			# 射箭 (skill-handlers.ts:2694): attack-hop 25px -> windup 240ms (caster 到前拉弓)
			#   -> 首支 hunter-arrow 投射物飞 240ms 至命中帧. 伤害由 execute 算, 后续段随其时序。
			_lunge(actor_idx, side, 25.0, HOP_DURATION)
			await get_tree().create_timer(0.24).timeout
			# 3 支箭逐发 (1:1 PoC hits=3, 每支飞240ms, 段间140ms, ts:2717-2747); 前2支 fire-and-forget, 末支 await 接命中帧
			_fire_arrow(actor_idx, target_idx, 0.24)
			await get_tree().create_timer(0.14).timeout
			_fire_arrow(actor_idx, target_idx, 0.24)
			await get_tree().create_timer(0.14).timeout
			await _fire_arrow(actor_idx, target_idx, 0.24)
		"hunterBarrage":
			# 连珠箭 (skill-handlers.ts:4960): attack-hop + windup 220ms 拉弓 -> execute 10 段随机飞箭。
			#   10 支箭由 _play_barrage_bolts 逐发 (120ms错峰); 此处不再额外发箭 (原多发1支=11支重复)。
			_lunge(actor_idx, side, 25.0, HOP_DURATION)
			await get_tree().create_timer(0.22).timeout
		"gamblerCards":
			# 卡牌射击 (skill-handlers.ts:4774): attack-hop 25px + 一记 pulse punch 起势 (PoC handler 无每段脉冲, 仅900ms命中节奏)。
			_lunge(actor_idx, side, 25.0, HOP_DURATION)
			_pulse_avatar(actor_idx, 1.12, 0.15)
			await get_tree().create_timer(0.18).timeout
		"gamblerBet":
			# 赌注 (skill-handlers.ts:4721): attack-hop + 【每段挥击脉冲】1:1 PoC ts:4744 pulseScale(caster,1.12,150)×7段(段间~460ms)。
			_lunge(actor_idx, side, 25.0, HOP_DURATION)
			_gambler_bet_pulses(actor_idx, 7, 0.46)   # fire-and-forget 7记脉冲, 与 execute 7段同步
			await get_tree().create_timer(0.18).timeout
		"starBlackhole":
			# 黑洞: 旋涡 VFX 先播 → 等 300ms → 再 execute 结算 (1:1 PoC skill-handlers.ts:4399 sleep(300)
			#   在 applyRawDamage 之前; 修原顺序反转——旧版 execute 先扣血、post 才播旋涡 = 视觉与数值脱节)。
			actor["_atkHop"] = true
			_attack_hop(actor_idx, side)
			_play_blackhole_vfx(target_idx)
			await get_tree().create_timer(0.3).timeout
		"lightningSurgeBuff":
			# 涌动即时电击: 天降闪电【先于】伤害劈下 (1:1 PoC ts:2991 fireLightningVfx 在 applyRawDamage 前).
			#   原走默认 ranged + 只在 post 段才劈 = 伤害数字先出、闪电后到, 顺序反 (同 starBlackhole 修过的反转).
			actor["_atkHop"] = true
			_play_cast_tell(actor_idx)
			_attack_hop(actor_idx, side)
			await get_tree().create_timer(0.40).timeout
			_play_lightning_strike(target_idx)   # 命中帧劈下, 紧接 execute 应用真伤
		"pirateCannonBarrage":
			# 火炮齐射: 出手前全敌飘"炮击!"预警 + 蓄势 600ms 再轰 (1:1 PoC skill-handlers.ts:5335 sleep(600) 前置)
			actor["_atkHop"] = true
			_play_cast_tell(actor_idx)
			_attack_hop(actor_idx, side)
			for ei in _all_enemy_idxs(actor_idx):
				_spawn_passive_text(ei, "💥炮击!")
			await get_tree().create_timer(0.6).timeout
		_:
			if skill_type in _RANGED_SKILLS:
				# 远程/魔法/AOE: 通用 attack-hop (1:1 PoC playAttackHop 1200ms 自驱+hold, 命中帧400ms), VFX/伤害由 handler 展示
				#   + 施法 tell (1:1 PoC: 所有技能 playAction('attack'), 无攻击帧的龟回退 glow+脉冲) — 修施法龟全程 idle 不反应
				actor["_atkHop"] = true
				_play_cast_tell(actor_idx)
				_attack_hop(actor_idx, side)
				await get_tree().create_timer(0.40).timeout
			elif skill_type in _SELF_DRIVE_SKILLS:
				# 其他自驱技能: 暂用通用前冲 + 施法 tell
				_play_cast_tell(actor_idx)
				_lunge(actor_idx, side, 25.0, HOP_DURATION)
				await get_tree().create_timer(HOP_DURATION).timeout
			else:
				# 物理普攻 / 近战单体 (ghostTouch/bambooLeaf/bambooSmack/物理裁决等):
				#   通用 attack-hop (1:1 PoC playAttackHop ts:3416, 1200ms 自驱 6帧 smoothstep + hold, 命中帧400ms)
				#   + 施法 tell: ACTION_PETS(basic/ghost/ninja/golem) 播动作帧, 其余龟 glow+脉冲 (1:1 PoC playAction)
				actor["_atkHop"] = true
				_play_cast_tell(actor_idx)
				_attack_hop(actor_idx, side)
				await get_tree().create_timer(0.40).timeout


## ── per-skill post-impact: 命中后编排 (target 击飞 / caster 归位) ──
## 龟派气波: 某目标 ci 的【波头到达延时】(= cw_frac × 1.5s, 下限 0.08)。
##   伤害段显示 与 juggle 击飞 共用此基准 → "波头扫到即掉血即弹飞"。
##   修根因: 原伤害段从【发波瞬间】(h×220ms)跳, 击飞却等【波头到达】(cw_frac×1.5) → 血先掉、龟后飞 = 与 PoC 整个观感不同。
func _chiwave_arrival_delay(actor_idx: int, target_idx: int, ci: int) -> float:
	var dir: float = 1.0 if fighters[actor_idx].get("side", "left") == "left" else -1.0
	var col_idxs := _chiwave_column_idxs(actor_idx, target_idx)
	var cw_start: float = float(slot_nodes[actor_idx].get_meta("home_pos", slot_nodes[actor_idx].position).x) + dir * 36.0
	var cw_end: float = cw_start
	for ce in col_idxs:
		var ehx: float = float(slot_nodes[ce].get_meta("home_pos", slot_nodes[ce].position).x)
		cw_end = (maxf(cw_end, ehx) if dir > 0.0 else minf(cw_end, ehx))
	var cw_total: float = cw_end + dir * 70.0 - cw_start
	if absf(cw_total) < 1.0:
		cw_total = dir
	var cw_frac: float = clampf((float(slot_nodes[ci].get_meta("home_pos", slot_nodes[ci].position).x) - dir * 120.0 - cw_start) / cw_total, 0.0, 1.0)
	return maxf(0.08, cw_frac * 1.5)


func _skill_post_impact(actor_idx: int, target_idx: int, skill_type: String) -> void:
	match skill_type:
		"basicChiWave":
			# caster 滑回原排 (1:1 PoC:1063 走回 home 300ms cubic.inOut) + 目标列弹空 juggle
			var actor: Dictionary = fighters[actor_idx]
			var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
			# 同列敌方目标各弹空 3 连物理, 按波头到达逐个错峰 (1:1 PoC ts:1046-1055, 非同时, 近先弹)。
			#   延时 = _chiwave_arrival_delay, 与该目标的伤害段显示共用同一基准 → 到达即掉血即弹飞。
			var max_arr: float = 0.0
			for ci in _chiwave_column_idxs(actor_idx, target_idx):
				var ad: float = _chiwave_arrival_delay(actor_idx, target_idx, ci)
				max_arr = maxf(max_arr, ad)
				_chiwave_juggle_after(ci, dir * 55.0, ad)
			# 关键修: 等最远目标波头到达 + 3段伤害结算(~440ms)都跑完, 再走回/拉镜头。
			#   (1:1 PoC ts:1047-1059 await Promise.all(doJuggle) → sleep560 → caster back。
			#    原 caster_back 从 post_impact 开始就 sleep0.56 → 镜头在击飞前(cw_frac×1.5)就拉远 = climax 跑到镜头外)
			await get_tree().create_timer(max_arr + 0.44).timeout
			await _chiwave_caster_back(actor_idx)
		"basicSlam":
			# 过肩摔: target 抛向敌方阵型中心 → 落地砸 → 趴 → 起身走回; caster 落定后冲回。
			await _slam_throw(actor_idx, target_idx)
		"turtleShieldBash":
			# 龟盾: target 14 段击飞 (1400ms, 1:1 skill-handlers.ts:739-760)
			await _shield_bash_knockup(target_idx)
		"ninjaImpact":
			# 冲击 (ninja.js:349-360): 命中后站立 500 → 闪回 home → recovery 400 → 还原 idle。
			#   命中时同步 target 击飞 juggle (knockX = dir×56) 并行。
			var a_imp: Dictionary = fighters[actor_idx]
			var d_imp: float = 1.0 if a_imp.get("side", "left") == "left" else -1.0
			_juggle(target_idx, d_imp * 56.0)   # 主目标击飞 (PoC applyKnockupJuggle)
			# 身后单位也击飞 (PoC skill-handlers.ts:1654 对 fighterBehind 同样 applyKnockupJuggle)
			var behind_imp = SlotHelpers.fighter_behind(fighters, fighters[target_idx])
			if behind_imp != null:
				var bi: int = fighters.find(behind_imp)
				if bi >= 0 and fighters[bi].get("alive", false):
					_juggle(bi, d_imp * 56.0)   # fire-and-forget 并行
			# 等冲刺飞完(到 dash_x)再归位 — 命中在中段提前返回了, 冲刺 tween 可能还在跑, 防抢位
			var imp_ft = slot_nodes[actor_idx].get_meta("_ninja_flight_tw", null)
			if imp_ft != null and is_instance_valid(imp_ft) and imp_ft.is_running():
				await imp_ft.finished
			await _ninja_caster_snap_home(actor_idx)
		"ninjaBackstab":
			# 背刺 (ninja.js:501-461): 3段戳刺停留 1100 → 闪回 home → recovery 400 → 还原 idle。
			#   停留期 target 受击白闪 ×3 (1:1 PoC per-stab setTint 0xffffff:2008-2014, 原3段无受击反馈)
			for _si in range(3):
				_flash_hit(target_idx)
				await get_tree().create_timer(0.37).timeout   # 3×0.37 ≈ PoC sleep(1100)
			await _ninja_caster_snap_home(actor_idx)
		"ghostPhantom":
			# 幽冥突袭 (ghost.js:411-451): 命中处叠 幻影(5帧)+触碰(7帧) → target 13段击退 juggle (1400ms)。
			var pos_pp: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
			_play_vfx("ghost-phantom", pos_pp, 1.0)
			_play_vfx("ghost-touch", pos_pp, 0.875)
			await _ghost_phantom_knockback(actor_idx, target_idx)
		"ninjaBomb", "ghostPhase":
			# 自施/AOE 自驱: 无 caster 归位 (位移已在 windup 自收), 不走通用 return。
			pass
		"cyberBeam":
			# 能量大炮 (cyber.js:275-334 / skill-handlers.ts:3275-3355):
			#   命中横排敌人各 2 段击飞 juggle (并行) + 震屏 → caster 抛回原排。镜头 zoom 复位留后。
			_play_screen_shake(0.26, 12.0)   # 1:1 ts:3277 cam.shake(260, 0.012)
			for ci in _chiwave_column_idxs(actor_idx, target_idx):   # 同列敌人 (横排) — 复用列查询
				_cyber_beam_juggle(actor_idx, ci)                     # fire-and-forget 并行 2 段击飞
			await _cyber_beam_caster_back(actor_idx)
		"rockShockwave":
			# 磐石之躯 (skill-handlers.ts:2472): 命中后横排敌各 knockup 小跳 (1:1 api.knockup, 原漏=命中后目标不动)
			for ki in _chiwave_column_idxs(actor_idx, target_idx):
				_knockup_hop(ki)
		"starWormhole", "starGravityWarp":
			# 虫洞/引力扭曲 (star.js / skill-handlers.ts:4565,4566 / 4477+): 命中后对横排(虫洞)/全敌(引力) knockup 小跳。
			#   1:1 PoC api.knockup = playAction('knockup') = 上跳 40px 旋转落回 400ms (BattleScene.ts:3906)。
			#   注: starGravityWarp 满星换位由 result.relayout 在主流程处理 (已接, BattleScene.gd:2450)。
			for ki in _chiwave_column_idxs(actor_idx, target_idx) if skill_type == "starWormhole" else _all_enemy_idxs(actor_idx):
				_knockup_hop(ki)                                      # 并行小跳
			await _lunge_return(actor_idx, 0.28)
		"starBlackhole":
			# 黑洞 (star.js:174-235): 旋涡 VFX 已在 windup 段先于伤害播 (修顺序反转), post 仅归位。
			await _lunge_return(actor_idx, 0.28)
		"lineLink":
			# 连笔 (skill-handlers.ts:5244 / BattleScene.ts:5694 drawInkLink): 主目标与第 2 目标间画墨线。
			#   第 2 目标 = enemies.find(alive && != target) (1:1 line.js:79 second). 命中后画一道淡紫墨线连两者脚底。
			var second_idx := _line_second_target(actor_idx, target_idx)
			if second_idx >= 0:
				_draw_ink_link(target_idx, second_idx)
			await _lunge_return(actor_idx, 0.8)   # 1:1 PoC 末尾 sleep(800) 让墨线驻留 (line.js:106, ts:5310)
		# lightningSurgeBuff 闪电已移到 windup 段(先于伤害劈下), post 落默认分支(自归位).
		_:
			if not (skill_type in _SELF_DRIVE_SKILLS):
				var atk_actor: Dictionary = fighters[actor_idx]
				if atk_actor.get("_atkHop", false):
					atk_actor["_atkHop"] = false   # _attack_hop 1200ms 自归位, 不再 _lunge_return (防抢 position)
				else:
					# 旧 _lunge 路径(专属技能)归位 (1:1 PoC:3590 280ms power2.out)
					await _lunge_return(actor_idx, 0.28)


# ── 龟派气波 choreography (1:1 skill-handlers.ts basicChiWave) ──
## caster 滑到目标横排 (保留 X, y→目标排 Y), 280ms cubic.out (PoC casterHold 第一段)
func _chiwave_caster_to_row(actor_idx: int, target_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var t_node: Node2D = slot_nodes[target_idx]
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var t_home: Vector2 = t_node.get_meta("home_pos", t_node.position)
	var row_y: float = t_home.y
	# ── 1) 青屏 cut-in (1:1 skill-handlers.ts:975-983: 0x3c8cff ADD混合, alpha 0→.45→.55→0, ~500ms) ──
	_screen_cutin_flash(Color(0x3c / 255.0, 0x8c / 255.0, 1.0), [0.45, 0.55, 0.0], [0.12, 0.12, 0.26])
	await get_tree().create_timer(0.5).timeout
	# ── 2) caster 滑到目标横排 (保留 X, y→目标排 Y), 280ms cubic.out ──
	c_node.z_index = 50
	var tw := create_tween()
	tw.tween_property(c_node, "position:y", row_y, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 滑到排 fire-and-forget(不 await): 1:1 PoC casterHold=tweens.chain 并发, 与下面 zoom(300)+蓄力(550)重叠.
	# 原 await tw.finished 把 280ms 滑行串行化 → 发波 + 全列弹空伤害都晚 280ms.
	# ── 3) 镜头原地放大 1.2× (焦点=施法者↔目标中点 X / 目标排 Y, 1:1 ts:1001-1006 origin-zoom) ──
	var focus := Vector2((c_home.x + t_home.x) / 2.0, row_y)
	_camera_focus(focus, 1.2, 0.4, "origin")
	await get_tree().create_timer(0.3).timeout   # 1:1 PoC sleep(300)
	# ── 4) 蓄力 windup 550ms (1:1 PoC sleep(550), ts:1015). 不再压缩(自作主张已撤)。──
	_spawn_passive_text(actor_idx, "⚡蓄气中...")
	await get_tree().create_timer(0.55).timeout
	# 发波 VFX 横向贯穿目标排 (1:1 PoC wave sprite travel, 胸口高度 row_y-15)
	_chiwave_wave_vfx(actor_idx, target_idx, c_home.y)


## 波头到达后延时弹空单个目标 (fire-and-forget, 1:1 PoC ts:1053 await sleep(...)→doJuggle)
func _chiwave_juggle_after(idx: int, knock_x: float, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if idx >= 0 and idx < fighters.size() and fighters[idx].get("alive", false):
		_juggle(idx, knock_x)


## caster 走回原排 + 落 z_index (1:1 PoC:1062-1063)
func _chiwave_caster_back(actor_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	# 等击飞顶点+下落片刻再回 (1:1 PoC:1059 sleep 560)
	await get_tree().create_timer(0.56).timeout
	# caster 走回原排 (300ms cubic.inOut) + 镜头拉回 (1:1 ts:1064-1065 zoom→1 pan→屏心 320ms) 并发
	_camera_reset(0.32)
	var tw := create_tween()
	tw.tween_property(c_node, "position", c_home, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	c_node.z_index = int(c_home.y)


## 气波 sprite 横向飞贯穿目标列 (1:1 PoC:1017-1042 — 起于胸口, 匀速 linear, 1500ms travel)
func _chiwave_wave_vfx(actor_idx: int, target_idx: int, _caster_home_y: float) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var t_node: Node2D = slot_nodes[target_idx]
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var path := "res://assets/sprites/vfx/basic-chiwave.png"
	if not ResourceLoader.exists(path):
		return
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var t_home_w: Vector2 = t_node.get_meta("home_pos", t_node.position)
	var row_y: float = t_home_w.y
	var start_x: float = c_home.x + dir * 36.0   # PoC startX = cHomeX + dir×36
	# 终点锚到目标列【后排槽】固定坐标 + dir×70 (1:1 PoC slotCoords back-{col}; 波速恒定, 不随前后排/死活变).
	#   原用主目标 home.x → 主目标在前排时波停在前排, 扫不到后排 = 弹道偏短.
	var target_w: Dictionary = fighters[target_idx]
	var tcol_w := str(target_w.get("_slotKey", "front-1")).split("-")[-1]
	var back_x: float = _slot_to_coords("back-%s" % tcol_w, target_w.get("side", "right")).x
	var end_x: float = back_x + dir * 70.0
	var tex: Texture2D = load(path)
	var fw: int = tex.get_height()
	if fw <= 0:
		return
	var n: int = maxi(1, int(tex.get_width() / fw))
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.hframes = n
	spr.frame = 0
	# PoC 256×256 显示尺寸: 缩放 = 256/帧高
	var disp_scale := 256.0 / float(fw)
	spr.scale = Vector2(disp_scale * dir, disp_scale)   # 右队 flipX → dir<0 镜像
	spr.position = Vector2(start_x, row_y - 15.0)        # 起于胸口 (row_y - 15)
	spr.z_index = 600   # 波显在龟身之上 (Godot龟z=int(home.y)最深497, PoC固定depth50不适用→z40被全龟遮死=用户报"在角色层之下"; 对齐其它VFX≥600)
	slots_root.add_child(spr)
	var travel := 1.5   # PoC WAVE_DURATION_MS 1500
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position:x", end_x, travel)   # 匀速 linear
	tw.tween_method(func(fv: float): spr.frame = mini(n - 1, int(fv)), 0.0, float(n), travel)   # 帧动画播【一次】(从头到尾, 1:1 PoC wave.play); 原 %n 跑到 n×6 = 整段循环6遍(用户报"一直循环")
	tw.chain().tween_property(spr, "modulate:a", 0.0, 0.13)   # 末帧淡出
	tw.chain().tween_callback(spr.queue_free)


## 同列敌方目标 slot 索引 (主目标 + 同 col 存活敌方) — 1:1 PoC sameColumnFighters
func _chiwave_column_idxs(actor_idx: int, target_idx: int) -> Array:
	var actor: Dictionary = fighters[actor_idx]
	var target: Dictionary = fighters[target_idx]
	var tcol := str(target.get("_slotKey", "front-1")).split("-")[-1]
	var out: Array = []
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("alive", false):
			continue
		if f.get("side", "") == actor.get("side", ""):
			continue
		if str(f.get("_slotKey", "")).split("-")[-1] == tcol:
			out.append(i)
	if out.is_empty():
		out.append(target_idx)
	return out


# ── 过肩摔 choreography (1:1 skill-handlers.ts basicSlam) ──
## caster dash 到 target 旁 (gap 58px), 蓄力后撤→爆发冲刺. 返回时=抓取帧 (PoC:1105-1117 + sleep 360)
func _slam_caster_dash(actor_idx: int, target_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var t_node: Node2D = slot_nodes[target_idx]
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var t_home: Vector2 = t_node.get_meta("home_pos", t_node.position)
	var grab_x := t_home.x - dir * 58.0
	c_node.z_index = 50
	var tw := create_tween()
	tw.tween_property(c_node, "position", Vector2(c_home.x - dir * 12.0, c_home.y + 2.0), 0.13) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)           # 蓄力后撤 (PoC 130ms)
	tw.tween_property(c_node, "position", Vector2(grab_x, t_home.y), 0.23) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)          # 爆发冲刺 (PoC 230ms)
	await tw.finished
	# 抓取帧 flash (PoC:1119-1125 双方白闪 + sleep 120)
	_flash_hit(actor_idx)
	_flash_hit(target_idx)
	await get_tree().create_timer(0.12).timeout
	# 抛掷 target 飞向敌方阵中心 560ms 重力弧, 落地 = 命中帧: windup 返回后 execute 在【落地瞬间】结算伤害,
	#   与砸地特效/震屏同帧 (1:1 PoC await sleep(throwMs) 后才 dealPhysical). 原抛掷在 post-impact、伤害却在
	#   抓取时(windup结束)就冒 → 数字在抓取处冒出、砸地无数字, 早 560ms (用户F5复查抓到).
	_slam_caster_return(actor_idx, c_home)   # caster 驻留→冲回 (并行, 从抓取时刻起算)
	var land: Vector2 = _formation_center(actor.get("side", "left"))
	t_node.set_meta("_ground_shadow", true)   # 抛投+砸地+趴起期 target 影子留地 (1:1 PoC; _slam_throw 末尾清)
	t_node.rotation = 0.0
	var tw_throw := create_tween()
	tw_throw.tween_method(
		func(p: float):
			if not is_instance_valid(t_node):
				return
			var base := t_home.lerp(land, p)
			var arc := -135.0 * 4.0 * p * (1.0 - p)   # PoC peakAir 重力弧
			t_node.position = Vector2(base.x, base.y + arc)
			t_node.rotation = deg_to_rad(dir * 360.0 * p),
		0.0, 1.0, 0.56)
	await tw_throw.finished   # 落地 → windup 返回 → execute 应用伤害(与砸地同帧)


## target 落地砸 → 趴 → 起身走回 (抛掷已在 windup 完成, 落地=命中帧)。
##   1:1 PoC:1126-1183 (throw 560ms 重力弧 + 摔趴120 + 趴停320 + 起身220 + 走回400)
func _slam_throw(actor_idx: int, target_idx: int) -> void:
	var t_node: Node2D = slot_nodes[target_idx]
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var t_home: Vector2 = t_node.get_meta("home_pos", t_node.position)
	var land: Vector2 = _formation_center(actor.get("side", "left"))   # 敌方阵型中心
	var prone_angle := deg_to_rad(78.0 * dir)
	# target 已在 windup 抛掷落到 land (落地=命中帧, 伤害与此同帧结算). post 段: 砸地特效 + 摔趴起身走回.
	# Phase 5: 砸地特效 + 震屏 (1:1 PoC:1161-1170, 与落地伤害同帧)
	_play_vfx("basic-slam-impact", land, 2.0)   # 蘑菇云 ×2
	_play_screen_shake(VisualConstants.SHAKE_CRIT_DURATION, VisualConstants.SHAKE_CRIT_STRENGTH)
	# Phase: 落地摔趴 (120) → 趴停 (320) → 起身 (220) → 走回原位 (400) — 1:1 PoC:1147-1151
	var tw2 := create_tween()
	tw2.tween_property(t_node, "rotation", prone_angle, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.parallel().tween_property(t_node, "position:y", land.y + 5.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.tween_interval(0.32)                                                # 趴停
	tw2.tween_property(t_node, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 起身
	tw2.parallel().tween_property(t_node, "position:y", land.y, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(t_node, "position", t_home, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)   # 走回原位
	await tw2.finished
	if is_instance_valid(t_node):
		t_node.position = t_home
		t_node.rotation = 0.0
	_unground_shadow(t_node)


## caster 抓取后驻留 → 冲回落定 (1:1 PoC:1110-1114 hold 1030 + 冲回 300 + 落定 90)
func _slam_caster_return(actor_idx: int, c_home: Vector2) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var tw := create_tween()
	tw.tween_interval(1.03)   # 抓取+抛掷+落地后驻留
	tw.tween_property(c_node, "position", Vector2(c_home.x, c_home.y - 3.0), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c_node, "position:y", c_home.y, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	if is_instance_valid(c_node):
		c_node.z_index = int(c_home.y)


## 敌方阵型几何中心 (target 那侧的存活敌方 slot home 平均) — 1:1 PoC formationCenter
func _formation_center(caster_side: String) -> Vector2:
	var sum := Vector2.ZERO
	var cnt := 0
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("side", "") == caster_side:
			continue
		if i >= slot_nodes.size():
			continue
		sum += slot_nodes[i].get_meta("home_pos", Vector2.ZERO)
		cnt += 1
	if cnt == 0:
		return Vector2(640, 360)
	return sum / float(cnt)


# ── 龟盾 caster 演出: chop 旋转 + 金弧 + 爆裂 (1:1 skill-handlers.ts:678-719) ──
func _shield_bash_caster_chop(actor_idx: int, target_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	# 1) chop 4段链 440ms (旋转+Y bob), fire-and-forget (1:1 ts:681-689)
	# 原地 chop 旋转/抬起 → 影子接地不跟着转/抬 (1:1 PoC: 转的是 sprite, 影子是独立物体只跟 x)
	c_node.set_meta("_ground_shadow", true)
	var ctw := c_node.create_tween()
	ctw.tween_property(c_node, "position:y", c_home.y - 2.0, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ctw.parallel().tween_property(c_node, "rotation", -0.07 * dir, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ctw.tween_property(c_node, "position:y", c_home.y + 3.0, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	ctw.parallel().tween_property(c_node, "rotation", 0.10 * dir, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	ctw.tween_property(c_node, "position:y", c_home.y + 1.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ctw.parallel().tween_property(c_node, "rotation", 0.05 * dir, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ctw.tween_property(c_node, "position:y", c_home.y, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ctw.parallel().tween_property(c_node, "rotation", 0.0, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ctw.tween_callback(_unground_shadow.bind(c_node))   # chop 结束撤接地标记 + 影子归位
	# 2) 180ms → 金弧 (target body center, ±50 朝攻击者侧, 抬20, 208px disp, 攻击者右则翻转) (ts:695-705)
	await get_tree().create_timer(0.18).timeout
	_shieldbash_vfx(target_idx, "basic-shieldbash-arc", 208.0, -50.0 * dir, -20.0, dir < 0.0)
	# 3) 再 250ms → 爆裂 (±28, 187px disp) — 命中帧, 之后主流程 execute 结算 (ts:710-718)
	await get_tree().create_timer(0.25).timeout
	_shieldbash_vfx(target_idx, "basic-shieldbash-impact", 187.0, -28.0 * dir, 0.0, false)


## 龟盾 VFX: 在 target body center ± 偏移播 sprite, scale = 目标显示px / 原生帧高
func _shieldbash_vfx(target_idx: int, vfx: String, disp: float, off_x: float, off_y: float, flip: bool) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var avatar: Sprite2D = node.get_meta("avatar", null)
	var home: Vector2 = node.get_meta("home_pos", node.position)
	var center: Vector2 = home + (avatar.position if avatar != null else Vector2(0, -50))
	var path := "res://assets/sprites/vfx/%s.png" % vfx
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	var scl: float = disp / maxf(1.0, float(tex.get_height()))
	_play_vfx(vfx, center + Vector2(off_x, off_y), scl, -1.0, flip)


# ── 龟盾 choreography (1:1 skill-handlers.ts turtleShieldBash:739-760) ──
## target 14 段击飞 (1400ms): 起飞上+后 → 落地砸 → 倒地 prone → 起身 → 走回 home。
func _shield_bash_knockup(target_idx: int) -> void:
	var actor_side := "left"   # knockDir 由攻击者侧决定; 用 target 对面推断
	var target: Dictionary = fighters[target_idx]
	actor_side = "right" if target.get("side", "") == "left" else "left"
	var knock_dir: float = 1.0 if actor_side == "left" else -1.0
	var t_node: Node2D = slot_nodes[target_idx]
	t_node.set_meta("_ground_shadow", true)   # 击飞期影子留地
	var th: Vector2 = t_node.get_meta("home_pos", t_node.position)
	var prone := deg_to_rad(90.0 * knock_dir)
	# 14 段 chain — x/y/rotation 全 1:1 PoC basic.js:739-758 keyframes
	var tw := create_tween()
	# Phase 1: 起飞上+后
	tw.tween_property(t_node, "position", Vector2(th.x + 14.0 * knock_dir, th.y - 28.0), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t_node, "rotation", 0.35 * knock_dir, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)   # PoC rot 与 position 同 keyframe ease cubic.out
	tw.tween_property(t_node, "position", Vector2(th.x + 30.0 * knock_dir, th.y - 42.0), 0.168).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(t_node, "rotation", 0.87 * knock_dir, 0.168).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)   # PoC cubic.in
	tw.tween_property(t_node, "position", Vector2(th.x + 42.0 * knock_dir, th.y - 6.0), 0.154).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(t_node, "rotation", 1.40 * knock_dir, 0.154).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)   # PoC cubic.in
	# Phase 2: 落地砸 / bounce / hold prone
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y + 8.0), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t_node, "rotation", prone, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)   # PoC Sine.easeOut
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y + 2.0), 0.056).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y + 5.0), 0.182).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Phase 3: 起身
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y), 0.126).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t_node, "rotation", prone * 0.4, 0.126).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)   # PoC Sine.easeOut
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y - 2.0), 0.084).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(t_node, "rotation", 0.0, 0.084).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Phase 4: 走回 home (PoC sine.inOut — 原漏成默认linear, 走回不够顺)
	tw.tween_property(t_node, "position", Vector2(th.x + 30.0 * knock_dir, th.y - 3.0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(t_node, "position", Vector2(th.x + 18.0 * knock_dir, th.y), 0.112).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(t_node, "position", Vector2(th.x + 8.0 * knock_dir, th.y - 2.0), 0.098).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(t_node, "position", th, 0.07)
	tw.parallel().tween_property(t_node, "rotation", 0.0, 0.07)
	await tw.finished
	if is_instance_valid(t_node):
		t_node.position = th
		t_node.rotation = 0.0
	_unground_shadow(t_node)


# ════════════════════════════════════════════════════════════════════
#  第 2 批 6 龟技能演出 (1:1 PoC): 石头/竹叶/天使/寒冰/忍者/幽灵
#    忍者 dash/backstab/bomb/shuriken; 幽灵 phantom juggle/phase overlay。
#    伤害逻辑由 SkillHandlers.execute 算, 此处仅叠加视觉演出。
# ════════════════════════════════════════════════════════════════════

## ── 原语: 在 caster 身上播一次性 action-sheet 序列 (64² 横向单行帧, NEAREST) ──
##   PoC playFighterSpriteOnce: dash.png/backstab.png/phase.png 18/18/13 帧盖在角色身上。
##   Godot 单 avatar Sprite2D 的 idle hframes 与之冲突 → 改用跟随 caster 的覆盖 Sprite2D (播完销毁)。
##   返回该 overlay 节点供调用方驱动跟随 (dash 中跟 caster 位移)。
# ACTION_PETS 通用物理普攻挥击动作帧 (1:1 PoC playAction(actor,'attack') 12fps, BootScene.ts:381-395)。
#   仅这 4 只有 attack sheet (帧尺寸各异: basic120 / ghost64 / ninja throw64 / golem74); 其余龟无 → no-op
#   (PoC 也只这 4 只播动作帧, 其余龟普攻沿用 idle 帧 hop)。
const _ACTION_ATTACK := {
	"basic": ["pets/animations/basic/attack.png", 120],
	"ghost": ["pets/animations/ghost/attack.png", 64],
	"ninja": ["pets/animations/ninja/throw.png", 64],
	"treasure_golem": ["pets/animations/treasure_golem/attack.png", 74],
}
func _play_attack_action(actor_idx: int) -> void:
	var aid: String = str(fighters[actor_idx].get("id", ""))
	if _ACTION_ATTACK.has(aid):
		var spec: Array = _ACTION_ATTACK[aid]
		_play_action_sheet_overlay(actor_idx, str(spec[0]), int(spec[1]), 12.0)   # overlay 自管销毁/缺资源 no-op


## 施法"出招" tell (1:1 PoC playAction('attack') / playFallbackAction, BattleScene.ts:3787-3890):
##   有攻击帧的龟(basic/ghost/ninja/golem) → 播攻击序列帧; 其余无帧的龟 → glow(稀有度)+scale 脉冲 1.08 150ms。
##   修: 远程/魔法/AOE 技能施法龟原本全程 idle 不反应 (Godot 只近战分支调过 _play_attack_action)。
##   脉冲不动位移(让给 hop), 始终回 home_scale (PoC 同款防累积变形)。
func _play_cast_tell(actor_idx: int) -> void:
	if actor_idx < 0 or actor_idx >= slot_nodes.size():
		return
	var f: Dictionary = fighters[actor_idx]
	if _ACTION_ATTACK.has(str(f.get("id", ""))):
		_play_attack_action(actor_idx)
		return
	var avatar: Sprite2D = slot_nodes[actor_idx].get_meta("avatar", null)
	if avatar == null:
		return
	var home_scale: Vector2 = avatar.get_meta("home_scale", avatar.scale)
	# 稀有度 glow: SSS 金 / SS 银 (1:1 PoC glowTint ts:3873); 其余无 glow
	var rarity: String = str(f.get("rarity", ""))
	var glow := Color(0, 0, 0, 0)
	if rarity == "SSS":
		glow = Color(1.0, 0.843, 0.0)
	elif rarity == "SS":
		glow = Color(0.878, 0.878, 0.878)
	if avatar.has_meta("tell_tw"):
		var old = avatar.get_meta("tell_tw")
		if old is Tween and old.is_valid():
			old.kill()
	avatar.scale = home_scale   # 始终从 home 起跳 (不读当前值, 防累积)
	if glow.a > 0.0:
		avatar.modulate = Color(glow.r, glow.g, glow.b, avatar.modulate.a)
	var tw := avatar.create_tween()
	avatar.set_meta("tell_tw", tw)
	# 1:1 PoC playFallbackAction: duration:150 + yoyo → 150ms 去 + 150ms 回 = 300ms 全程 (Phaser yoyo 倍时)
	tw.tween_property(avatar, "scale", home_scale * 1.08, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(avatar, "scale", home_scale, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(avatar):
			avatar.scale = home_scale
			if glow.a > 0.0:
				avatar.modulate = Color(1, 1, 1, avatar.modulate.a))


func _play_action_sheet_overlay(actor_idx: int, sheet_rel: String, frame_size: int, fps: float) -> Sprite2D:
	var node: Node2D = slot_nodes[actor_idx]
	var avatar: Sprite2D = node.get_meta("avatar")
	var path := "res://assets/sprites/%s" % sheet_rel
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var n: int = maxi(1, int(tex.get_width() / frame_size))
	var ov := Sprite2D.new()
	ov.texture = tex
	ov.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ov.hframes = n
	ov.frame = 0
	# 与 avatar 等高缩放 + 同朝向 (right 队镜像) + 同锚 (脚底抬 half)
	# 目标显示高 = avatar 当前显示高 (avatar.scale.y × avatar 单帧原生高), 与 overlay 原生帧尺寸无关。
	#   dash/phase 等 overlay 帧=avatar 原生 64 时与旧式等价; basic attack 120px≠idle 64px 时才修正(不放大 1.875×)。
	var avatar_h: float = float(avatar.texture.get_height()) if (avatar and avatar.texture) else float(frame_size)
	var box: float = (avatar.scale.y * avatar_h) if avatar else float(frame_size)
	var sf: float = box / float(frame_size)
	var dir_sign: float = signf(avatar.scale.x) if avatar else 1.0
	ov.scale = Vector2(sf * dir_sign, sf)
	ov.position = avatar.position if avatar else Vector2.ZERO
	ov.z_index = 5
	if avatar:
		# 引用计数: 同一龟若叠多个 action overlay, 只有"最后一个"播完才还原 idle, 否则早结束的会
		#   提前把 idle 显出来透在后一个动作精灵后面 (视觉回归三问之②重叠)。
		node.set_meta("action_ov_count", int(node.get_meta("action_ov_count", 0)) + 1)
		avatar.modulate.a = 0.0   # 隐藏 idle, 让 action 序列接管 (最后一个播完还原)
	node.add_child(ov)
	var dur: float = float(n) / fps
	var tw := ov.create_tween()
	tw.tween_method(func(v: float): ov.frame = mini(n - 1, int(v)), 0.0, float(n), dur)
	tw.tween_callback(func():
		if is_instance_valid(node):
			var c: int = int(node.get_meta("action_ov_count", 1)) - 1
			node.set_meta("action_ov_count", maxi(0, c))
			if c <= 0 and is_instance_valid(avatar):
				avatar.modulate.a = 1.0
		ov.queue_free())
	return ov


## ── 忍者冲击 dash (ninja.js:155-374): 跑到目标排 → 蓄力 → dash 穿过目标列后排 (+60px). ──
##   caster 停在 dash 终点 (post 段 snap home)。dash.png 18帧序列 + dash-trail VFX 跟随。
func _ninja_impact_dash(actor_idx: int, target_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var actor: Dictionary = fighters[actor_idx]
	var target: Dictionary = fighters[target_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var t_home: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
	c_node.z_index = 60
	# Phase 0: 跑到目标横排 Y (400ms linear, PoC RUN_MS)
	if absf(t_home.y - c_home.y) > 4.0:
		var tw0 := create_tween()
		tw0.tween_property(c_node, "position:y", t_home.y, 0.4)
		await tw0.finished
	# dash.png 18帧序列盖在 caster 身上 (PoC ninja.js:262; overlay 自管销毁)
	# PoC BootScene:416 frameRate=10 → 18帧/10fps=1800ms 盖满全程 (非18fps)
	_play_action_sheet_overlay(actor_idx, "pets/animations/ninja/dash.png", 64, 10.0)
	# Phase 1: 蓄力 300ms (PoC F1-3 windup)
	await get_tree().create_timer(0.3).timeout
	# dash 终点 X = 目标列后排槽 + dir×60 (PoC slotCoords back-<col> + 60)
	var tcol := str(target.get("_slotKey", "front-1")).split("-")[-1]
	var back_x: float = _slot_to_coords("back-%s" % tcol, target.get("side", "right")).x
	var dash_x: float = back_x + dir * 60.0
	# dash-trail VFX 跟随 (4帧循环), 与 sprite 同步
	var trail := _spawn_follow_vfx("ninja-dash-trail", c_node, dir)
	# Phase 2: 飞行 500ms cubic.out — caster x → dash_x. 命中在【飞行中段】= caster 经过目标 X 的瞬间
	#   (1:1 PoC triggerMs=max(40, 500×|hitX|/|dashX|); 原 await 整段=命中在飞行末, 晚 ~50-150ms).
	var pass_frac: float = clampf(absf(t_home.x - c_home.x) / maxf(1.0, absf(dash_x - c_home.x)), 0.0, 1.0)
	var trigger_s: float = maxf(0.04, 0.5 * pass_frac)
	var tw2 := create_tween()
	tw2.tween_property(c_node, "position:x", dash_x, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c_node.set_meta("_ninja_flight_tw", tw2)   # post-impact 等冲刺飞完(到 dash_x)再归位, 防与归位 tween 抢位
	await get_tree().create_timer(trigger_s).timeout   # 经过目标X → windup 返回 → execute 在中段结算伤害
	_play_screen_shake(0.24, 8.0)   # PoC cameras.shake(240, 0.008)
	# 余下飞行播完后清 trail (fire-and-forget, 不挡伤害)
	tw2.finished.connect(func() -> void:
		if is_instance_valid(trail):
			trail.queue_free(), CONNECT_ONE_SHOT)


## ── 忍者背刺 dash (ninja.js:382-515): 蓄力300 → 闪现到目标后方 (X+dir×50). ──
##   caster 停在目标后方 (post 段停留后 snap home)。backstab.png 18帧序列盖身上。
func _ninja_backstab_dash(actor_idx: int, target_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var t_home: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
	c_node.z_index = 60
	# PoC BootScene:416 frameRate=10 → 18帧/10fps=1800ms (非18fps)
	_play_action_sheet_overlay(actor_idx, "pets/animations/ninja/backstab.png", 64, 10.0)
	# F1-3 蓄力 300ms (sprite 留 home)
	await get_tree().create_timer(0.3).timeout
	# F4 闪现到目标后方 (瞬移, PoC instant)
	c_node.position = Vector2(t_home.x + dir * 50.0, t_home.y)


## ── 忍者 caster 闪回 home + recovery (ninja.js:357-360 / 461) ──
func _ninja_caster_snap_home(actor_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	await get_tree().create_timer(0.5).timeout   # 命中后站立 500ms (PoC)
	c_node.position = c_home                       # 闪回 home (PoC teleport)
	c_node.z_index = int(c_home.y)
	await get_tree().create_timer(0.4).timeout   # recovery 400ms


## ── 忍者炸弹抛投 (ninja.js:523-619): bomb sprite 从 caster 抛物线飞向敌阵中心 (400ms) + 引信 400ms。 ──
##   命中帧 ≈ 引爆 800ms (PoC detonateAt). 伤害由 execute 在 windup 结束后算。
func _ninja_bomb_throw(actor_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var actor: Dictionary = fighters[actor_idx]
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var center: Vector2 = _formation_center(actor.get("side", "left"))   # 敌方阵型中心
	var path := "res://assets/sprites/vfx/ninja-bomb.png"
	if not ResourceLoader.exists(path):
		await get_tree().create_timer(0.8).timeout
		return
	var tex: Texture2D = load(path)
	var fw: int = tex.get_height()
	var n: int = maxi(1, int(tex.get_width() / fw))
	var bomb := Sprite2D.new()
	bomb.texture = tex
	bomb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bomb.hframes = n
	bomb.frame = 0
	var disp := 220.0 / float(fw)   # PoC setDisplaySize(220,220)
	bomb.scale = Vector2(disp, disp)
	bomb.position = c_home
	bomb.z_index = 600   # 忍者炸弹抛投高过龟身(最深 ~497): 原 200 被龟立绘遮死
	slots_root.add_child(bomb)
	# 抛物线 400ms (3 段弹跳 ARC_PEAK -160 / BOUNCE -55 / -22, PoC:1888-1916)
	var start := c_home
	var delta := center - c_home
	var bomb_fly := func(p: float) -> void:
		if not is_instance_valid(bomb):
			return
		var arc: float
		var sub: float
		if p < 0.5:
			sub = p / 0.5
			arc = -160.0
		elif p < 0.75:
			sub = (p - 0.5) / 0.25
			arc = -55.0
		elif p < 0.95:
			sub = (p - 0.75) / 0.20
			arc = -22.0
		else:
			sub = 1.0
			arc = 0.0
		bomb.position = Vector2(start.x + delta.x * p, start.y + delta.y * p + arc * 4.0 * sub * (1.0 - sub))
	var bomb_anim := func(fv: float) -> void:
		if is_instance_valid(bomb):
			bomb.frame = mini(n - 1, int(fv))   # 播一次(从头到尾, 1:1 PoC anim-ninja-bomb 12帧@10fps repeat:0); 原 %n×3 = 循环3遍
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(bomb_fly, 0.0, 1.0, 0.4)
	# 炸弹帧动画 (12帧 全程 1200ms 循环)
	tw.tween_method(bomb_anim, 0.0, float(n), 1.2)   # 12帧 / 1.2s 播一次 (1:1 PoC)
	# 引信 400ms (抛物线后停在中心), 共 800ms 至引爆帧
	await get_tree().create_timer(0.8).timeout
	_play_screen_shake(0.26, 12.0)   # PoC cameras.shake(260, 0.012)
	# 引爆即返回 → windup 结束, execute 在【此刻】应用 AOE 伤害+飘字 (PoC floatNum 在 sleep(800) 引爆点 delay0).
	# 余下 400ms 蘑菇云帧动画播完再销毁 = fire-and-forget, 【不再 await】(否则伤害被推迟到云淡完才出, 晚 0.4s).
	var cleanup_tw := create_tween()
	cleanup_tw.tween_interval(0.4)
	cleanup_tw.tween_callback(func() -> void:
		if is_instance_valid(bomb):
			bomb.queue_free())


## ── 忍者飞镖投掷 (ninja.js:1-60): 飞镖 sprite 从 caster 飞向 target, 280ms linear, 命中 240ms。 ──
func _ninja_shuriken_throw(actor_idx: int, target_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var t_home: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
	var path := "res://assets/sprites/vfx/ninja-shuriken.png"
	if not ResourceLoader.exists(path):
		await get_tree().create_timer(0.24).timeout
		return
	var tex: Texture2D = load(path)
	var fw: int = tex.get_height()   # 128²
	var n: int = maxi(1, int(tex.get_width() / fw))
	var shuriken := Sprite2D.new()
	shuriken.texture = tex
	shuriken.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shuriken.hframes = n
	shuriken.frame = 0
	shuriken.scale = Vector2(0.47, 0.47)   # PoC setScale(0.47) (128→60px)
	var start := Vector2(c_home.x + dir * 30.0, c_home.y - 40.0)   # 胸口高度起手 (PoC cv.y)
	var dest := Vector2(t_home.x, t_home.y - 40.0)
	shuriken.position = start
	shuriken.z_index = 600   # 忍者飞镖高过龟身(最深 ~497): 原 200 被龟立绘遮死
	slots_root.add_child(shuriken)
	var spin := func(fv: float) -> void:
		if is_instance_valid(shuriken):
			shuriken.frame = int(fv) % n
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(shuriken, "position", dest, 0.28)          # 飞行 280ms linear
	tw.tween_method(spin, 0.0, float(n * 8), 0.28)   # 旋转
	await get_tree().create_timer(0.24).timeout   # 命中 240ms (PoC damageAtMs)
	get_tree().create_timer(0.04).timeout.connect(func() -> void:
		if is_instance_valid(shuriken):
			shuriken.queue_free())


## ── 幽冥突袭击退 juggle (ghost.js:226-247): 13 段 (1400ms), 与龟盾同款 keyframes (低弧+远落+倒地+走回)。 ──
func _ghost_phantom_knockback(actor_idx: int, target_idx: int) -> void:
	var actor: Dictionary = fighters[actor_idx]
	var knock_dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var t_node: Node2D = slot_nodes[target_idx]
	t_node.set_meta("_ground_shadow", true)   # 击退期影子留地
	var th: Vector2 = t_node.get_meta("home_pos", t_node.position)
	var prone := deg_to_rad(-82.0 * knock_dir)   # PoC proneRot -82°
	var tw := create_tween()
	# 升空后仰 (PoC skill-handlers.ts:1433-1435 — rot 与 position 同 keyframe ease)
	tw.tween_property(t_node, "position", Vector2(th.x + 14.0 * knock_dir, th.y - 28.0), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t_node, "rotation", deg_to_rad(20.0 * knock_dir), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)   # PoC cubic.out
	tw.tween_property(t_node, "position", Vector2(th.x + 30.0 * knock_dir, th.y - 42.0), 0.168).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(t_node, "rotation", deg_to_rad(50.0 * knock_dir), 0.168).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)   # PoC cubic.in
	tw.tween_property(t_node, "position", Vector2(th.x + 42.0 * knock_dir, th.y - 6.0), 0.154).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(t_node, "rotation", deg_to_rad(80.0 * knock_dir), 0.154).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)   # PoC cubic.in
	# 砸地 / 弹跳 / 保持倒地
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y + 8.0), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t_node, "rotation", prone, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)   # PoC Sine.easeOut
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y + 2.0), 0.056).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y + 5.0), 0.182).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 起身
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y), 0.126).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t_node, "rotation", prone * 0.4, 0.126).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)   # PoC Sine.easeOut
	tw.tween_property(t_node, "position", Vector2(th.x + 44.0 * knock_dir, th.y - 2.0), 0.084).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(t_node, "rotation", 0.0, 0.084).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)   # PoC sine.inOut
	# 走回原位 (PoC ts:1444-1446 sine.inOut)
	tw.tween_property(t_node, "position", Vector2(th.x + 30.0 * knock_dir, th.y - 3.0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(t_node, "position", Vector2(th.x + 18.0 * knock_dir, th.y), 0.112).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(t_node, "position", Vector2(th.x + 8.0 * knock_dir, th.y - 2.0), 0.098).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(t_node, "position", th, 0.07)
	tw.parallel().tween_property(t_node, "rotation", 0.0, 0.07)
	await tw.finished
	if is_instance_valid(t_node):
		t_node.position = th
		t_node.rotation = 0.0
	_unground_shadow(t_node)


## ── 跟随节点的循环 VFX (ninja dash-trail): 方形帧条, 跟 follow_node, 返回供调用方销毁 ──
func _spawn_follow_vfx(vfx_name: String, follow_node: Node2D, dir: float) -> Sprite2D:
	var path := "res://assets/sprites/vfx/%s.png" % vfx_name
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var fw: int = tex.get_height()
	if fw <= 0:
		return null
	var n: int = maxi(1, int(tex.get_width() / fw))
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.hframes = n
	spr.frame = 0
	var disp := 128.0 / float(fw)   # PoC setDisplaySize(128,128)
	spr.scale = Vector2(disp * signf(dir), disp)
	spr.position = follow_node.global_position
	spr.z_index = 180
	follow_node.add_child(spr)
	spr.position = Vector2(0, -40.0)   # 胸口高度跟随
	var anim := func(fv: float) -> void:
		if is_instance_valid(spr):
			spr.frame = int(fv) % n
	var tw := spr.create_tween().set_loops()
	tw.tween_method(anim, 0.0, float(n), 0.2)   # PoC 4帧200ms循环
	return spr


# ════════════════════════════════════════════════════════════════════
#  第 3 批 6 龟技能演出 (1:1 PoC): 凤凰/熔岩/赛博(机甲)/水晶/星际(星能)/彩虹
#    多数技能=远程魔法/自施/AOE → 25px attack-hop (已入 _RANGED_SKILLS)。
#    本块只处理特殊编排: cyberBeam KOF / star knockup / 黑洞旋涡。镜头 zoom 留后。
#    伤害逻辑由 SkillHandlers.execute 算, 此处仅叠加视觉演出。
# ════════════════════════════════════════════════════════════════════

## 全敌方 slot 索引 (存活, 对侧) — starGravityWarp 全体击飞用 (1:1 PoC getEnemies)
func _all_enemy_idxs(actor_idx: int) -> Array:
	var actor: Dictionary = fighters[actor_idx]
	var out: Array = []
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("alive", false) and f.get("side", "") != actor.get("side", ""):
			out.append(i)
	return out


## ── 原语: knockup 小跳 (1:1 PoC playFallbackAction 'knockup', BattleScene.ts:3906-3916) ──
##   上跳 40px + 旋转 0.4rad (180ms power2.out) → 落回 + 转正 (220ms bounce.out)。共 400ms。
func _knockup_hop(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size():
		return
	var node: Node2D = slot_nodes[target_idx]
	node.set_meta("_ground_shadow", true)   # 击飞期影子留地 (1:1 PoC 只动 sprite)
	var home: Vector2 = node.get_meta("home_pos", node.position)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "position:y", home.y - 40.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "rotation", 0.4, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(node, "position:y", home.y, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await tw.finished
	if is_instance_valid(node):
		node.position.y = home.y
		node.rotation = 0.0
	_unground_shadow(node)


## ── 能量大炮 KOF windup (cyber.js:92-334 / skill-handlers.ts:3187-3230) ──
##   1) 全屏青色 cut-in flash 500ms + 中心 orb 扩散  2) caster Y-hop 抛物到目标横排 (460ms)  3) 蓄力 tint 550ms
func _cyber_beam_windup(actor_idx: int, target_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var t_node: Node2D = slot_nodes[target_idx]
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var t_home: Vector2 = t_node.get_meta("home_pos", t_node.position)
	var avatar: Sprite2D = c_node.get_meta("avatar")
	# ── 1) KOF cut-in: 全屏青闪 (0x4cc9f0, a=0.45→0, 500ms cubic.out) ──
	#   在 fx_layer (CanvasLayer) 而非 slots_root → 不随相机 zoom/pan, 永盖满屏。
	if is_instance_valid(fx_layer):
		var cutin := ColorRect.new()
		cutin.color = Color(0x4c / 255.0, 0xc9 / 255.0, 0xf0 / 255.0, 0.45)
		cutin.size = get_viewport().get_visible_rect().size   # 盖满真实视口 (ENVELOP)
		cutin.position = Vector2.ZERO
		cutin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx_layer.add_child(cutin)
		var tw_c := cutin.create_tween()
		tw_c.tween_property(cutin, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_c.tween_callback(cutin.queue_free)
	# 中心 orb (青白色圆, 扩散淡出) — 简化省略 (光闪已足够提示)。
	await get_tree().create_timer(0.5).timeout
	# ── 2) 镜头 pan 到横排中点 + zoom 1.2× (1:1 ts:3204-3208: midX/midY pan + zoomTo 1.2 400ms easeOut) ──
	#   PoC cyberBeam 用 center 模式 (cam.pan(midX,midY)) — 焦点移到画面中心, 非 chiwave 的 origin 原地放大。
	var mid := Vector2((c_home.x + t_home.x) / 2.0, t_home.y)
	_camera_focus(mid, 1.2, 0.4, "center", Tween.EASE_OUT)
	# ── 3) caster Y-hop 抛物到目标横排 (460ms Sine.easeInOut; apexLift = -min(44, 24+|yShift|×0.28)) ──
	var y_shift: float = t_home.y - c_home.y
	var apex_lift: float = -minf(44.0, 24.0 + absf(y_shift) * 0.28)
	c_node.z_index = 50
	var hop_ms := 0.46
	var tw_h := create_tween()
	tw_h.tween_method(
		func(p: float) -> void:
			if not is_instance_valid(c_node):
				return
			c_node.position.y = c_home.y + y_shift * p + apex_lift * 4.0 * p * (1.0 - p),
		0.0, 1.0, hop_ms).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.48).timeout   # PoC sleep(480)
	# ── 3) 蓄力 windup: avatar tint 青色脉冲 550ms (PoC setTint(0x9af6ff) → clearTint) ──
	#   恢复保留当前 alpha(别强制1.0, 否则若期间被 action overlay 隐藏 a=0 会强行显形); guard 释放。
	if is_instance_valid(avatar):
		avatar.modulate = Color(0x9a / 255.0, 0xf6 / 255.0, 1.0, avatar.modulate.a)
	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(avatar):
		avatar.modulate = Color(1, 1, 1, avatar.modulate.a)
	# ── 5) 发射 beam-sweep: 从 caster 胸口朝敌方向贯穿到画面边缘 (1:1 skill-handlers.ts:3232-3261) ──
	_play_cyber_beam_sweep(actor_idx, target_idx)
	# 激光横扫 360ms 到峰值【再】结算伤害 (1:1 PoC ts:3276 await sleep(360) 在 cam.shake+双段伤害前).
	# 原 windup 发射后立即返回 = 敌人在激光还没扫到时就被击飞+掉血, 视觉与数值脱节(ninjaBomb同类).
	await get_tree().create_timer(0.36).timeout


## 能量大炮 beam-sweep: 从 caster 朝敌方向拉伸贯穿到屏边的全屏光束 (1:1 skill-handlers.ts:3232-3261)。
##   PoC: 锚在施法者侧 origin(dir==1?0:1, 0.5), displayWidth=beamLen(到屏边), displayHeight=150,
##        6帧@8.333fps(720ms 横扫), 入场 scaleX 0→1 120ms cubic.out, 360ms 后 alpha→0 360ms 销毁, depth 48。
func _play_cyber_beam_sweep(actor_idx: int, target_idx: int) -> void:
	var path := "res://assets/sprites/vfx/cyber-beam-sweep.png"
	if not ResourceLoader.exists(path):
		return
	var c_node: Node2D = slot_nodes[actor_idx]
	var t_node: Node2D = slot_nodes[target_idx]
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	# fCx = caster sprite x (windup 期间只动 y, x 仍在 home.x); beamY = 目标行中心 (PoC beamY = tv.y, ts:3243)。
	var f_cx: float = c_node.position.x
	var t_avatar: Sprite2D = t_node.get_meta("avatar", null)
	var center_off: float = t_avatar.position.y if t_avatar != null else -51.0   # sprite 中心抬 SPRITE_HALF
	var beam_y: float = t_node.position.y + center_off
	# farEdgeX = dir==1 ? sceneW : 0 (ts:3237); beamLen = max(120, |farEdgeX - fCx|) (ts:3244)
	var far_edge_x: float = float(VIEW_W) if dir == 1.0 else 0.0
	var beam_len: float = maxf(120.0, absf(far_edge_x - f_cx))
	var tex: Texture2D = load(path)
	var fw: int = tex.get_height()           # 方形帧 → 帧宽=高 (768×128 = 6×128)
	if fw <= 0:
		return
	var n: int = maxi(1, int(tex.get_width() / fw))   # 6 帧
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.hframes = n
	spr.frame = 0
	spr.centered = true
	# PoC: setOrigin(dir==1?0:1, 0.5) — 锚在施法者侧. Godot Sprite2D 用 centered=true + offset 模拟左/右锚。
	#   左队(dir=1): 左边缘锚 caster → offset.x = +帧宽/2 (向右拉伸); 右队: 右边缘锚 → offset.x = -帧宽/2。
	spr.offset = Vector2((fw / 2.0) * dir, 0.0)
	spr.position = Vector2(f_cx, beam_y)
	# displayWidth=beamLen / displayHeight=150 (ts:3251-3252): scale = 目标尺寸 / 帧像素尺寸
	var target_sx: float = beam_len / float(fw)
	var sy: float = 150.0 / float(fw)
	if dir == -1.0:
		spr.flip_h = true                    # PoC setFlipX(true) 右队镜像 (ts:3253)
	spr.scale = Vector2(target_sx, sy)
	spr.z_index = 600                        # 机甲横扫光束高过龟身(最深 ~497): 原 200 被遮 (PoC depth 48 在角色之上)
	slots_root.add_child(spr)
	# 6 帧 @ 8.333fps = 720ms 横扫 (PoC anim-cyber-beam-sweep, VFX_FPS["cyber-beam-sweep"]=8.333)
	var tw_f := spr.create_tween()
	tw_f.tween_method(func(fv: float): spr.frame = mini(n - 1, int(fv)), 0.0, float(n), float(n) / 8.333)
	# 入场: scaleX 0→target 120ms cubic.out (ts:3256-3258)
	spr.scale.x = 0.0
	var tw_in := spr.create_tween()
	tw_in.tween_property(spr, "scale:x", target_sx, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 360ms 后 alpha→0 360ms 销毁 (ts:3259-3261)
	var tw_out := spr.create_tween()
	tw_out.tween_interval(0.36)
	tw_out.tween_property(spr, "modulate:a", 0.0, 0.36)
	tw_out.tween_callback(spr.queue_free)


## 海浪 e_wave 横扫 VFX (1:1 PoC launchWaveSweep vfx/skills.ts:324):
##   wave-sweep.png 显示220×110, x 从 -120 扫到 1400(=1280基宽+120), 2000ms linear, 行 y 高度,
##   alpha 入0→.9(300ms) hold →0(末400ms). 加 slots_root 世界层(随相机, 同 cyber-beam-sweep). 层级/行y精度需F5.
# 海浪横扫 x 行程常量 (与 _play_wave_sweep 的 x tween 同步): 起 -120 → 终 1400, 线性 2.0s.
const WAVE_SWEEP_START_X := -120.0
const WAVE_SWEEP_END_X := 1400.0
const WAVE_SWEEP_DUR := 2.0
# 龙蛋 024 火柱横扫 (_play_fire_sweep) x tween 时长: 从携带者扫向该列敌, 0.6s Cubic.easeOut.
#   各列目标(友/敌)按其 x 沿扫向错峰显伤/盾/魔法 (火接触才掉血), 同海浪思路 (复用 wave_arrival_delay_at).
const FIRE_SWEEP_DUR := 0.6

func _play_wave_sweep(row_y: float) -> void:
	var tex_path := "res://assets/sprites/vfx/wave-sweep.png"
	if not ResourceLoader.exists(tex_path):
		return
	var tex: Texture2D = load(tex_path)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2(220.0 / maxf(1.0, float(tex.get_width())), 110.0 / maxf(1.0, float(tex.get_height())))   # PoC setDisplaySize 220×110
	spr.position = Vector2(WAVE_SWEEP_START_X, row_y)
	spr.modulate.a = 0.0
	spr.z_index = 600                       # 海浪横扫高过龟身(最深 ~497): 原 100 被遮 (PoC depth 45 在角色之上)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	slots_root.add_child(spr)
	var tw := spr.create_tween()            # x 横扫 2000ms (PoC startX-120 → endX sceneW+120)
	tw.tween_property(spr, "position:x", WAVE_SWEEP_END_X, WAVE_SWEEP_DUR).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(spr.queue_free)
	var atw := spr.create_tween()           # alpha 入→hold→出 (并行)
	atw.tween_property(spr, "modulate:a", 0.9, 0.3)
	atw.tween_interval(1.3)
	atw.tween_property(spr, "modulate:a", 0.0, 0.4)


# 海浪波头扫到某目标的【到达时刻】(s): 波头中心从 START_X 线性扫到 END_X, 在目标 home_pos.x 处的时间分量.
#   用于海浪 043 各目标 effect 错峰显示 (波接触才掉血/盾/魔法), 与投射 arrival_delay 同思路. 纯显示时机, 数值不动.
func _wave_arrival_delay(target_idx: int) -> float:
	if target_idx < 0 or target_idx >= slot_nodes.size():
		return 0.0
	var tx: float = float(slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position).x)
	return wave_arrival_delay_at(tx, WAVE_SWEEP_START_X, WAVE_SWEEP_END_X, WAVE_SWEEP_DUR)


# 纯函数 (可单测): 波头从 start_x 线性扫到 end_x 用时 dur, 扫到 target_x 处的墙钟到达时刻 (clamp 到 [0,dur]).
static func wave_arrival_delay_at(target_x: float, start_x: float, end_x: float, dur: float) -> float:
	var span: float = end_x - start_x
	if absf(span) < 1.0:
		return 0.0
	var frac: float = clampf((target_x - start_x) / span, 0.0, 1.0)
	return frac * dur


## 能量大炮: 横排敌人 2 段击飞 juggle (1:1 skill-handlers.ts:3287-3303, knockX = dir×50, ~860ms)
func _cyber_beam_juggle(actor_idx: int, enemy_idx: int) -> void:
	if enemy_idx < 0 or enemy_idx >= slot_nodes.size():
		return
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var node: Node2D = slot_nodes[enemy_idx]
	node.set_meta("_ground_shadow", true)   # 击飞期影子留地
	var h: Vector2 = node.get_meta("home_pos", node.position)
	var knock_x: float = dir * 50.0
	var tw := create_tween()
	# 第1击 抛起 (180ms cubic.out)
	tw.tween_property(node, "position", Vector2(h.x + knock_x * 0.6, h.y - 40.0), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "rotation", 0.3 * dir, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)   # PoC rot 同 keyframe cubic.out
	tw.tween_interval(0.10)                                                       # 短停
	# 第2击 再抛 (180ms cubic.out)
	tw.tween_property(node, "position", Vector2(h.x + knock_x, h.y - 60.0), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "rotation", 0.6 * dir, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)   # PoC cubic.out
	tw.tween_interval(0.06)                                                       # 顶点停顿
	# 落地 (220ms cubic.in)
	tw.tween_property(node, "position", Vector2(h.x + knock_x * 1.2, h.y + 5.0), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(node, "rotation", 0.9 * dir, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)   # PoC cubic.in
	# 起身走回 home (280ms sine.inOut)
	tw.tween_property(node, "position", h, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(node, "rotation", 0.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)   # PoC sine.inOut
	await tw.finished
	if is_instance_valid(node):
		node.position = h
		node.rotation = 0.0
	_unground_shadow(node)


## 能量大炮: caster 抛回原排 (1:1 skill-handlers.ts:3342-3353, 反向抛物 460ms Sine)
func _cyber_beam_caster_back(actor_idx: int) -> void:
	var c_node: Node2D = slot_nodes[actor_idx]
	var c_home: Vector2 = c_node.get_meta("home_pos", c_node.position)
	var start_y: float = c_node.position.y
	var y_shift: float = c_home.y - start_y
	var apex_lift: float = -minf(44.0, 24.0 + absf(y_shift) * 0.28)
	# 镜头拉回 (1:1 ts:3350-3351 pan→屏心 + zoom→1, 460ms easeOut) 与 caster 抛回并发
	_camera_reset(0.46, Tween.EASE_OUT)
	var tw := create_tween()
	tw.tween_method(
		func(p: float) -> void:
			if not is_instance_valid(c_node):
				return
			c_node.position.y = start_y + y_shift * p + apex_lift * 4.0 * p * (1.0 - p),
		0.0, 1.0, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(c_node):
		c_node.position = c_home
		c_node.z_index = int(c_home.y)


## ── 黑洞旋涡 VFX (star.js:174-235 / skill-handlers.ts:4368-4397) ──
##   PoC: graphics 同心圆(0x1a0033)+旋转紫环(0xc77dff) 800ms。Godot 无现成帧→用嵌套圆+旋转 Node2D 近似。
func _play_blackhole_vfx(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size():
		return
	var pos: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
	var root := Node2D.new()
	root.position = pos
	root.z_index = 600   # 黑洞旋涡高过龟身(最深 ~497): 原 46 被龟立绘遮死
	slots_root.add_child(root)
	# 旋转紫环 (4 段弧用 4 个细长矩形近似十字, 旋转)
	var ring := Node2D.new()
	root.add_child(ring)
	for i in range(4):
		var bar := ColorRect.new()
		bar.color = Color(0xc7 / 255.0, 0x7d / 255.0, 1.0, 0.85)
		bar.size = Vector2(60, 4)
		bar.position = Vector2(-30, -2)
		bar.rotation = i * PI / 2.0
		ring.add_child(bar)
	# 中心暗圆 (同心 ColorRect 缩放近似)
	var core := ColorRect.new()
	core.color = Color(0x1a / 255.0, 0x00 / 255.0, 0x33 / 255.0, 0.7)
	core.size = Vector2(64, 64)
	core.position = Vector2(-32, -32)
	root.add_child(core)
	root.move_child(core, 0)   # core 在 ring 下
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "rotation", PI * 2.0, 0.8)                       # 旋转 800ms
	tw.tween_property(root, "scale", Vector2(1.4, 1.4), 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)  # 淡出
	tw.chain().tween_callback(root.queue_free)


# ════════════════════════════════════════════════════════════════════
#  第 4 批 6 龟技能演出原语 (1:1 PoC): 赌神/猎人/海盗/糖果/泡泡/线条
#    多数技能 = 远程/魔法/AOE/自施 → 已入 _RANGED_SKILLS 走 25px attack-hop。
#    本块仅特殊编排: 猎人飞箭投射物 / 赌神 pulse punch / 线条墨线连接。
#    伤害逻辑由 SkillHandlers.execute 算, 此处仅叠加视觉演出。
# ════════════════════════════════════════════════════════════════════

## ── 原语: 飞 hunter-arrow 投射物 (1:1 vfx/skills.ts:501 fireHunterArrow) ──
##   从 caster 胸口 (前移 30px) 飞向目标 home, 旋转朝向, 56×14 显示 (512×128 源图 4:1), linear。
##   awaitable — 跑完销毁。命中帧由调用方时序对齐。
func _fire_arrow(actor_idx: int, target_idx: int, dur: float) -> void:
	if actor_idx < 0 or actor_idx >= slot_nodes.size() or target_idx < 0 or target_idx >= slot_nodes.size():
		return
	var path := "res://assets/sprites/vfx/hunter-arrow.png"
	if not ResourceLoader.exists(path):
		return
	var actor: Dictionary = fighters[actor_idx]
	var dir: float = 1.0 if actor.get("side", "left") == "left" else -1.0
	var c_home: Vector2 = slot_nodes[actor_idx].get_meta("home_pos", slot_nodes[actor_idx].position)
	var t_home: Vector2 = slot_nodes[target_idx].get_meta("home_pos", slot_nodes[target_idx].position)
	var start: Vector2 = c_home + Vector2(dir * 30.0, -40.0)   # 胸口高度 (avatar 上抬 ~40)
	var dest: Vector2 = t_home + Vector2(0.0, -40.0)
	var tex: Texture2D = load(path)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = start
	spr.rotation = (dest - start).angle()
	# PoC setDisplaySize(56,14): 源 512×128 → scale = 56/512 ≈ 0.109 (X), 14/128 ≈ 0.109 (Y)
	spr.scale = Vector2(56.0 / float(tex.get_width()), 14.0 / float(tex.get_height()))
	spr.z_index = 600   # 猎人飞箭高过龟身(最深 ~497): 原 190 被龟立绘遮死
	slots_root.add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "position", dest, dur)   # linear
	tw.tween_callback(spr.queue_free)
	await tw.finished


## ── 原语: caster avatar pulse-scale (1:1 BattleScene.ts:2831 pulseScale yoyo Sine.easeInOut) ──
##   factor×homeScale 放大再缩回 (yoyo). 用 avatar 局部 scale, 不动 slot 站位/锚定。
## 赌注每段挥击脉冲 (fire-and-forget, 1:1 PoC ts:4744 每段 pulseScale 1.12×150ms)
func _gambler_bet_pulses(actor_idx: int, count: int, interval: float) -> void:
	for h in range(count):
		if h > 0:
			await get_tree().create_timer(interval).timeout
		if actor_idx >= 0 and actor_idx < fighters.size() and fighters[actor_idx].get("alive", false):
			_pulse_avatar(actor_idx, 1.12, 0.15)


func _pulse_avatar(actor_idx: int, factor: float, dur: float) -> void:
	if actor_idx < 0 or actor_idx >= slot_nodes.size():
		return
	var avatar: Sprite2D = slot_nodes[actor_idx].get_meta("avatar")
	if not avatar:
		return
	var home_scale: Vector2 = avatar.scale
	var tw := avatar.create_tween()
	tw.tween_property(avatar, "scale", home_scale * factor, dur * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(avatar, "scale", home_scale, dur * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 连笔第 2 目标: 存活 + 对侧 + != 主目标 的首个敌方 (1:1 skill-handlers.ts:5279 enemies.find)
func _line_second_target(actor_idx: int, target_idx: int) -> int:
	var actor: Dictionary = fighters[actor_idx]
	for i in range(fighters.size()):
		if i == target_idx:
			continue
		var f: Dictionary = fighters[i]
		if f.get("alive", false) and f.get("side", "") != actor.get("side", ""):
			return i
	return -1


## ── 墨线连接 VFX (1:1 BattleScene.ts:5694 drawInkLink + 5705 redrawInkLink + 5720 updateInkLinks) ──
##   两被连敌人脚底间画双层墨线: 外层淡墨晕(8px 0x140a28 a0.16) + 主墨线(3px 0x8a5cff a0.32) + 两端墨点。
##   PoC: buff 驱动逐帧重画 (随龟移动跟随), 任一方失去 _inkLink (到期) 或死亡 → 销毁该线。
##   Godot: 注册 (a_idx,b_idx) 对 → _process 每帧从活节点脚底重画 + 检查 _inkLink/存活 teardown。
var _ink_links: Array = []   # [{a:int, b:int, root:Node2D, halo:Line2D, main:Line2D, dots:[ColorRect,ColorRect]}]

func _draw_ink_link(idx_a: int, idx_b: int) -> void:
	if idx_a < 0 or idx_a >= slot_nodes.size() or idx_b < 0 or idx_b >= slot_nodes.size():
		return
	# 涉及同一只龟的旧线先清 (重复连笔 → 刷新, 不叠多条) — 1:1 PoC drawInkLink:5696-5699
	for i in range(_ink_links.size() - 1, -1, -1):
		var l: Dictionary = _ink_links[i]
		if l["a"] == idx_a or l["a"] == idx_b or l["b"] == idx_a or l["b"] == idx_b:
			if is_instance_valid(l["root"]):
				l["root"].queue_free()
			_ink_links.remove_at(i)
	var root := Node2D.new()
	root.z_index = 0
	slots_root.add_child(root)
	# 外层淡墨晕 (8px)
	var halo := Line2D.new()
	halo.width = 8.0
	halo.default_color = Color(0x14 / 255.0, 0x0a / 255.0, 0x28 / 255.0, 0.16)
	root.add_child(halo)
	# 主墨线 (3px 淡紫)
	var main := Line2D.new()
	main.width = 3.0
	main.default_color = Color(0x8a / 255.0, 0x5c / 255.0, 1.0, 0.32)
	root.add_child(main)
	# 两端脚底墨点 (半径 4, ColorRect 近似 8×8)
	var dots: Array = []
	for k in range(2):
		var dot := ColorRect.new()
		dot.color = Color(0x8a / 255.0, 0x5c / 255.0, 1.0, 0.38)
		dot.size = Vector2(8, 8)
		root.add_child(dot)
		dots.append(dot)
	var ln := {"a": idx_a, "b": idx_b, "root": root, "halo": halo, "main": main, "dots": dots}
	_ink_links.append(ln)
	_redraw_ink_link(ln)   # 立即画首帧


## 单条墨线: 从两端活节点脚底 (= slot 节点当前 position, 战斗中随 juggle/hop 移动) 重画。
func _redraw_ink_link(ln: Dictionary) -> void:
	var na: Node2D = slot_nodes[ln["a"]]
	var nb: Node2D = slot_nodes[ln["b"]]
	# slot 节点 position = 脚底锚 (PoC footY ≈ sprite.y + displayHeight/2 - 4, 此处即节点位)
	var p1: Vector2 = na.position
	var p2: Vector2 = nb.position
	var halo: Line2D = ln["halo"]
	var main: Line2D = ln["main"]
	halo.points = PackedVector2Array([p1, p2])
	main.points = PackedVector2Array([p1, p2])
	(ln["dots"][0] as ColorRect).position = p1 - Vector2(4, 4)
	(ln["dots"][1] as ColorRect).position = p2 - Vector2(4, 4)


## 每帧: 重画活跃连笔线; 任一方失去 _inkLink (到期) 或死亡 → 销毁该线 (1:1 PoC updateInkLinks:5720)。
## 燃烧叠层同步 — 1:1 PoC syncBurnOverlay (BattleScene.ts:229-249): 有 burn buff 的存活龟显
##   burn-loop 8帧@10fps 循环叠层, 跟随龟身; burn 消失即销毁。PoC SCREEN 混合 → Godot 用 ADD 近似(发亮叠加)。
## 黑礁猎团: 猎物(_huntTarget)身上罩红色脉冲瞄准环 — 醒目标记谁是猎物 (替代只有小徽章)。
func _sync_hunt_reticle() -> void:
	for i in range(mini(slot_nodes.size(), fighters.size())):
		var node: Node2D = slot_nodes[i]
		if not is_instance_valid(node):
			continue
		var f: Dictionary = fighters[i]
		var is_prey: bool = f.get("alive", false) and f.get("_huntTarget", false)
		var rt = node.get_meta("hunt_reticle") if node.has_meta("hunt_reticle") else null
		if is_prey and (rt == null or not is_instance_valid(rt)):
			node.set_meta("hunt_reticle", _make_hunt_reticle(node))
		elif not is_prey and rt != null and is_instance_valid(rt):
			rt.queue_free()
			node.set_meta("hunt_reticle", null)


func _make_hunt_reticle(node: Node2D) -> Node2D:
	var ret := Node2D.new()
	ret.position = Vector2(0, -40.0)   # 胸口高度
	ret.z_index = 60
	var ph := [0.0]
	ret.draw.connect(func() -> void:
		var pulse: float = 1.0 + 0.12 * sin(ph[0] * TAU)
		var r: float = 30.0 * pulse
		ret.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1.0, 0.25, 0.25, 0.85), 2.5, true)
		ret.draw_arc(Vector2.ZERO, r - 6.0, 0.0, TAU, 40, Color(1.0, 0.45, 0.45, 0.4), 1.5, true)
		for a in [0.0, PI / 2.0, PI, PI * 1.5]:
			var d: Vector2 = Vector2(cos(a), sin(a))
			ret.draw_line(d * (r - 4.0), d * (r + 5.0), Color(1.0, 0.3, 0.3, 0.9), 2.0))
	node.add_child(ret)
	var tw := ret.create_tween().set_loops()
	tw.tween_method(func(v: float): ph[0] = v; if is_instance_valid(ret): ret.queue_redraw(), 0.0, 1.0, 1.0)
	return ret


func _sync_burn_overlays() -> void:
	for i in range(mini(slot_nodes.size(), fighters.size())):
		var node: Node2D = slot_nodes[i]
		if not is_instance_valid(node):
			continue
		var f: Dictionary = fighters[i]
		var has_burn := false
		if f.get("alive", false):
			for b in f.get("buffs", []):
				if b is Dictionary and b.get("type", "") == "burn":
					has_burn = true
					break
		var ov = node.get_meta("burn_overlay") if node.has_meta("burn_overlay") else null
		if has_burn and (ov == null or not is_instance_valid(ov)):
			node.set_meta("burn_overlay", _make_burn_overlay(node))
		elif not has_burn and ov != null and is_instance_valid(ov):
			ov.queue_free()
			node.set_meta("burn_overlay", null)


func _make_burn_overlay(node: Node2D) -> Sprite2D:
	var path := "res://assets/sprites/vfx/burn-loop.png"
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var fh: int = tex.get_height()
	if fh <= 0:
		return null
	var n: int = maxi(1, int(tex.get_width() / fh))   # 8 帧方形条
	var avatar = node.get_meta("avatar") if node.has_meta("avatar") else null
	var ov := Sprite2D.new()
	ov.texture = tex
	ov.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ov.hframes = n
	ov.frame = 0
	ov.scale = Vector2(128.0 / float(fh), 128.0 / float(fh))   # PoC setDisplaySize(128,128)
	ov.position = avatar.position if avatar != null else Vector2(0, -40)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # PoC mix-blend-mode:screen → ADD 近似
	ov.material = mat
	ov.z_index = 1   # 龟身之上 (PoC sprite.depth+1; z_as_relative 默认 → 相对父 +1)
	node.add_child(ov)
	var tw := ov.create_tween().set_loops()              # 8帧@10fps=800ms 循环 (BootScene:520)
	tw.tween_method(
		func(fv: float) -> void:
			if is_instance_valid(ov):
				ov.frame = int(fv) % n,
		0.0, float(n), float(n) / 10.0)
	return ov


func _process(_delta: float) -> void:
	_sync_burn_overlays()   # 任何 fighter 有 burn buff → 显/隐 burn-loop 叠层 (1:1 PoC syncBurnOverlay)
	_ground_flagged_shadows()   # 击飞/小跳/抛投期间影子留在地面 (1:1 PoC: 只动 sprite, 影子不抬起)
	_sync_rock_body_scale()   # 磐石之躯: 岩层每层 +2% 体型 → 龟身+影子一起放大 (1:1 PoC syncRockBodyScale)
	_sync_blackhole_overlays()   # 黑洞: 有 blackhole buff 的单位被深色椭圆罩住 (1:1 PoC updateBlackholeVisuals)
	_refresh_skill_card_state()   # 被动大卡开着→实时刷状态行(金币/击杀/怒气随战斗变)
	_sync_hunt_reticle()   # 黑礁: 猎物身上罩红色脉冲瞄准环
	if _ink_links.is_empty():
		return


## 黑洞罩层 (1:1 PoC updateBlackholeVisuals ts:5736): 有 blackhole buff 的存活单位被深色椭圆(64×88 #05010f a.95 + 紫边#8b5cf6)罩住,
##   每帧跟随龟身; buff 消失则移除. 表现"被吸进黑洞".
func _sync_blackhole_overlays() -> void:
	for i in range(fighters.size()):
		if i >= slot_nodes.size() or not is_instance_valid(slot_nodes[i]):
			continue
		var f: Dictionary = fighters[i]
		var node: Node2D = slot_nodes[i]
		var has_bh: bool = f.get("alive", false) and Buffs.has(f, "blackhole")
		var ov = node.get_meta("_bh_overlay", null) if node.has_meta("_bh_overlay") else null   # null 默认仍会对缺失键报错 → 先 has_meta 守卫
		if has_bh:
			if ov == null or not is_instance_valid(ov):
				var av: Sprite2D = node.get_meta("avatar", null)
				var holder := Node2D.new()
				holder.position = (av.position if av != null else Vector2(0, -50))
				holder.z_index = 6   # 罩龟身上, HP条(HUD 兄弟节点)之下
				var ell := PackedVector2Array()
				for k in range(28):
					var a := TAU * float(k) / 28.0
					ell.append(Vector2(cos(a) * 32.0, sin(a) * 44.0))   # 椭圆 半宽32×半高44 = 64×88
				var fill := Polygon2D.new()
				fill.polygon = ell
				fill.color = Color(0.020, 0.004, 0.059, 0.95)   # #05010f
				holder.add_child(fill)
				var stroke := Line2D.new()
				stroke.points = ell
				stroke.closed = true
				stroke.width = 3.0
				stroke.default_color = Color(0.545, 0.361, 0.965, 0.85)   # #8b5cf6
				holder.add_child(stroke)
				node.add_child(holder)
				node.set_meta("_bh_overlay", holder)
		elif ov != null and is_instance_valid(ov):
			ov.queue_free()
			node.set_meta("_bh_overlay", null)


## 标了 _ground_shadow 的 root: 反抵其 y 抬升 + 旋转, 让影子(root子)留在地面平躺、横向仍跟随 root.x.
##   击飞/小跳/抛投类动画动 root → 影子本会一起飞; 此处每帧补偿 (1:1 PoC 这些动画只动 sprite, 影子留地).
##   滑步换排(气波)等【不】标记 → 影子正常跟随到新位置.
func _ground_flagged_shadows() -> void:
	for i in range(slot_nodes.size()):
		var rn: Node2D = slot_nodes[i]
		if not is_instance_valid(rn) or not rn.get_meta("_ground_shadow", false):
			continue
		var sh = rn.get_meta("shadow", null)
		if sh == null or not is_instance_valid(sh):
			continue
		var shome: Vector2 = sh.get_meta("home", Vector2.ZERO)
		var rhome: Vector2 = rn.get_meta("home_pos", rn.position)
		sh.position.y = shome.y - (rn.position.y - rhome.y)   # 反抵 root 抬升 → 影子留地面 (x 仍随 root 横移)
		sh.rotation = deg_to_rad(24.0) - rn.rotation           # 反抵 root 旋转 → 影子保持平躺 24°


## 磐石之躯体型: 岩层每层 +2% sprite (cap 30 → +60%), 龟身(avatar)+脚底影子(shadow)一起放大.
##   1:1 PoC syncRockBodyScale (BattleScene.ts:2008). 只在 _rockLayers 变化时写一次. 影子放大后重算模糊 σ
##   (sigma_texels = 4.48/scale → 保持屏幕模糊恒 4.48px).
func _sync_rock_body_scale() -> void:
	for i in range(slot_nodes.size()):
		var node: Node2D = slot_nodes[i]
		if not is_instance_valid(node) or i >= fighters.size():
			continue
		var f: Dictionary = fighters[i]
		if not f.get("_hasRockArmor", false):
			continue
		var avatar = node.get_meta("avatar", null)
		if avatar == null or not is_instance_valid(avatar):
			continue
		var shadow = node.get_meta("shadow", null)
		if not node.has_meta("_rockBaseAvatarScale"):
			node.set_meta("_rockBaseAvatarScale", avatar.get_meta("home_scale", avatar.scale))
			if shadow != null and is_instance_valid(shadow):
				node.set_meta("_rockBaseShadowScale", shadow.scale)
		var layers: int = mini(30, int(f.get("_rockLayers", 0)))
		if int(node.get_meta("_rockAppliedLayers", -1)) == layers:
			continue
		node.set_meta("_rockAppliedLayers", layers)
		var growth: float = 1.0 + 0.02 * float(layers)
		var base_av: Vector2 = node.get_meta("_rockBaseAvatarScale")
		avatar.scale = base_av * growth
		avatar.set_meta("home_scale", avatar.scale)   # 小跳/脉冲归位锚点用成长后 scale
		if shadow != null and is_instance_valid(shadow):
			var base_sh: Vector2 = node.get_meta("_rockBaseShadowScale")
			shadow.scale = base_sh * growth
			if shadow.material is ShaderMaterial:
				(shadow.material as ShaderMaterial).set_shader_parameter("sigma_texels", Vector2(4.48 / maxf(0.01, absf(shadow.scale.x)), 4.48 / maxf(0.01, absf(shadow.scale.y))))


## 击飞/小跳动画结束: 清 _ground_shadow 标记 + 把影子归位到 home (地面平躺 24°).
func _unground_shadow(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	node.set_meta("_ground_shadow", false)
	var sh = node.get_meta("shadow", null)
	if sh != null and is_instance_valid(sh):
		sh.position = sh.get_meta("home", sh.position)
		sh.rotation = deg_to_rad(24.0)
	for i in range(_ink_links.size() - 1, -1, -1):
		var ln: Dictionary = _ink_links[i]
		var ai: int = ln["a"]
		var bi: int = ln["b"]
		var fa: Dictionary = fighters[ai]
		var fb: Dictionary = fighters[bi]
		var alive: bool = fa.get("alive", false) and fb.get("alive", false)
		var linked: bool = (fa.get("_inkLink", null) is Dictionary) and (fb.get("_inkLink", null) is Dictionary)
		if not (alive and linked) or not is_instance_valid(ln["root"]):
			if is_instance_valid(ln["root"]):
				ln["root"].queue_free()
			_ink_links.remove_at(i)
			continue
		_redraw_ink_link(ln)


## 受击击退 (1:1 PoC playHitKnockback / JS sceneKnockback, BattleScene.ts:2896-2931):
##   目标 body(avatar) 远离攻击者 18px×baseScale + 抬 3px, 三段 52/105/193ms 归位; 影子 x 同步跟随。
##   _knockUntil 350ms 守卫: 350ms 内的后续命中段不重启动画 (PoC tv._knockUntil 同款)。
##   跳过名单 = PoC 中【用 applyRawDmg 而非 dealPhysical/dealMagic 落伤、故不触发通用 hitKnockback】的技能
##   (skill-handlers.ts:362 dealPhysical 末尾 api.hitKnockback; ghostPhantom/ninjaImpact 注释明确"抑制通用击退"ts:1386/1642)。
##   等价表述: 该集 = Godot _skill_post_impact 里【自定义击飞/抛投/击飞 target】的全部技能, 逐条核对 1:1, 非任选。
const _NO_HIT_KNOCK := ["basicSlam", "basicChiWave", "turtleShieldBash", "ninjaImpact", "ghostPhantom", "cyberBeam", "starWormhole", "starGravityWarp", "rockShockwave"]
func _hit_knockback(target_idx: int, attacker_side: String) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var avatar: Sprite2D = node.get_meta("avatar", null)
	if avatar == null:
		return
	var f: Dictionary = fighters[target_idx]
	if not f.get("alive", false):
		return
	# _knockUntil 350ms 守卫 (多段命中只首段动, 后续不重启)
	var now := Time.get_ticks_msec()
	if int(f.get("_knockUntil", 0)) > now:
		return
	f["_knockUntil"] = now + 350
	# 龟蛋受击: 震动+裂纹色闪 (蛋是静物, 不走龟的横推抬升 → 用专属命中演出)
	if f.get("_isEgg", false):
		_play_egg_hit(target_idx)
		return
	# baseScale: boss ×1.5 (1:1 PoC ts:2906)
	var is_boss: bool = bool(f.get("_isBoss", false))
	var base_scale: float = (0.9 * 1.417 * 1.5) if is_boss else (0.9 * 1.417)
	# 远离攻击者: 攻击者在左→目标右推(+); 在右→左推(-)
	var kx: float = (1.0 if attacker_side == "left" else -1.0) * roundf(18.0 * base_scale)
	var lift: float = roundf(3.0 * base_scale)
	var a_home: Vector2 = avatar.get_meta("home", avatar.position)
	var shadow: Sprite2D = node.get_meta("shadow", null)
	var s_home: Vector2 = (shadow.get_meta("home", shadow.position) if shadow != null else Vector2.ZERO)
	if node.has_meta("knock_tw"):
		var old = node.get_meta("knock_tw")
		if old is Tween and old.is_valid():
			old.kill()
	avatar.position = a_home   # 归位 (防上次被 kill 停在偏移处)
	if shadow != null:
		shadow.position = s_home
	var tw := create_tween()
	node.set_meta("knock_tw", tw)
	# 15% (52ms): 推 kx + 抬 lift
	tw.tween_property(avatar, "position", a_home + Vector2(kx, -lift), 0.052).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if shadow != null:
		tw.parallel().tween_property(shadow, "position:x", s_home.x + kx, 0.052).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 45% (105ms): 落到 kx 同高
	tw.tween_property(avatar, "position", a_home + Vector2(kx, 0.0), 0.105).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 100% (193ms): 归位
	tw.tween_property(avatar, "position", a_home, 0.193).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if shadow != null:
		tw.parallel().tween_property(shadow, "position:x", s_home.x, 0.193).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 受击 scale dip (1:1 PoC playAction 'hurt' ts:3894-3905: ×0.92x/×1.05y 挤压 50ms power2.in → 复原 100ms sine.out)。
	#   绕 home_scale 防累积(保留 flip 符号) + kill 旧 scale tween 防重叠; 与击退同受 _knockUntil 守卫 → 多段只首段动.
	var hs: Vector2 = avatar.get_meta("home_scale", avatar.scale)
	if node.has_meta("hurt_scale_tw"):
		var olds = node.get_meta("hurt_scale_tw")
		if olds is Tween and olds.is_valid():
			olds.kill()
	avatar.scale = hs
	var stw := create_tween()
	node.set_meta("hurt_scale_tw", stw)
	stw.tween_property(avatar, "scale", Vector2(hs.x * 0.92, hs.y * 1.05), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	stw.tween_property(avatar, "scale", hs, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _flash_hit(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var node: Node2D = slot_nodes[idx]
	var avatar: Sprite2D = node.get_meta("avatar")
	if not avatar:
		return
	# 杀掉上一段未结束的 flash tween, 否则快速多段命中(闪电80/风暴95/虫洞120ms < flash 250ms)会把
	#   "中途的红色"当成 original 累积 → 龟越来越红、永远回不到白 ("乌龟莫名变红"). 始终回到白(保留 alpha)。
	if node.has_meta("flash_tw"):
		var old = node.get_meta("flash_tw")
		if old is Tween and old.is_valid():
			old.kill()
	var a: float = avatar.modulate.a
	avatar.modulate = Color(1.5, 1.5, 1.5, a)   # 白闪(提亮, 对齐 PoC setTint(0xffffff) 白) — 原偏红 (1,0.5,0.5)
	var tween := create_tween()
	node.set_meta("flash_tw", tween)
	tween.tween_property(avatar, "modulate", Color(1, 1, 1, a), 0.12)   # PoC ~120ms (原 250ms 偏长)


## 命中冲击 FX (1:1 PoC playImpactFx ts:3928): 每击 白环扩散 r4→36/260ms + 中心闪点 r8 fade; 暴击金/r60/380ms/r14 + 4向迸射.
##   全是圆 (Line2D环 + Polygon2D点), 非粒子 → 不受亚像素纹理问题影响. 区别于已删的自创 playMeleeArcTrail "小球弧线".
func _play_impact_fx(target_idx: int, is_crit: bool) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var node: Node2D = slot_nodes[target_idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	var pos: Vector2 = av.position if av != null else Vector2(0, -50)
	var col: Color = Color(1.0, 0.843, 0.0) if is_crit else Color(1, 1, 1)   # 暴击金 #ffd700 / 普通白
	var ring_max: float = 60.0 if is_crit else 36.0
	var ring_dur: float = 0.38 if is_crit else 0.26
	# 圆环扩散 (stroke circle r4 → ring_max, alpha 0.9→0)
	var ring := Line2D.new()
	ring.points = _circle_points(4.0)
	ring.closed = true
	ring.width = 3.0
	ring.default_color = Color(col.r, col.g, col.b, 0.9)
	ring.position = pos
	ring.z_index = 48
	node.add_child(ring)
	var rtw := ring.create_tween().set_parallel(true)
	rtw.tween_property(ring, "scale", Vector2(ring_max / 4.0, ring_max / 4.0), ring_dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rtw.tween_property(ring, "modulate:a", 0.0, ring_dur)
	get_tree().create_timer(ring_dur + 0.05).timeout.connect(ring.queue_free)
	# 中心闪点 (filled circle r8/r14, alpha 0.9→0 + scale→0.4)
	var fl := Polygon2D.new()
	fl.polygon = _circle_points(14.0 if is_crit else 8.0)
	fl.color = Color(col.r, col.g, col.b, 0.9)
	fl.position = pos
	fl.z_index = 49
	node.add_child(fl)
	var fdur: float = 0.22 if is_crit else 0.15
	var ftw := fl.create_tween().set_parallel(true)
	ftw.tween_property(fl, "scale", Vector2(0.4, 0.4), fdur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ftw.tween_property(fl, "modulate:a", 0.0, fdur)
	get_tree().create_timer(fdur + 0.05).timeout.connect(fl.queue_free)
	# 4 向迸射 (仅暴击): 4 小圆 r4 → (±28,±28) cross, fade+缩 280ms
	if is_crit:
		for off in [Vector2(28, 0), Vector2(-28, 0), Vector2(0, -28), Vector2(0, 28)]:
			var sp := Polygon2D.new()
			sp.polygon = _circle_points(4.0)
			sp.color = col
			sp.position = pos
			sp.z_index = 49
			node.add_child(sp)
			var stw := sp.create_tween().set_parallel(true)
			stw.tween_property(sp, "position", pos + off, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			stw.tween_property(sp, "scale", Vector2(0.3, 0.3), 0.28)
			stw.tween_property(sp, "modulate:a", 0.0, 0.28)
			get_tree().create_timer(0.33).timeout.connect(sp.queue_free)


## 暴击全屏白闪 (1:1 PoC flashCritScreen ts:5141): 全屏白 alpha 0→0.4→0 yoyo 80ms.
func _flash_crit_screen() -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.0)
	flash.size = get_viewport().get_visible_rect().size   # 盖满视口 (CanvasLayer 上 anchors preset 不生效 → 显式 size, 同 _trigger_transform 4837)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 95
	fx_layer.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.4, 0.08)
	tw.tween_property(flash, "color:a", 0.0, 0.08)
	tw.tween_callback(flash.queue_free)


## 事件来袭入场闪 (1:1 PoC flashEventEntrance ts:1752): 暗底 #1a1024 脉冲(0→.42→0,150ms+110hold) + 橙闪 #ffb01f(0→.2→0,120ms) + 轻震(180,.004).
func _flash_event_entrance() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.102, 0.063, 0.141, 0.0)
	dim.size = get_viewport().get_visible_rect().size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 88
	fx_layer.add_child(dim)
	var dtw := dim.create_tween()
	dtw.tween_property(dim, "color:a", 0.42, 0.15)
	dtw.tween_interval(0.11)
	dtw.tween_property(dim, "color:a", 0.0, 0.15)
	dtw.tween_callback(dim.queue_free)
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.690, 0.122, 0.0)
	flash.size = get_viewport().get_visible_rect().size   # 盖满视口 (CanvasLayer 上 anchors preset 不生效 → 显式 size, 同 _trigger_transform 4837)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 89
	fx_layer.add_child(flash)
	var ftw := flash.create_tween()
	ftw.tween_property(flash, "color:a", 0.2, 0.12)
	ftw.tween_property(flash, "color:a", 0.0, 0.12)
	ftw.tween_callback(flash.queue_free)
	_play_screen_shake(0.18, 4.0)   # PoC cam.shake(180, 0.004) → ×1000 = 4px


## 按 Phaser visual_dispatcher.ts spec 飘字 (颜色 / 字号 / amount 缩放 / 暴击)
## 飘字堆叠行偏移 (1:1 PoC visual_dispatcher: 三色伤害固定行 红0/蓝1/白2, 非伤害 3/4; 同行同窗口再堆叠)
## 防止同一目标短时间内多个飘字重叠看不清. ROW_HEIGHT=22, 窗口 220ms.
var _float_stack: Dictionary = {}        # 非伤害: "tgt-base_row" → {ms, count}
var _float_dmg_window: Dictionary = {}   # 三色伤害: target_idx → {ranks:Array, ms:int}
func _float_row_offset(target_idx: int, kind: String, dmg_type: String) -> float:
	var now := Time.get_ticks_msec()
	if kind == "damage":
		# 三色伤害(红0/蓝1/白2): 同窗口(220ms)内按【已登记 rank 排序后的紧凑索引】×22 → 缺色不留空
		#   (只红+白 → 0,22 而非 0,44), 同色同 rank 同行(各自上飞错开, 不叠梯子)。
		#   1:1 PoC visual_dispatcher damageRowOffset (render 时按 rank 集排序索引, 不用 base_row×22)。
		var rank: int = 1 if dmg_type == "magic" else (2 if dmg_type == "true" else 0)
		var w: Dictionary = _float_dmg_window.get(target_idx, {"ranks": [], "ms": 0})
		if now - int(w.get("ms", 0)) > 220:
			w = {"ranks": [], "ms": 0}
		var ranks: Array = w["ranks"]
		if not ranks.has(rank):
			ranks.append(rank)
		w["ranks"] = ranks; w["ms"] = now
		_float_dmg_window[target_idx] = w
		var sorted_ranks: Array = ranks.duplicate(); sorted_ranks.sort()
		return float(maxi(0, sorted_ranks.find(rank))) * 22.0
	# 非伤害(治疗/盾/dot/被动/miss): 到达序紧凑堆叠 0/22/44… 从 row0 起 (1:1 PoC pickRowOffset:178, 窗口 100ms)。
	#   原 Godot 加了 base_row 3/4(=非伤害飘字凭空高 66-88px) + 窗口 220ms = 偏差; 现对齐 PoC(无 base_row, 100ms)。
	var key := "%d-nd" % target_idx
	var rec: Dictionary = _float_stack.get(key, {"ms": 0, "count": 0})
	if now - int(rec["ms"]) > 100:
		rec["count"] = 0
	rec["ms"] = now
	var extra: int = int(rec["count"])
	rec["count"] = extra + 1
	_float_stack[key] = rec
	return float(extra) * 22.0


## 标签 autoOffset (1:1 PoC ts:264-272/430): 同目标每 spawn +16px, 600ms 窗口归零。仅 label 路径(治疗/盾/MISS)用。
var _float_auto_stack: Dictionary = {}
func _float_auto_offset(target_idx: int) -> float:
	var now := Time.get_ticks_msec()
	var rec: Dictionary = _float_auto_stack.get(target_idx, {"ms": 0, "count": 0})
	if now - int(rec["ms"]) > 600:
		rec["count"] = 0
	var n: int = int(rec["count"])
	rec["count"] = n + 1
	rec["ms"] = now
	_float_auto_stack[target_idx] = rec
	return float(n) * 16.0


# 并段时需逐段保留的【装备 proc VFX】字段集 — 见 _coalesce_multihit_segments / _play_seg_proc_vfx。
#   (vfx 类型键 + 其参数键; 不含 arrival_delay, 那个并段另有 per-source 处理逻辑)。
const _VFX_CARRY_KEYS := [
	"vfx", "vfx_from", "vfx_color", "vfx_scale", "vfx_path", "vfx_size", "vfx_dur",
	"vfx_width", "vfx_pierce", "vfx_delay", "vfx_pellets", "chain_idx",
]

## 多段伤害逐段播放 — 1:1 PoC 每 hit 一个 api.floatNum + 段间 sleep, 血条随每 hit 下降。
##   seg = {value:int, dmg_type:String, is_crit:bool, delay:float(秒,相对本effect起点),
##          y_off:float(同型多段垂直错开), hp_after:float(该段后HP, 血条step), shield_after:float(可选)}
##   delay<=0 立即; 否则 timer 错开。display-only: HP 已由 execute 扣完, 这里只编排"看起来逐段掉"。
## 把同目标的多个 per-hit 伤害 effect 合并成 1 条带 segments(逐段错开飘字 + 逐段血条trail), 修多段"节奏全挤一帧".
##   只合并 kind=="damage" 且无现成 segments 的; 同目标≥2 段才合. hp_after 由最终HP反推(无盾时精确, 末段必精确).
##   每段间隔 0.12s (≈ PoC 多段 floatNum stagger). 非伤害/单段/已带segments 的原样保留.
##   no_coalesce 标记的 effect 不参与并段(多弹武器 048/049/050/053 等连发子弹: 每颗自带 arrival_delay
##     按各自落地时刻【逐颗各掉各血+各飘字】, 不被并成一次掉血) — 原样穿过, 走单发投射 arrival_delay 路径。
func _coalesce_multihit_segments(effs: Array, stagger: float = 0.5) -> Array:
	var dmg_pos_by_t: Dictionary = {}   # target_idx → [effs 中的位置]
	for i in range(effs.size()):
		var e = effs[i]
		if e is Dictionary and e.get("kind", "") == "damage" and not e.has("segments") and not e.get("no_coalesce", false):
			var t: int = int(e.get("target_idx", -1))
			if not dmg_pos_by_t.has(t):
				dmg_pos_by_t[t] = []
			(dmg_pos_by_t[t] as Array).append(i)
	var merge_t: Dictionary = {}
	for t in dmg_pos_by_t:
		if (dmg_pos_by_t[t] as Array).size() >= 2:
			merge_t[t] = true
	if merge_t.is_empty():
		return effs   # 无多段同目标 → 原样(单段技能不受影响)
	var out: Array = []
	var done_t: Dictionary = {}
	for i in range(effs.size()):
		var e = effs[i]
		var t: int = int(e.get("target_idx", -1)) if e is Dictionary else -1
		if e is Dictionary and e.get("kind", "") == "damage" and not e.has("segments") and not e.get("no_coalesce", false) and merge_t.has(t):
			if done_t.has(t):
				continue   # 后续同目标段已并入首段, 跳过
			done_t[t] = true
			var vals: Array = []
			var dts: Array = []
			var crits: Array = []
			# 投射物落地延迟: 并段组里若有 arrival_delay(枪弹/弩箭等), 取该组【最小】当并段基线 —
			#   第一发子弹落地即开始逐段 step, 段内 stagger 仍逐段错开 (数值不动, 只推迟显示时机)。
			var grp_arrival: float = -1.0
			for pos in (dmg_pos_by_t[t] as Array):
				if effs[pos].has("arrival_delay"):
					var ad: float = float(effs[pos].get("arrival_delay", 0.0))
					grp_arrival = ad if grp_arrival < 0.0 else minf(grp_arrival, ad)
			# 装备 proc VFX 字段 (slash/fireball/goldbullet/swordecho/lightning/projectile…) 每段各带 1 份 →
			#   并段不再吞掉 proc 特效 (原 bug: 重建 merged 只 copy value/dmg_type/is_crit/delay/hp_after, 丢 vfx*/
			#   per-source arrival_delay → 双生匕首等 proc 斩弧被并段那几下永不播)。_VFX_CARRY_KEYS 逐段随段保留,
			#   _render_one_segment 在各段落地时刻各播一次 → N 次 proc = N 个斩弧 (时序对齐血条 step)。
			var vfxs: Array = []        # 各源的 vfx 子集 (无 vfx → 空 dict)
			var src_arr: Array = []     # 各源自带的 arrival_delay (无 → -1)
			for pos in (dmg_pos_by_t[t] as Array):
				vals.append(int(effs[pos].get("value", 0)))
				dts.append(str(effs[pos].get("dmg_type", "physical")))
				crits.append(bool(effs[pos].get("is_crit", false)))
				var src_e: Dictionary = effs[pos]
				var vsub: Dictionary = {}
				for vk in _VFX_CARRY_KEYS:
					if src_e.has(vk):
						vsub[vk] = src_e[vk]
				vfxs.append(vsub)
				src_arr.append(float(src_e.get("arrival_delay", -1.0)) if src_e.has("arrival_delay") else -1.0)
			var total: int = 0
			for v in vals:
				total += int(v)
			var final_hp: float = float(fighters[t].get("hp", 0)) if (t >= 0 and t < fighters.size()) else 0.0
			var max_hp: float = float(fighters[t].get("maxHp", 1)) if (t >= 0 and t < fighters.size()) else 1.0
			var segs: Array = []
			for k in range(vals.size()):
				var rest: int = 0
				for m in range(k + 1, vals.size()):
					rest += int(vals[m])
				var seg_d: Dictionary = {
					"value": int(vals[k]), "dmg_type": str(dts[k]), "is_crit": bool(crits[k]),
					"delay": float(k) * stagger, "hp_after": clampf(final_hp + rest, final_hp, max_hp),
				}
				# 该段对应源的 proc VFX 字段随段走 (vfx/vfx_from/vfx_color/vfx_scale/vfx_path/...) → 逐段各播一次
				var vsub_k: Dictionary = vfxs[k]
				for vk in vsub_k:
					seg_d[vk] = vsub_k[vk]
				# per-source 落地延迟 (单发投射 proc): 若该段源自带 arrival_delay 且 ≠ 组基线, 段内额外推迟 (差量叠到 delay)
				if float(src_arr[k]) >= 0.0 and grp_arrival >= 0.0 and float(src_arr[k]) > grp_arrival:
					seg_d["delay"] = float(seg_d["delay"]) + (float(src_arr[k]) - grp_arrival)
				segs.append(seg_d)
			var merged: Dictionary = {"target_idx": t, "kind": "damage", "value": total, "dmg_type": str(dts[0]), "is_crit": crits.has(true), "segments": segs}
			if grp_arrival >= 0.0:
				merged["arrival_delay"] = grp_arrival   # 并段后保留落地延迟 (调用方把它叠到各段 delay 上)
			# 注意: proc VFX 由【各段】在落地时刻各播 (见 _render_one_segment + _play_seg_proc_vfx), merged 顶层【不】
			#   再挂 vfx → 避免渲染循环顶层分发(7001+)与逐段播【双触发】(首发斩弧/弹道会播两次)。merged 只承载聚合飘字/血条。
			out.append(merged)
		else:
			out.append(e)
	return out


# ───────────────────────────────────────────────────────────────────────────
# 每目标统一显示调度器 (per-target display scheduler)
#   病根: 本会话堆了 4+ 套独立错峰(并段 segments / 投射 arrival / 逐颗子弹 / DoT 错峰 / 海浪 / 火柱 …),
#   各自 create_timer 抢同一根血条 + 飘字层。多源同打一目标时, 这些 fire-and-forget 定时器会落在【同一帧】→
#   HpBar 单调守卫(hp_bar:66/73)把它们塌成"一下掉血/一条 trail", 飘字叠, 迟到定时器拿旧 hp_after 回刷。
#
#   解法: 同一 target 的所有【显示事件】(飘字+血条 step)排进一条有序队列, 由【单一驱动】按【单调递增显示时刻】
#   依次消费, 同目标两事件至少隔 _DISP_MIN_GAP 不塌一帧。各机制【何时显】的意图(arrival/stagger)原样作为
#   事件的 `at` 入队 — 调度器只解决"同目标多事件排队不打架", 不改任何【何时显】, 更【绝不动伤害数值/统计/死亡时机】。
#   纯显示路: 事件 payload 只带 value/hp_after 等"看起来怎么掉", HP 早在 execute/Dot.tick 扣完。
#
#   事件 shape: { at:float(秒,相对入队时刻), kind:"damage"/"dot", value:int, dmg_type/cls, is_crit:bool,
#                hp_after:float(可选,血条权威步进值), shield_after:float, atk_side, suppress_knock, epoch:int }
const _DISP_MIN_GAP: float = 0.10                # 同目标两显示事件最小间隔 (s) — 防塌一帧
var _disp_q: Dictionary = {}                     # target_idx → Array[event] (按 _wall_at 升序)
var _disp_cursor: Dictionary = {}                # target_idx → 下一个空闲显示时刻 (msec, 单调递增)
var _disp_epoch: Dictionary = {}                 # target_idx → epoch; 目标死亡/重定向时 +1 → 作废旧队列里的待显事件
var _disp_driving: Dictionary = {}               # target_idx → bool; 该目标是否已有驱动协程在跑 (避免并发驱动)


## 取目标当前 epoch (死亡/重定向时由 _bump_disp_epoch 递增 → 旧入队事件失效)
func _disp_epoch_of(idx: int) -> int:
	return int(_disp_epoch.get(idx, 0))


## 目标死亡 / 显示重定向: 作废其待显队列 + bump epoch (迟到事件不再拿旧 hp_after 回刷血条)。
func _bump_disp_epoch(idx: int) -> void:
	_disp_epoch[idx] = _disp_epoch_of(idx) + 1
	if _disp_q.has(idx):
		(_disp_q[idx] as Array).clear()


## 入队一个显示事件 — 所有机制(并段段/投射/逐颗子弹/DoT/海浪/火柱…)统一走此口。
##   at: 相对【入队此刻】的意图显示延迟(秒, 各机制算出的 arrival/stagger)。调度器按目标排队再加最小间隔约束。
func _enqueue_display(idx: int, ev: Dictionary) -> void:
	if idx < 0 or idx >= slot_nodes.size():
		return
	var e: Dictionary = ev.duplicate()
	e["epoch"] = _disp_epoch_of(idx)
	# 绝对墙钟到达时刻 (msec): 把"相对入队此刻的意图延迟"锁成绝对时间 → 后入队但 at 更小的事件不会乱序
	e["_wall_at"] = Time.get_ticks_msec() + int(maxf(0.0, float(e.get("at", 0.0))) * 1000.0)
	if not _disp_q.has(idx):
		_disp_q[idx] = []
	var q: Array = _disp_q[idx]
	# 按 _wall_at 升序插入 (稳定: 相等保持入队序 → 同时到达的多事件按提交顺序消费)
	var ins: int = q.size()
	for i in range(q.size()):
		if int((q[i] as Dictionary).get("_wall_at", 0)) > int(e["_wall_at"]):
			ins = i
			break
	q.insert(ins, e)
	if not bool(_disp_driving.get(idx, false)):
		_disp_driving[idx] = true
		_drive_display_queue(idx)


## 单一驱动协程: 按序消费某目标的显示队列, 给每事件单调递增的显示时刻(同目标≥_DISP_MIN_GAP), 严格按序驱动血条+飘字。
func _drive_display_queue(idx: int) -> void:
	# 出树守卫: 单测 .new() 不入树 → get_tree()/create_timer 不可用。不驱动(队列留给测试检视), 实战恒在树内。
	if not is_inside_tree():
		_disp_driving[idx] = false
		return
	while _disp_q.has(idx) and not (_disp_q[idx] as Array).is_empty():
		var q: Array = _disp_q[idx]
		var ev: Dictionary = q.pop_front()
		# 等到该事件的墙钟到达时刻 (各机制意图的 arrival/stagger 时点)
		var wait_ms: int = int(ev.get("_wall_at", 0)) - Time.get_ticks_msec()
		if wait_ms > 0:
			await get_tree().create_timer(float(wait_ms) / 1000.0).timeout
		# 作废守卫: 目标已死透 / epoch 已被 bump (死亡或重定向) → 丢弃此事件, 不回刷尸体血条
		if idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
			continue
		if int(ev.get("epoch", 0)) != _disp_epoch_of(idx):
			continue
		# 只有【已死透】(_deathVfxDone, 死亡演出已播) 才丢弃 — 致命那一击的事件 alive 早已 false (HP 在 execute 同步扣到 0),
		# 但死亡演出尚未播 → 必须放它过, 让血条 step 到 0 (致命掉血动画), 否则龟"没掉到 0 就死了"(用户报)。
		if idx < fighters.size() and fighters[idx].get("_deathVfxDone", false):
			continue
		# 最小间隔约束: 显示时刻 = max(意图到达时刻, 该目标上次显示+_DISP_MIN_GAP) → 不塌一帧
		var now_ms: int = Time.get_ticks_msec()
		var cursor_ms: int = int(_disp_cursor.get(idx, 0))
		if cursor_ms > now_ms:
			await get_tree().create_timer(float(cursor_ms - now_ms) / 1000.0).timeout
			# gap 等待期间可能死亡演出已播/重定向 → 再判一次 (同上: 仅 _deathVfxDone 才丢, 致命掉血放过)
			if idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
				continue
			if int(ev.get("epoch", 0)) != _disp_epoch_of(idx):
				continue
			if idx < fighters.size() and fighters[idx].get("_deathVfxDone", false):
				continue
		_disp_cursor[idx] = maxi(Time.get_ticks_msec(), cursor_ms) + int(_DISP_MIN_GAP * 1000.0)
		_consume_display_event(idx, ev)
	_disp_driving[idx] = false


## 等某目标的显示队列【全部消费完】(队列空且驱动协程已收尾)。
##   死亡时机根治: 致命那一下的血条 step 是【队列里】的事件, 受 _DISP_MIN_GAP 错峰影响, 显示时刻晚于
##   intent delay 估的 _seg_end。死亡前先 await 此函数 → 致命掉血动画(血条走到 0)先放完, 再播死亡演出,
##   让 死亡 = "致命显示完成驱动" 而非 "真实 HP 一到 0 就播"(脱节)。不动伤害/统计, 只把"何时播死"挪到血条到 0 那刻。
func _await_display_drained(idx: int) -> void:
	if not is_inside_tree():
		return   # 出树 (单测): 无驱动协程在跑, 直接返回
	# 上限守卫: 极端排队 (大量同目标事件) 不至于卡死回合推进 — 最多等 ~2.5s 兜底放行。
	var guard_ms: int = Time.get_ticks_msec() + 2500
	while (bool(_disp_driving.get(idx, false)) or (_disp_q.has(idx) and not (_disp_q[idx] as Array).is_empty())):
		if Time.get_ticks_msec() > guard_ms:
			break
		await get_tree().process_frame


## 消费单个显示事件: 按 kind 驱动血条 step + 飘字 + (damage 段的)flash/juice。纯显示, 不碰 fighter.hp/统计。
func _consume_display_event(idx: int, ev: Dictionary) -> void:
	var kind: String = str(ev.get("kind", "damage"))
	if kind == "dot":
		_spawn_dot_text(idx, int(ev.get("value", 0)), str(ev.get("cls", "dot-dmg")))
		if ev.has("hp_after"):
			_refresh_slot(idx, float(ev["hp_after"]))
		else:
			_refresh_slot(idx)
		return
	# damage 段: 复用 _render_one_segment 的整套演出 (飘字色/暴击/y_off + hp_after 血条 step + flash/juice)
	_render_one_segment(idx, ev, str(ev.get("atk_side", "left")), bool(ev.get("suppress_knock", false)))


## 段级装备 proc VFX 分发 — 并段后逐段保留的 vfx* 字段, 在该段落地时刻各播一次。
##   只处理【会落进段】的 proc VFX (slash/fireball/chainbolt/lightning/execute/swordecho/goldbullet/projectile);
##   "纯标记/continue 类"(blood/freeze/flameburst/crystalbeam…) 不会被并段(那些是 passive 或自带 continue 不进段),
##   故此处不分发它们 (与渲染循环顶层 7001+ 的"不 continue 即 fall-through 飘字"那批一致)。复用既有 _play_* primitive。
func _play_seg_proc_vfx(target_idx: int, seg: Dictionary) -> void:
	var vfx: String = str(seg.get("vfx", ""))
	if vfx == "":
		return
	var from_default: int = int(seg.get("vfx_from", target_idx))
	match vfx:
		"slash":
			_play_slash_at(target_idx, Color(str(seg.get("vfx_color", "#e8eef5"))), int(seg.get("vfx_from", from_default)), float(seg.get("vfx_scale", 1.0)))
		"swordecho":
			_play_slash_at(target_idx, Color("#d8e6f5"), int(seg.get("vfx_from", from_default)), 0.85)
		"fireball":
			_play_fireball(int(seg.get("vfx_from", -1)), target_idx)
		"goldbullet":
			_play_gold_bullet(int(seg.get("vfx_from", from_default)), target_idx)
		"chainbolt":
			_play_chain_bolt(int(seg.get("vfx_from", -1)), target_idx, int(seg.get("chain_idx", 0)))
		"lightning":
			_play_lightning_strike(target_idx)
		"execute":
			_play_execute_flash(target_idx)
		"projectile":
			var pf: int = int(seg.get("vfx_from", -1))
			if pf >= 0:
				_fire_projectile(pf, target_idx, str(seg.get("vfx_path", "")), float(seg.get("vfx_size", 32.0)), float(seg.get("vfx_dur", 0.36)))
		_:
			pass


func _play_damage_segments(target_idx: int, segments: Array, atk_side: String = "left", suppress_knock: bool = false) -> void:
	# 统一走显示调度器: 每段作为一个显示事件入队 (at=段意图延迟), 由 _drive_display_queue 按目标有序消费。
	#   原本每段各自 create_timer→_render_one_segment 抢血条 (多源同帧塌成一下); 现同目标排队不打架。
	for seg in segments:
		var sg: Dictionary = (seg as Dictionary).duplicate()
		sg["kind"] = "damage"
		sg["at"] = maxf(0.0, float(sg.get("delay", 0.0)))
		sg["atk_side"] = atk_side
		sg["suppress_knock"] = suppress_knock
		_enqueue_display(target_idx, sg)


## 单段渲染: 飘字(各自色/暴击/y_off) + 血条 step(hp_after) + flash + juice (PoC 每 hit 同款)。
func _render_one_segment(target_idx: int, seg: Dictionary, atk_side: String = "left", suppress_knock: bool = false) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	var v: int = int(seg.get("value", 0))
	var dt: String = str(seg.get("dmg_type", "physical"))
	var cr: bool = bool(seg.get("is_crit", false))
	var yo: float = float(seg.get("y_off", 0.0))
	# 装备 proc VFX (并段后逐段保留的 vfx*): 该段落地时刻各播一次 (斩弧/火球/金弹/弹道/链电 等) — 修并段吞特效。
	_play_seg_proc_vfx(target_idx, seg)
	# step_bar=false: 多段血条由本函数下方 hp_after 权威驱动, 不让飘字 chokepoint 再自行 step (防双扣).
	_spawn_float_text(target_idx, v, "damage", dt, cr, yo, false)
	# 血条逐段下降: 有 hp_after 用之 (turtle-hud playDamageTrail per hit), 否则刷到真实值
	if seg.has("hp_after"):
		_refresh_slot(target_idx, float(seg["hp_after"]), float(seg.get("shield_after", -1.0)))
	else:
		_refresh_slot(target_idx)
	# 同段追加飘字 (天使审判: 红物理 + 白魔法 同一 hit 各自跳出; 血条 step 已含 judgment(hp_after), 不再单独下降)
	#   step_bar=false: 这一段的 hp_after 已含审判全部伤害, extra_floats 只飘字不可再 step (否则双扣).
	for ef in seg.get("extra_floats", []):
		var efd: Dictionary = ef
		_spawn_float_text(target_idx, int(efd.get("value", 0)), "damage", str(efd.get("dmg_type", "magic")), bool(efd.get("is_crit", false)), float(efd.get("y_off", 22.0)), false)
	# 段 timer 跨~1s 可溢到下一回合; 若目标已死(尸体), 只补飘字+血条(命中已发生), 不再 flash/juice,
	#   否则会在别的回合冒出无关的 hit-stop 慢动作/震屏/红闪/暴击标 in 尸体上 (视觉回归三问之③)。
	if not fighters[target_idx].get("alive", false):
		return
	_flash_hit(target_idx)
	_play_impact_fx(target_idx, cr)   # 1:1 PoC showDamageVfx→playImpactFx: 每击白环+中心闪点 (暴击金+4向迸射)
	if not suppress_knock:
		_hit_knockback(target_idx, atk_side)
	# Juice per 段 (PoC 每 hit): 暴击 → hit-stop + 大震 + 暴击标; 大伤 → 中震
	var tmax: float = float(fighters[target_idx]["maxHp"])
	var hp_ratio: float = float(v) / maxf(1.0, tmax)
	if seg.get("micro_shake", false):
		_play_screen_shake(0.09, 1.75)   # 气波每发微震 (1:1 PoC shake(90, 0.0025)≈1.75px), 不论暴击, 无 hit-stop
	elif cr:
		_play_hit_stop(VisualConstants.HIT_STOP_MS_CRIT)
		_play_screen_shake(VisualConstants.SHAKE_CRIT_DURATION, VisualConstants.SHAKE_CRIT_STRENGTH)
		_spawn_crit_label(target_idx)
		_flash_crit_screen()   # 1:1 PoC showDamageVfx: 暴击全屏白闪 (flashCritScreen)
	elif hp_ratio > VisualConstants.BIG_HIT_HP_RATIO:
		_play_screen_shake(VisualConstants.SHAKE_BIG_DURATION, VisualConstants.SHAKE_BIG_STRENGTH)


## 飘字数字字体: emboldened m6x11+CJK (1:1 PoC .floating-num font-weight:900 厚重感), 缓存
var _float_num_font_cache: FontVariation = null
func _float_num_font() -> FontVariation:
	if _float_num_font_cache == null:
		var base: FontFile = load("res://assets/fonts/m6x11.ttf")
		var cjk := SystemFont.new()
		cjk.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "sans-serif"])
		cjk.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
		cjk.allow_system_fallback = true
		var main := FontVariation.new()
		main.base_font = base
		main.fallbacks = [cjk] as Array[Font]
		var bold := FontVariation.new()
		bold.base_font = main
		bold.variation_embolden = 0.5   # ≈ 900 weight 的厚重, 又不糊像素
		_float_num_font_cache = bold
	return _float_num_font_cache


## 显示血量 step-down (多源逐段修): 把目标血条从【当前正显示值】下移 amount, 但不低于真实终值 hp。
##   纯显示 — 不改 fighter.hp(execute 已扣)。血条 _prev_hp 是它自己的"已显示"账本, 直接读它当基线:
##   - 单源命中: 基线=命中前显示值, step 一次到真实值 (与原 _refresh_slot 同效果)。
##   - 多源(AOE 基础 + 装备 proc 等): 第一飘字从基线 step 一段, 第二飘字从【新基线】再 step 一段 … 逐段收敛。
##   回弹守卫 (hp_bar:60) 保证只降不升; floor 到 hp 保证不会停在真实值上方残留。
func _step_display_hp(idx: int, amount: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var node: Node2D = slot_nodes[idx]
	if not node.has_meta("hp_bar"):
		return
	var hp_bar: HpBar = node.get_meta("hp_bar")
	if not is_instance_valid(hp_bar):
		return
	var real_hp: float = float(fighters[idx].get("hp", 0))
	var shown: float = hp_bar.displayed_hp()   # 血条当前正显示的 HP (-1 = 未初始化)
	var baseline: float = shown if shown >= 0.0 else real_hp
	# 基线落后于真实值(血条还没显示这段伤害) 才 step; 已显示到/低于真实值 → 直接刷真实值。
	var target_disp: float = maxf(real_hp, baseline - float(amount))
	_refresh_slot(idx, target_disp)


func _spawn_float_text(target_idx: int, amount: int, kind: String, dmg_type: String = "physical", is_crit: bool = false, extra_y_off: float = 0.0, step_bar: bool = true) -> void:
	# 死龟身上不再飘任何字 (chokepoint): 残留装备/side_end 效果打到已死透的龟 → 不飘幻影伤害字。
	#   首杀的飘字仍显 (此时 _deathVfxDone 尚未被 _play_death 置位); 复活时 _revive_node 清标 → 恢复正常飘字。
	if target_idx >= 0 and target_idx < fighters.size() and fighters[target_idx].get("_deathVfxDone", false):
		return
	# 多源逐段 chokepoint: 任何来源(AOE 基础/装备 proc/审判/DoT/学派/羁绊…)的伤害飘字, 都让血条按本飘字的量
	#   逐段 step-down — 不再"第一下就刷到终值、后续飘字血条不动"。HP 在 execute 已扣完, 这里纯显示:
	#   从血条【当前正显示的 HP】减去 amount, floor 到真实终值 hp → 用 hp_override 刷 (回弹守卫 hp_bar:60 保单调).
	#   step_bar=false: 调用方自己管 hp_after(如 _render_one_segment 多段) → 不在此重复 step.
	if step_bar and kind == "damage" and amount > 0 and target_idx >= 0 and target_idx < fighters.size():
		_step_display_hp(target_idx, amount)
	if OS.has_environment("DIAG_DMG") and target_idx >= 0 and target_idx < fighters.size():   # 诊断: 记录每次伤害/治疗/效果飘字 (核对数值)
		print("[DMG] %s %s=%d (%s)%s" % [str(fighters[target_idx].get("name", "?")), kind, amount, dmg_type, " 暴击" if is_crit else ""])
	var node: Node2D = slot_nodes[target_idx]
	# PoC ts:283: 三色伤害【忽略 caller yOffset】(explicitYOffset=0), 垂直只靠排行(红0蓝1白2紧凑)+时机。
	#   原 Godot 个别技能(如 phys+true 审判)手传 y_off=22, 又叠排行22 = true 飘到 44(双重)。强制清0 → 只靠排行, 1:1。
	if kind == "damage":
		extra_y_off = 0.0
	# SFX 按 cls 决定 (跟 Phaser visual_dispatcher fireSfxForCls 同款)
	var cls_for_sfx: String = VisualConstants.cls_for(kind, dmg_type, is_crit)
	Audio.play_sfx_for_cls(cls_for_sfx)
	# (命中火花粒子已移除 — 自创: PoC BattleScene 无任何命中粒子, 用户要求去掉自创粒子)

	# 文案 (Phaser 同款: 伤害无前导 '-', 治疗/护盾带 '+', 闪避 MISS)
	var text: String
	if kind == "heal":
		text = "+%d" % amount
	elif kind == "shield":
		text = "+%d 盾" % amount
	elif kind == "miss":
		text = "MISS"
	else:
		text = str(amount)   # 伤害无符号

	# cls + 颜色 + 字号 (Phaser FLOAT_STYLE 表 + size-by-amount 公式 1:1)
	var cls: String = VisualConstants.cls_for(kind, dmg_type, is_crit)
	var color: Color = VisualConstants.color_of(cls)
	var size: int = VisualConstants.size_by_amount(amount, is_crit)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_font_override("font", _float_num_font())   # PoC .floating-num font-weight:900 厚重 → emboldened m6x11
	label.add_theme_color_override("font_color", color)
	# 描边 (Phaser CSS 8 方向 text-shadow 同款效果, Godot 用真 outline)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	# 1:1 PoC: 数字在【龟身中心】冒出 (spawnFloatingText 用 sprite.y = 身体中心), 不是脚底。
	#   slot 节点原点=脚底, avatar.position.y = -sprite_half = 身体中心 → 用它当起跳 y (原 -10 太低=贴脚)。
	var av_fl: Sprite2D = node.get_meta("avatar", null)
	var center_y: float = (av_fl.position.y if av_fl != null else -50.0)
	# 1:1 PoC floatNum setOrigin(0.5): 文字【水平+垂直居中】于龟身中心 + pop 缩放绕中心。
	#   (原 x=-30 左锚定 → 数字随位数左右漂 ±15px; 且缩放从左上角长出=非对称, 与 PoC 居中起爆不符。)
	var tsz: Vector2 = _float_num_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	# 飞行单元 fly_unit: 抛物/pop/淡出 tween 作用的节点 (默认=label 本体)。
	#   暴击伤害: 数字前内嵌 20×20 crit-dmg-icon (1:1 PoC .floating-num crit 内嵌 <img class=crit-dmg-icon>),
	#   把【图标+数字】包进一个 HBoxContainer → tween 作用到容器 → 图标与数字同一飞行单元 (不脱节)。
	var fly_unit: Control = label
	var unit_sz: Vector2 = tsz
	if is_crit and kind == "damage":
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 1)   # PoC crit-dmg-icon margin-right:1px
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		var icon := TextureRect.new()
		icon.texture = load("res://assets/sprites/stats/crit-dmg-icon.png")
		icon.custom_minimum_size = Vector2(20, 20)   # PoC 20×20
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 图标垂直居中、紧贴数字左侧
		box.add_child(icon)
		# label 进容器: 清掉单体居中偏移 (容器自身做居中), pivot 留默认 — 缩放由容器统一绕中心做。
		label.pivot_offset = Vector2.ZERO
		box.add_child(label)
		# 容器合成尺寸 = 图标(20) + 间距(1) + 数字宽; 高=max(20, 数字高) → 据此居中起跳 + pivot 居中。
		unit_sz = Vector2(20.0 + 1.0 + tsz.x, maxf(20.0, tsz.y))
		box.custom_minimum_size = unit_sz
		box.size = unit_sz
		fly_unit = box
	else:
		label.pivot_offset = tsz / 2.0   # 缩放/动画绕文字中心 (PoC origin 0.5), 非默认左上角
	# 1:1 PoC floatNum setOrigin(0.5): 飞行单元【水平+垂直居中】于龟身中心 + pop 缩放绕中心。
	#   (原 x=-30 左锚定 → 数字随位数左右漂 ±15px; 且缩放从左上角长出=非对称, 与 PoC 居中起爆不符。)
	fly_unit.position = Vector2(-unit_sz.x / 2.0, center_y - _float_row_offset(target_idx, kind, dmg_type) - extra_y_off - unit_sz.y / 2.0)
	fly_unit.pivot_offset = unit_sz / 2.0   # 缩放/动画绕单元中心 (PoC origin 0.5)
	node.add_child(fly_unit)

	# ── 飘字动画 1:1 PoC visual_dispatcher runFloatAnim (ts:404-469) + ticker (ts:343-354) ──
	var auto_off := _float_auto_offset(target_idx)   # PoC ts:266 每次 spawn 都 +1 计数, 仅 label 路径用其值
	var base_pos := fly_unit.position
	var hold_scale := 1.0 if is_crit else 0.7
	if kind == "damage":
		# 伤害: pop(放大到 popSize 1.6~2.5) → hold → 抛物飞行(按屏边横跳 + 重力200) — ts:445-468
		fly_unit.scale = Vector2(0.01, 0.01)
		var pop_size := 1.6 if amount < 20 else (1.8 if amount < 60 else (2.2 if amount < 150 else 2.5))
		var dir := -1.0 if node.global_position.x < 640.0 else 1.0   # 左半屏往左跳/右半往右 (ts:449)
		var jump_x := dir * (12.0 + randf() * 14.0)                  # ts:450
		var jump_y := (-(10.0 + randf() * 8.0)) if is_crit else (-(22.0 + randf() * 10.0))  # ts:451
		var hold_end := 0.4 if is_crit else 0.15                    # ts:457 crit 锁久点
		var total_dur := hold_end + 0.65                            # ts:458-459 flightDur650
		var fade_start := hold_end + 0.3                            # ts:461
		var tw := create_tween()
		tw.tween_method(_dmg_float_step.bind(fly_unit, base_pos, jump_x, jump_y, hold_end, hold_scale, pop_size, total_dur, fade_start), 0.0, total_dur, total_dur)
		tw.tween_callback(fly_unit.queue_free)
	else:
		# 治疗/护盾/MISS: PoC label 路径 (ts:427-442): startY 多抬 -15 - autoOffset; scale→1.2/100ms; y-50 + alpha0 1500ms sine.out
		var lsy := base_pos.y - 15.0 - auto_off
		label.position.y = lsy
		# PoC 标签从默认 scale 1.0 tween 到 1.2 (ts:432), 非自创 0.6 起跳
		var pop := create_tween()
		pop.tween_property(label, "scale", Vector2(1.2, 1.2), 0.1)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(label, "position:y", lsy - 50.0, 1.5).set_delay(0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(0.1)
		tw.chain().tween_callback(label.queue_free)


## 伤害飘字每帧: pop→hold→抛物飞行 (1:1 PoC ticker ts:343-354). el=已过秒数.
##   node_fl=飞行单元 (普通伤害=Label; 暴击伤害=含[图标+数字]的 HBoxContainer) → scale/位移/淡出整单元一起动。
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
	var py: float = jump_y * flight * 2.0 + 0.5 * 200.0 * flight * flight   # gravity 200
	node_fl.scale = Vector2(sc, sc)
	node_fl.position = base + Vector2(px, py)
	var op: float = 1.0 if el < fade_start else maxf(0.0, 1.0 - (el - fade_start) / (total_dur - fade_start))
	node_fl.modulate.a = op


## (已删 _spawn_hit_particles: 命中火花粒子=自创, PoC BattleScene 无任何命中粒子; 调用早先已移, 2026-06-11 复扫清死代码本体. _make_decay_curve 仍被合法 burst(3582) 用, 保留)


## W7 回合末 DoT tick (PoC BattleScene.tickDoTs:8078 1:1)
## DoT 对指定一队结算 (side-end 时对【对面】调用) — PoC tickDoTs 对 oppTeam
## 本侧 HoT 持续回血 (1:1 PoC processSideEnd own队 hot tick): 每个 hot buff 回 value HP。
##   duration 由 tick_buffs_duration(turn-begin)衰减, 此处只回血不动 duration。
func _tick_hots_for_team(team_side: String) -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("side", "") != team_side or not f.get("alive", false):
			continue
		var healed: int = 0
		for b in f.get("buffs", []):
			if b is Dictionary and b.get("type", "") == "hot" and int(b.get("duration", 0)) > 0:
				healed += int(b.get("value", 0))
		if healed > 0:
			healed = Buffs.fatigue_amt(f, healed)   # 决胜局疲惫: HoT 治疗 ×0.5
			var before: int = int(f.get("hp", 0))
			f["hp"] = mini(int(f.get("maxHp", 0)), before + healed)
			var got: int = int(f["hp"]) - before
			if got > 0:
				_spawn_float_text(i, got, "heal")
				_refresh_slot(i)
				battle_stats.record_heal(null, f, got)
		# bubbleStore 被动: 每回合从 store 回 healPct%(青🫧) + dmgPct%→随机敌 magic (1:1 PoC BattleScene:8037)
		var bp = f.get("passive", null)
		if bp is Dictionary and bp.get("type", "") == "bubbleStore" and int(f.get("bubbleStore", 0)) > 0:
			var heal_pct: int = int(bp.get("healPct", 25))
			var dmg_pct: int = int(bp.get("dmgPct", 0))
			var heal_amt: int = roundi(int(f.get("bubbleStore", 0)) * heal_pct / 100.0)
			var bb_heal: int = Buffs.fatigue_amt(f, heal_amt)   # 决胜疲惫
			var hr = Buffs.find(f, "healReduce")                # applyHeal 受 healReduce
			if hr != null and int(hr.get("value", 0)) > 0:
				bb_heal = roundi(bb_heal * (1.0 - hr.get("value", 0) / 100.0))
			var bb_before: int = int(f.get("hp", 0))
			f["hp"] = mini(int(f.get("maxHp", 0)), bb_before + bb_heal)
			f["bubbleStore"] = int(f.get("bubbleStore", 0)) - heal_amt   # store 按 healAmt 扣 (PoC:8044)
			var bb_actual: int = int(f["hp"]) - bb_before
			if bb_actual > 0:
				_spawn_bubble_text(i, bb_actual)   # 青🫧 bubble-num
				_refresh_slot(i)
				battle_stats.record_heal(null, f, bb_actual)
			if dmg_pct > 0:
				var dmg_amt: int = roundi(int(f.get("bubbleStore", 0)) * dmg_pct / 100.0)
				f["bubbleStore"] = int(f.get("bubbleStore", 0)) - dmg_amt
				if dmg_amt > 0:
					var bb_enemies: Array = []
					for j in range(fighters.size()):
						if fighters[j].get("side", "") != f.get("side", "") and fighters[j].get("alive", false):
							bb_enemies.append(j)
					if not bb_enemies.is_empty():
						var ej: int = bb_enemies[randi() % bb_enemies.size()]
						var et: Dictionary = fighters[ej]
						var is_crit_bb: bool = randf() < float(f.get("crit", 0.0))
						var crit_mult: float = Damage.calc_crit_mult(f) if is_crit_bb else 1.0
						var final_dmg: int = maxi(1, roundi(dmg_amt * Damage.calc_dmg_mult(Damage.calc_eff_mr(f, et)) * crit_mult))
						var was_alive_bb: bool = et.get("alive", false)
						var r_bb: Dictionary = Damage.apply_raw_damage(et, final_dmg, "magic")
						var shown_bb: int = int(r_bb["hpLoss"]) + int(r_bb["shieldAbs"])
						battle_stats.record_damage(f, et, shown_bb, "mag")
						_spawn_float_text(ej, shown_bb, "damage", "magic", is_crit_bb)
						_refresh_slot(ej)
						if was_alive_bb and not et.get("alive", false):
							await _play_death(ej)
			if int(f.get("bubbleStore", 0)) < 1:
				f["bubbleStore"] = 0


func _tick_dots_for_team(team_side: String) -> void:
	# 元素羁绊: DoT ×(1+boost), boost = 对面(施加 DoT 那队)最大 _synergyElemDmgBoost
	var elem_boost: float = 0.0
	for f in fighters:
		if f.get("side", "") != team_side:
			elem_boost = maxf(elem_boost, f.get("_synergyElemDmgBoost", 0.0))
	var any_visible_dot: bool = false   # 是否真有可见 DoT 飘字入队 → 决定末尾 0.8s settle 是否需要(无飘字则跳过)
	var max_stagger: float = 0.0   # 全队最长的 DoT 错峰序列 → 末尾统一等它跑完
	var _dot_dead: Array = []      # 本回合被 DoT 致死的 idx → 错峰飘完后【并行】播死亡 (不逐只串行)
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("side", "") != team_side or not f.get("alive", false) or f.get("_deathVfxDone", false):
			continue   # 跳过已死透(可能被on-hit保活)的龟: 死龟不该再吃DOT/重触发死亡 (源头修)
		var was_alive_dot: bool = f.get("alive", false)
		var dot_effects: Array = Dot.tick(f, elem_boost)   # 已按 burn→poison→bleed→curse 固定顺序排好
		# 统计立即记 (不随错峰): DoT 已扣完血, 统计按聚合值落 — 避免 stagger 影响面板准确性。
		for eff in dot_effects:
			# 统计桶按【真实伤害类型】分 (1:1 PoC statCat = dmgType): bleed→phy / curse→tru / burn,poison→mag,
			#   且 022真火把 burn 转真伤时 dmg_type=true → 这里也跟着算 tru (原按 cls 抠→真火被错记 mag).
			var dot_bucket: String = _stat_type(str(eff.get("dmg_type", "magic")))
			battle_stats.record_damage(eff.get("_src", null), f, int(eff["value"]), dot_bucket)
		# 同目标多条 DoT: 逐条错开飘字 (~0.13s/条, 像多段伤害 stagger) + 血条随每条逐段 step。
		#   HP 在 Dot.tick 已扣到终值; 这里纯显示 — 每条算它那一步的 hp_after (终值 + 它之后所有 DoT 的伤害和),
		#   血条逐条降而非一帧砸到底。固定顺序+错峰 → 干净有序不乱挤。
		var final_hp_dot: float = float(f.get("hp", 0))
		var this_stagger: float = float(maxi(0, dot_effects.size() - 1)) * 0.13   # 本目标这串 DoT 错峰总时长
		for k in range(dot_effects.size()):
			var eff: Dictionary = dot_effects[k]
			var v: int = int(eff["value"])
			var cls: String = eff.get("cls", "dot-dmg")
			var rest_dot: int = 0
			for m in range(k + 1, dot_effects.size()):
				rest_dot += int(dot_effects[m]["value"])
			var hp_after_dot: float = final_hp_dot + float(rest_dot)
			var step_delay: float = float(k) * 0.13   # 逐条错峰 ~0.13s (多段伤害 stagger 同款手感)
			# 统一走显示调度器: 每条 DoT 作为显示事件入队 (at=逐条错峰), 与同目标的其它来源(并段/投射等)
			#   共用一条有序队列 + 最小间隔 → 不再各自 create_timer 抢血条/塌一帧。死龟守卫由调度器统一处理。
			_enqueue_display(i, {"kind": "dot", "value": v, "cls": cls, "at": step_delay, "hp_after": hp_after_dot})
			any_visible_dot = true   # 确有 DoT 飘字入队
		max_stagger = maxf(max_stagger, this_stagger)
		if not f.get("alive", false):
			# DoT 致死: HP 已在 tick 扣到死。先立即记账(击杀), 收集 idx → 全队 DoT 飘完后【并行】播死亡 (多龟同回合连死不逐只串行卡)。
			if was_alive_dot and not dot_effects.is_empty():
				var dsrc = dot_effects[-1].get("_src", null)
				if dsrc != null:
					_award_and_record_kill(dsrc, f)
			if not _dot_dead.has(i):
				_dot_dead.append(i)
			battle_log.append_text("  [color=#ff6b6b]☠ %s 阵亡[/color]\n" % f.get("name", "?"))
	if max_stagger > 0.0:
		await get_tree().create_timer(max_stagger).timeout   # 等最长一串 DoT 错峰飘完
	if not _dot_dead.is_empty():
		# 死亡时机根治: 先等各致命那条 DoT 的血条 step (队列里) 显示完 (血条走到 0)。
		for _di in _dot_dead:
			await _await_display_drained(_di)
		# 并行播死亡: bare-call void 协程, 一起跑 → 多龟连死不串行 (死3只≈1.2s 不是 ~11s)。
		for _di in _dot_dead:
			_play_death(_di)
		await get_tree().create_timer(1.25).timeout   # 统一等最长一段死亡演出跑完 (≈1.2s deathHop)
	if any_visible_dot:
		await get_tree().create_timer(0.8).timeout   # 1:1 PoC side-end DoT tick 后 800ms (BattleScene.ts:7937) — 仅当真有可见 DoT 飘字才等, 无飘字跳过这 0.8s


## DoT 飘字 (按 cls 决定颜色: dot-dmg 灼烧蓝 / dot-poison 蓝 / dot-bleed 红 / dot-curse 白)
## Phaser visual_dispatcher.ts:59-62 1:1
func _spawn_dot_text(target_idx: int, amount: int, cls: String) -> void:
	var node: Node2D = slot_nodes[target_idx]
	var label := Label.new()
	label.text = "%d" % amount   # PoC ts:258 — dot-* 也剥前导 '-', 伤害跳字统一无符号
	# 1:1 PoC: DoT 伤害数字也在龟身中心冒 (非脚底), 同 _spawn_float_text 修正
	var av_dt: Sprite2D = node.get_meta("avatar", null)
	var center_y_dt: float = (av_dt.position.y if av_dt != null else -50.0)
	var base_pos := Vector2(-30, center_y_dt - _float_row_offset(target_idx, "dot", "magic"))
	label.position = base_pos
	label.add_theme_font_size_override("font_size", VisualConstants.base_size_of(cls))
	label.add_theme_color_override("font_color", VisualConstants.color_of(cls))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	node.add_child(label)
	# DoT tick 走伤害弹跳路径 (PoC ts:419-422: dot-poison/bleed/curse isDmg=true → pop+抛物)
	label.scale = Vector2(0.01, 0.01)
	var pop_size := 1.6 if amount < 20 else (1.8 if amount < 60 else (2.2 if amount < 150 else 2.5))
	var dir := -1.0 if node.global_position.x < 640.0 else 1.0
	var jump_x := dir * (12.0 + randf() * 14.0)
	var jump_y := -(22.0 + randf() * 10.0)
	var total_dur := 0.8       # holdEnd0.15 + flight0.65
	var fade_start := 0.45     # holdEnd0.15 + 0.3
	var tw := create_tween()
	tw.tween_method(_dmg_float_step.bind(label, base_pos, jump_x, jump_y, 0.15, 0.7, pop_size, total_dur, fade_start), 0.0, total_dur, total_dur)
	tw.tween_callback(label.queue_free)
	Audio.play_sfx_for_cls(cls)


## W7 装备 onTurnBegin 触发 — 单个 fighter (在它自己 turn-begin 调, PoC fireOnTurnBegin per-actor)
func _fire_turn_begin_equip_for(idx: int) -> void:
	var f: Dictionary = fighters[idx]
	if not f.get("alive", false):
		return
	var eqs: Array = f.get("_equipped_ids", [])
	for eq_id in eqs:
		var procs: Array = EquipmentRuntime.on_turn_begin(f, eq_id, fighters)
		for p in procs:
			var t_idx: int = p["target_idx"]
			var v: int = p.get("value", 0)
			var label: String = p.get("label", "+%d" % v)
			_spawn_passive_text(t_idx, label)
			_refresh_slot(t_idx)


## 泡泡龟 bubbleStore 回血飘字 (青 #4cc9f0 "+N🫧", bubble-num cls, label 路径) — 1:1 PoC ts:8046
func _spawn_bubble_text(target_idx: int, amount: int) -> void:
	var node: Node2D = slot_nodes[target_idx]
	var av_bb: Sprite2D = node.get_meta("avatar", null)
	var cy_bb: float = (av_bb.position.y if av_bb != null else -50.0)
	var auto_off := _float_auto_offset(target_idx)
	var label := Label.new()
	label.text = "+%d🫧" % amount
	var lsy := cy_bb - _float_row_offset(target_idx, "heal", "magic") - 15.0 - auto_off
	label.position = Vector2(-30, lsy)
	label.add_theme_font_size_override("font_size", VisualConstants.base_size_of("bubble-num"))
	label.add_theme_color_override("font_color", VisualConstants.color_of("bubble-num"))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	node.add_child(label)
	var pop := create_tween()
	pop.tween_property(label, "scale", Vector2(1.2, 1.2), 0.1)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", lsy - 50.0, 1.5).set_delay(0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(0.1)
	tw.chain().tween_callback(label.queue_free)


## 简易 passive 飘字 (绿色 + size 16, 跟 VisualConstants passive-num cls 同色)
func _spawn_passive_text(target_idx: int, text: String, color_hex: String = "") -> void:
	var node: Node2D = slot_nodes[target_idx]
	# 1:1 PoC spawnFloatingPassive(BattleScene.ts:5680): 龟身中心上方 50px 冒, 升到 -95(升45px), 800ms cubic.out。
	#   原 Godot (-40, +30) = 脚底【下方】30px = 严重偏低(~130px)。
	var av_pt: Sprite2D = node.get_meta("avatar", null)
	var cy_pt: float = (av_pt.position.y if av_pt != null else -50.0)
	var label := Label.new()
	label.text = text
	label.position = Vector2(-40, cy_pt - 50.0)
	label.add_theme_font_size_override("font_size", VisualConstants.base_size_of("passive-num"))
	label.add_theme_color_override("font_color", Color(color_hex) if color_hex != "" else VisualConstants.color_of("passive-num"))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	node.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", cy_pt - 95.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)


## 简单的 1→0 衰减曲线 (粒子 scale 用)
func _make_decay_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1.0))
	c.add_point(Vector2(1, 0.0))
	return c


## 死亡碎屑粒子纹理 (缓存): 16px 软白圆点 — 实心核 r5 + 软边到 r8. CPUParticles 无纹理=亚像素看不见, 故给它一个.
##   对齐 PoC __DEFAULT (~16px 白块) × scale0.7 ≈ 11px 碎屑. color 由粒子 tint 染灰.
var _debris_tex_cache: ImageTexture = null
func _debris_tex() -> ImageTexture:
	if _debris_tex_cache != null:
		return _debris_tex_cache
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ctr := Vector2(8.0, 8.0)
	for y in range(16):
		for x in range(16):
			var dd := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(ctr)
			var a := clampf(1.0 - (dd - 5.0) / 3.0, 0.0, 1.0)   # 实心核 r5 → 软边淡出到 r8
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	_debris_tex_cache = ImageTexture.create_from_image(img)
	return _debris_tex_cache


## 暴击计数 (成就 crit_100 用). ⚠ PoC 普通暴击命中【不飘任何"暴击!"文字】—— 暴击只靠 数字×1.2放大 + 暴击音效
##   (见 VisualConstants.size_by_amount is_crit×1.2 / cls_for crit-magic·crit-dmg·crit-true). 全仓 PoC 无此飘字.
##   原 _spawn_crit_label 飘 "💥 暴击!" label = 自创(2026-06-11 用户抓出), 已删; 仅保留计数. crit-label 类PoC只给事件文字(猎杀/复活).
var _battle_crits: int = 0   # 本局暴击次数 (成就 crit_100 用; 新 BattleScene 实例每局归 0)
func _spawn_crit_label(_target_idx: int) -> void:
	_battle_crits += 1


## hit-stop: Engine.time_scale 微停 (Phaser juiceHitStop 同款)
var _hitstop_gen: int = 0
func _play_hit_stop(ms: int) -> void:
	# 多段暴击会重叠调用 → 用 gen 让"最新那个"负责恢复, 否则早到的 restore 会把后面的 hit-stop 提前加速。
	_hitstop_gen += 1
	var gen := _hitstop_gen
	Engine.time_scale = 0.15
	# 用真实时间 (不受 time_scale 影响) 等待
	await get_tree().create_timer(ms / 1000.0, false, false, true).timeout
	if gen == _hitstop_gen:
		Engine.time_scale = 1.0


## ── 战斗 ENVELOP (1:1 PoC Scale.ENVELOP): 世界 cover 铺满窗口, HUD 边缘锚定不裁 ──
##   PoC 进战斗切 ENVELOP(整画布等比放大铺满、裁掉超出边), 退出切回 FIT。
##   Godot 做法: content_scale_aspect=EXPAND(视口随窗口比例扩展, 消 letterbox 黑边) +
##   相机 cover-zoom(世界 bg+龟 等比放大到铺满逻辑视口、裁另一维)。HUD 在 CanvasLayer 不随相机,
##   底部行动面板已 anchor_bottom=1.0、右侧 HUD 锚真实右边缘 → 跟随真实边缘不被裁 (= PoC DOM HUD)。
func _enter_battle_envelop() -> void:
	var win := get_window()
	if win == null:
		return
	_prev_scale_aspect = win.content_scale_aspect
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if not win.size_changed.is_connected(_update_battle_cover):
		win.size_changed.connect(_update_battle_cover)
	_update_battle_cover()


## 相机 cover-zoom: 世界(VIEW_W×VIEW_H)放大到铺满当前逻辑视口 (取较大缩放 → 铺满、裁另一维, 居中)。
##   + 把右锚 HUD 重排到真实右边缘 (EXPAND 下宽 > VIEW_W 时, 否则会内缩留空 = 非 16:9 屏 HUD 不贴边)。
func _update_battle_cover() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if is_instance_valid(battle_camera):
		var z: float = maxf(vp.x / float(VIEW_W), vp.y / float(VIEW_H))
		z = maxf(1.0, z)   # 永不缩小 (16:9 = 1.0 = 原样); 只放大铺满非 16:9
		battle_camera.zoom = Vector2(z, z)
	for e in _right_hud:
		var nd = e["node"]
		if is_instance_valid(nd):
			nd.position.x = vp.x - float(e["margin"])   # margin = 节点左沿距真实右边缘


## 注册一个右锚 HUD 节点 (margin = 左沿距右边缘像素), 立即按当前视口宽定位 + 存表供 resize 重排。
func _anchor_hud_right(node: Control, margin: float) -> void:
	if node == null:
		return
	_right_hud.append({"node": node, "margin": margin})
	node.position.x = get_viewport().get_visible_rect().size.x - margin


## 安全网: hit-stop 未恢复就切场景(如击杀同帧战斗结束, await 中途节点被释放) → Engine.time_scale
##   残留 0.15 会让之后整个游戏 slow-mo。离场强制复位。+ 还原 content_scale_aspect(ENVELOP→FIT)。
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	var win := get_window()
	if win != null:
		# 断开 cover-zoom 的 size_changed 连接 — 否则离场后窗口 resize 仍触发本(已弃)场景的相机重排 = 画布异常
		if win.size_changed.is_connected(_update_battle_cover):
			win.size_changed.disconnect(_update_battle_cover)
		if _prev_scale_aspect >= 0:
			win.content_scale_aspect = _prev_scale_aspect   # 还原进战斗前的 aspect


## 震屏: Camera2D offset 抖一抖 (Phaser cameras.main.shake 同款)
##   抖的是相机 offset (不动 slots_root / 不动 camera.position), 故与技能推镜 (zoom/pan position) 并存不冲突。
func _play_screen_shake(duration_s: float, strength_px: float) -> void:
	if not is_instance_valid(battle_camera):
		return
	var steps: int = 8
	for i in range(steps):
		var dx := randf_range(-strength_px, strength_px)
		var dy := randf_range(-strength_px * 0.5, strength_px * 0.5)
		battle_camera.offset = Vector2(dx, dy)
		await get_tree().create_timer(duration_s / steps).timeout
	battle_camera.offset = Vector2.ZERO


## ── 全屏 cut-in 闪屏 (1:1 PoC KOF cut-in: 全屏色矩形 ADD 混合 alpha 脉冲) ──
##   在 fx_layer (CanvasLayer) → 不随相机 zoom/pan, 永远盖满 1280×720。
##   alphas/durs 等长: 逐段 tween color.a (ADD 混合让闪屏发亮)。chiwave: [.45,.55,0]/[.12,.12,.26].
func _screen_cutin_flash(base_color: Color, alphas: Array, durs: Array) -> void:
	if not is_instance_valid(fx_layer) or alphas.is_empty():
		return
	var rect := ColorRect.new()
	rect.color = Color(base_color.r, base_color.g, base_color.b, 0.0)
	rect.size = get_viewport().get_visible_rect().size   # 盖满真实视口 (ENVELOP)
	rect.position = Vector2.ZERO
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ADD 混合 (1:1 PoC setBlendMode(ADD)): 闪屏叠加变亮, 不挡死画面
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rect.material = mat
	fx_layer.add_child(rect)
	var tw := rect.create_tween()
	for i in range(alphas.size()):
		var dur: float = float(durs[i]) if i < durs.size() else 0.15
		tw.tween_property(rect, "color:a", float(alphas[i]), dur)
	tw.tween_callback(rect.queue_free)


## ── 技能推镜: 相机拉近 + pan (1:1 PoC cam.zoomTo + cam.pan, Sine 缓动) ──
## focus_mode "origin": 焦点保持在原屏幕位置不动 (PoC basicChiWave 原地放大,
##   panC = 屏心 + (焦点-屏心)×(1-1/zoom), skill-handlers.ts:1003-1006)。
## focus_mode "center": 焦点 pan 到画面正中 (PoC cyberBeam cam.pan(midX,midY), ts:3207-3208)。
## Camera2D limit_* 已设世界边界 → zoom>1 pan 到边排时自动 clamp 在 bg 内, 绝不露黑边 (同 PoC setBounds)。
func _camera_focus(focus: Vector2, zoom_factor: float, dur: float, focus_mode: String = "origin", ease_type: int = Tween.EASE_IN_OUT) -> void:
	if not is_instance_valid(battle_camera):
		return
	var screen_center := Vector2(VIEW_W / 2.0, VIEW_H / 2.0)
	var pan_to: Vector2
	if focus_mode == "center":
		pan_to = focus
	else:
		pan_to = screen_center + (focus - screen_center) * (1.0 - 1.0 / zoom_factor)
	var tw := battle_camera.create_tween()
	tw.set_parallel(true)
	tw.tween_property(battle_camera, "zoom", Vector2(zoom_factor, zoom_factor), dur).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	tw.tween_property(battle_camera, "position", pan_to, dur).set_trans(Tween.TRANS_SINE).set_ease(ease_type)


## 相机复位: zoom→1, position→屏心 (1:1 PoC cam.zoomTo(1.0)+cam.pan(width/2,height/2))
func _camera_reset(dur: float, ease_type: int = Tween.EASE_IN_OUT) -> void:
	if not is_instance_valid(battle_camera):
		return
	var tw := battle_camera.create_tween()
	tw.set_parallel(true)
	tw.tween_property(battle_camera, "zoom", Vector2.ONE, dur).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	tw.tween_property(battle_camera, "position", Vector2(VIEW_W / 2.0, VIEW_H / 2.0), dur).set_trans(Tween.TRANS_SINE).set_ease(ease_type)


## hp_override / shield_override >= 0: 血条显示给定中间值 (多段技能逐段下降, 见 _play_damage_segments).
func _refresh_slot(idx: int, hp_override := -1.0, shield_override := -1.0) -> void:
	var f: Dictionary = fighters[idx]
	var node: Node2D = slot_nodes[idx]
	# 龟蛋是真单位 → 它每被打一次, 把 fighter.hp 写回 GameState.egg_hp[side] (跨上/下/终极累计的权威账本)。
	if f.get("_isEgg", false):
		_sync_egg_hp(f)
	# HP 条全交给 HpBar: 玻璃管/逐行渐变/100·500刻度/多段盾(白金青紫)/受击红trail/60ms白闪/横抖 (1:1 turtle-hud)
	if node.has_meta("hp_bar"):
		var hp_bar: HpBar = node.get_meta("hp_bar")
		if is_instance_valid(hp_bar):
			# 多源逐段修: 伤害下降由 _spawn_float_text→_step_display_hp 逐飘字 step 驱动 (chokepoint)。
			#   若此处是【无 override 的整槽刷新】且血条当前显示值仍高于真实 hp(一段降势进行中: 多源伤害的
			#   后续飘字还没飘到), 不要把血条一口气砸到真实终值 — 改成显示【当前定格值】, 让逐飘字 step 走完。
			#   (治疗/上调 real_hp>=displayed → 不命中此分支, 照常即时刷上去; 单源命中 step 已到终值 → 无差异。)
			var eff_override: float = hp_override
			if hp_override < 0.0:
				var disp: float = hp_bar.displayed_hp()
				if disp >= 0.0 and disp > float(f.get("hp", 0)):
					eff_override = disp
			hp_bar.update_state(f, eff_override, shield_override)
	if node.has_meta("energy_fill"):
		_update_energy_bar(node, f)
	if node.has_meta("staff_mana_bars"):
		_update_staff_mana_bars(node, f)   # 法器法力条 (≠龟能)
	if node.has_meta("incubator_bar"):
		_update_incubator_bar(node, f)     # 孵化器孵化进度条 (死亡加进度后随刷新链更新)

	# HP 数字滚动 (自创隐藏文字, 仍维护供潜在显示) — 不影响血条视觉
	var hp_text: Label = node.get_meta("hp_text")
	var hp_text_meta_key := "hp_displayed"
	var displayed: int = node.get_meta(hp_text_meta_key) if node.has_meta(hp_text_meta_key) else int(f["maxHp"])
	var target_hp: int = int(f["hp"])
	var max_hp: int = int(f["maxHp"])
	if displayed != target_hp:
		var roll_tween := create_tween()
		roll_tween.tween_method(
			func(v: float):
				var iv: int = roundi(v)
				hp_text.text = "%d / %d" % [iv, max_hp]
				node.set_meta(hp_text_meta_key, iv),
			float(displayed), float(target_hp), 0.35
		).set_ease(Tween.EASE_OUT)
	else:
		hp_text.text = "%d / %d" % [target_hp, max_hp]
		node.set_meta(hp_text_meta_key, target_hp)
	# 治疗顺带转盾可见化 (饰品溢出转盾 / 潮汐治疗留盾, _heal_to 静默累积): 刷新时一次性飘"+N盾"+盾光 (原静默, 玩家只见回血不见转盾) — 需F5
	var heal_sh_gain: int = int(f.get("_heal_shield_gain", 0))
	if heal_sh_gain > 0:
		f["_heal_shield_gain"] = 0
		_spawn_float_text(idx, heal_sh_gain, "shield")
		_play_shield_glow(idx)
	_sync_stun_overhead(idx)   # 头顶眩晕星星: 按 stun buff 状态增删 (施加/刷新时显示, 解晕刷新时移除)


# 击杀记录 + 击杀币奖励 (1:1 PoC :1557). 包住 battle_stats.record_kill, 统一在此发币。
#   我方击杀敌方: +25 (Boss +30) 进 battle_coins; 野生敌方击杀我方: AI +25 (自带守卫)。
#   无 killer(环境/DoT 无源) 或同侧 → 不发击杀币 (阵亡补偿走 _play_death)。每个 victim 只发一次。
func _award_and_record_kill(killer, victim) -> void:
	battle_stats.record_kill(killer, victim)
	if not (killer is Dictionary) or not (victim is Dictionary):
		return
	var vs: String = victim.get("side", "")
	if killer.get("side", "") == vs or victim.get("_killRewardGiven", false):
		return
	victim["_killRewardGiven"] = true
	if vs == "right":
		GameState.grant_wealth_coin("left", 30 if victim.get("_isBoss", false) else 25)
	elif vs == "left":
		GameState.ai_gain_coins(25)


## 唤灵学会: 召唤一只亡魂 (继承属性, 死后循环×0.9). src=死亡单位; cycles=剩余循环次数。
## 黑礁猎团: 给某侧(若激活猎杀)指定一个敌方猎物(最高 maxHp 存活非蛋) — 标 _huntTarget + _huntDmgBoost(伤害增幅)。
func _hunt_pick_for_side(side: String) -> void:
	var boost: float = 0.0
	for f in fighters:
		if f.get("side", "") == side and int(f.get("_huntTier", 0)) >= 1:
			boost = float(f.get("_huntDmgBoostPct", 0.0))
			break
	if boost <= 0.0:
		return
	var enemy_side: String = "right" if side == "left" else "left"
	for f in fighters:
		if f.get("side", "") == enemy_side:
			f.erase("_huntTarget")
			f.erase("_huntDmgBoost")
	var best = null
	for f in fighters:
		if f.get("side", "") == enemy_side and f.get("alive", false) and not f.get("_isEgg", false):
			if best == null or int(f.get("maxHp", 0)) > int(best.get("maxHp", 0)):
				best = f
	if best != null:
		best["_huntTarget"] = true
		best["_huntDmgBoost"] = boost


func _spawn_undead_spirit(src: Dictionary, atk: int, hp: int, cycles: int) -> void:
	var spirit := {
		"id": "undead_spirit", "name": "亡魂", "emoji": "👻",
		"img": "", "sprite": null,
		"side": str(src.get("side", "left")),
		"_level": 1, "_maxEnergy": 0, "_energy": 0,
		"hp": hp, "maxHp": hp, "shield": 0,
		"baseAtk": atk, "baseDef": 0, "baseMr": 0,
		"atk": atk, "def": 0, "mr": 0, "crit": 0.0,
		"armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
		"passive": null, "passiveUsedThisTurn": false,
		"skills": [{"name": "亡魂爪", "type": "physical", "hits": 1, "power": 0, "pierce": 0, "atkScale": 1.0, "cd": 0, "cdLeft": 0, "energyCost": 0, "icon": "👻", "brief": "", "detail": ""}],
		"_passiveSkills": [],
		"alive": true, "buffs": [], "tags": [],
		"_position": "front", "_slotKey": str(src.get("_slotKey", "front-1")),
		"_statsDirty": false, "equipment": [],
		"_isSummon": true, "_isUndead": true,
		"_undeadBaseAtk": atk, "_undeadBaseHp": hp, "_undeadCyclesLeft": cycles,
	}
	var sidx := _spawn_combatant(spirit)
	if sidx >= 0:
		_spawn_passive_text(sidx, "👻 亡魂")
		_play_vfx_at_slot("ghost-storm", sidx, 1.2)   # 羁绊·唤灵学会: 亡魂登场处幽灵风暴 (复用 ghost-storm 帧, 无新资源)


func _play_death(idx: int) -> void:
	# 龟蛋摧毁走专属碎裂演出 (碎裂放大+淡出+摧毁横幅), 不走龟的死亡 hop/倾倒/灰度; 且 hp 写回账本。
	if idx >= 0 and idx < fighters.size() and fighters[idx].get("_isEgg", false):
		_sync_egg_hp(fighters[idx])
		await _play_egg_destroy(idx)
		return
	# 防死亡演出重播: 死后几回合残留DOT/诅咒/环境事件再触发 _play_death → 死亡特效+音效重复出现 (用户报)。
	#   复活时 _revive_node 清 _deathVfxDone → 复活后再死能正常重播。
	if idx >= 0 and idx < fighters.size():
		if fighters[idx].get("_deathVfxDone", false):
			if OS.has_environment("DIAG_DEATH"):   # 诊断: 打调用栈 → 定位哪个生成器把效果打到死龟 (源头修用)
				print("[DEATH-DIAG] %s 残留再触发 ← %s" % [fighters[idx].get("name", "?"), str(get_stack())])
			elif OS.has_environment("DUALLANE_SMOKE"):   # 仅冒烟时打计数日志; 正常 F5 静默(守卫照常生效)
				print("[DEATH] 跳过死亡演出重播: %s (已死, 残留效果再触发)" % fighters[idx].get("name", "?"))
			return
		# 死亡时机根治 (兜底保证): 播死亡演出前, 把血条强制刷到真实终值 (击杀=0) — 触发 old→0 的红 trail 掉血动画。
		#   正常路已 _await_display_drained 把致命 step 显示完(血条已到 0, 此刷无差异); 但若极端排队超时放行,
		#   这里保证死亡那刻血条一定在 0 / 真实值, 绝不停在半血就消失。在 _deathVfxDone 置位前刷 (否则飘字/刷新被尸体守卫挡)。
		#   用 hp_override=真实 hp 强制下刷 (无 override 的 _refresh_slot 在"显示>真实"时会保留定格值, 不会砸到 0)。
		_refresh_slot(idx, float(fighters[idx].get("hp", 0)))
		fighters[idx]["_deathVfxDone"] = true
		# 显示调度: 目标死透 → 作废其待显队列 + bump epoch, 落在死亡之后的迟到事件不再拿旧 hp_after 回刷尸体血条 (#8).
		_bump_disp_epoch(idx)
	# 阵亡补偿 +20 (1:1 PoC :8569): 我方阵亡→我方钱包, 野生敌方阵亡→AI(自带守卫). 每死只给一次。
	var df: Dictionary = fighters[idx]
	if not df.get("_deathCompGiven", false):
		df["_deathCompGiven"] = true
		if df.get("side", "") == "left":
			GameState.grant_wealth_coin("left", 20)
		else:
			GameState.ai_gain_coins(20)
	Audio.play_sfx("defeat", 0.5, 1.0, 0.06)   # 1:1 PoC killView vol 0.5 (BattleScene.ts:8565) — 原0.9近两倍→死亡音突兀像"凭空多出"
	# B7 ghostEnhancedCurse 死亡怨灵: 死亡时诅咒全体存活敌人 5回合 (1:1 PoC:4497-4509)
	var _has_ghost_curse := false
	for _ps in df.get("_passiveSkills", []):
		if _ps is Dictionary and _ps.get("type", "") == "ghostEnhancedCurse":
			_has_ghost_curse = true
	if _has_ghost_curse:
		for e in fighters:
			if e.get("side", "") != df.get("side", "") and e.get("alive", false):
				(e["buffs"] as Array).append({"type": "curse", "value": roundi(e.get("maxHp", 0) * 0.05), "duration": 6})
		battle_log.append_text("[color=#9b59b6]👻 %s 死亡怨灵! 敌方全体诅咒5回合[/color]\n" % df.get("name", "?"))
	_incubator_on_death(df)   # 孵化器: 任意死亡 → 持有者+进度 (敌死+10/我死+15)
	# 唤灵学会[亡灵]: 友军死亡召唤亡魂(继承属性), 亡魂死再召更弱的(×0.9, 有次数上限) — 见 _spawn_undead_spirit
	if not df.get("_isEgg", false):
		var u_atk: float = 0.0
		var u_hp: float = 0.0
		var u_cyc: int = -1
		if df.get("_isUndead", false):
			if int(df.get("_undeadCyclesLeft", 0)) > 0:
				u_atk = float(df.get("_undeadBaseAtk", 0)) * 0.9
				u_hp = float(df.get("_undeadBaseHp", 0)) * 0.9
				u_cyc = int(df.get("_undeadCyclesLeft", 0)) - 1
		elif float(df.get("_undeadPct", 0.0)) > 0.0:
			u_atk = float(df.get("atk", 0)) * float(df.get("_undeadPct", 0.0))
			u_hp = float(df.get("maxHp", 0)) * float(df.get("_undeadPct", 0.0))
			u_cyc = int(df.get("_undeadCycles", 0))
		if u_cyc >= 0 and u_hp >= 1.0:
			_spawn_undead_spirit(df, roundi(u_atk), roundi(u_hp), u_cyc)
	# 黑礁猎团: 猎物被杀 → 猎方(对侧)全队永久 +_huntKillAtk 攻 + 重选猎物
	if df.get("_huntTarget", false):
		var hunt_side: String = "right" if df.get("side", "") == "left" else "left"
		var hunt_changed: bool = false
		for hf in fighters:
			if hf.get("side", "") == hunt_side and int(hf.get("_huntTier", 0)) >= 1 and hf.get("alive", false):
				hf["baseAtk"] = int(hf.get("baseAtk", 0)) + int(hf.get("_huntKillAtk", 14))
				hunt_changed = true
		if hunt_changed:
			StatsRecalc.recalc_all(fighters)
		_hunt_pick_for_side(hunt_side)
	# 圣甲议会 5档: 敌方单位阵亡 → 本方圣盾携带者获 30%×亡者maxHp 圣光护盾
	var holy_side: String = "right" if df.get("side", "") == "left" else "left"
	var holy_amt5: int = roundi(int(df.get("maxHp", 0)) * 0.3)
	if holy_amt5 > 0:
		for hf in fighters:
			if hf.get("side", "") == holy_side and hf.get("alive", false) and hf.get("_holyShield", false) and int(hf.get("_holyTier", 0)) >= 2:
				var holy5_add: int = Buffs.grant_shield(hf, holy_amt5)
				if holy5_add > 0:
					hf["_holyShieldVal"] = int(hf.get("_holyShieldVal", 0)) + holy5_add   # 血条圣盾段(白黄亮)记账
					# 圣甲5档 敌亡转盾可见化: 携带者处飘金白"+N盾" + 圣光盾光 (圣盾=白黄亮, 区别普通蓝盾; 原静默) — 需F5
					var holy5_i: int = fighters.find(hf)
					if holy5_i >= 0:
						_spawn_passive_text(holy5_i, "+%d 盾" % holy5_add, _HOLY_SHIELD_HEX)
						_play_shield_glow(holy5_i, _HOLY_SHIELD_COLOR)
						_refresh_slot(holy5_i)
	# 二阶段装备 on_death: 035齿轮(携带者死→给币) / 052左轮(敌死→对面装弹+1)
	# 奇械[深海工坊] 死亡产装备 (规格#544): 我方(左)统领/小将阵亡(非蛋/非召唤/非中立) → 累计+1,
	#   该侧每件激活奇械各产一件 cost=累计数(封顶5费)装备, 永久进背包(GameState.bench_inventory); 每档一局仅一次。
	_gadget_on_left_unit_death(df)
	var _p2death: Dictionary = Phase2EquipRuntime.on_death(df, fighters)
	# V2-TODO 阶段2/6: 黄铜齿轮死亡产币已删 (局内无经济); 035 效果待重定. _p2death.coins 仍作下方齿轮迸溅VFX 的触发信号
	var node: Node2D = slot_nodes[idx]
	var avatar: Sprite2D = node.get_meta("avatar", null)
	var hud_d = node.get_meta("hud", null)
	var shadow_d = node.get_meta("shadow", null)
	var drop_dir: float = -1.0 if df.get("side", "left") == "left" else 1.0
	# 035 黄铜齿轮: 携带者死亡散落齿轮 → 金色齿轮/金币迸溅 (有齿轮才迸; coins>0 等价 _p2Gears>0)
	if int(_p2death.get("coins", 0)) > 0:
		_play_gear_burst(node, avatar.position if avatar != null else Vector2(0, -40))
	# 死亡短慢镜 (1:1 PoC killView juiceHitStop(120), ts:8603)
	_play_hit_stop(120)
	# 死亡碎裂粒子 (1:1 PoC killView ts:8599-8602): 18 灰白碎屑爆开, lifespan420 speed60-210 scale0.7→0.
	#   普通混合(非ADD — PoC death particles 未指定 blendMode, 区别于技能 VFX 的发光 ADD); tint 灰白(0xcfd6e0/9aa3b5/fff).
	var debris := CPUParticles2D.new()
	debris.position = avatar.position if avatar != null else Vector2(0, -40)
	debris.emitting = true
	debris.one_shot = true
	debris.amount = 18
	debris.lifetime = 0.42
	debris.explosiveness = 1.0
	debris.direction = Vector2(0, -1)
	debris.spread = 180.0                 # 全方向爆
	debris.gravity = Vector2.ZERO
	debris.initial_velocity_min = 60.0
	debris.initial_velocity_max = 210.0
	debris.scale_amount_min = 0.7
	debris.scale_amount_max = 0.7
	debris.scale_amount_curve = _make_decay_curve()   # 0.7 → 0
	debris.color = Color(0.81, 0.84, 0.88)            # 浅灰白 (PoC tint 0xcfd6e0)
	debris.texture = _debris_tex()                    # 无纹理时 CPUParticles=亚像素点(看不见) → 给 16px 软白块 (对齐 PoC __DEFAULT×0.7≈11px)
	debris.z_index = 40
	node.add_child(debris)
	get_tree().create_timer(0.9).timeout.connect(debris.queue_free)
	# deathHop 1:1 JS scene.css:95-129 / PoC killView ts:8618-8632 (四段共 1200ms, 身体 hop+倾倒, HUD 只淡不转):
	#   ① 144ms 跳起+抬8+后仰 -8° (sine.out)
	#   ② 252ms 落地俯卧 +14 + 倾倒 ∓15° (cubic.in) + 灰度压暗(setTint 0x808080)
	#   ③ 504ms 保持俯卧
	#   ④ 300ms 淡到 alpha 0 (整体消失, scene.css:83 .dead{opacity:0})
	# 1:1 PoC killView(ts:8607-8643): 死亡演出只动【精灵本体 view.sprite】(hop/倾倒/灰度/末段300ms淡出);
	#   影子 + HUD 是【另一条 tween】原地全程 1200ms 淡出 (targets:[shadow,hpBar…] alpha0 dur1200), 影子【不动】。
	#   (原误把整段动 node → 影子是 node 子级跟着飞起+倾倒 + 只在末300ms随node淡 = 与 PoC 不符 → 改动 avatar。)
	var avatar_home: Vector2 = avatar.get_meta("home", avatar.position) if avatar != null else Vector2.ZERO
	var tw := create_tween()
	if avatar != null:
		tw.tween_property(avatar, "position", avatar_home + Vector2(drop_dir * 10.0, -8.0), 0.144).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(avatar, "rotation", deg_to_rad(-8.0 * drop_dir), 0.144).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(avatar, "position", avatar_home + Vector2(drop_dir * 14.0, 0.0), 0.252).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(avatar, "rotation", deg_to_rad(-15.0 * drop_dir), 0.252).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(avatar, "modulate", Color(0.5, 0.5, 0.5, avatar.modulate.a), 0.252)   # ② 灰度压暗
		tw.tween_interval(0.504)                                                                            # ③ 保持俯卧
		tw.tween_property(avatar, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD)                        # ④ 末段300ms 本体淡出
	else:
		tw.tween_interval(1.2)   # 兜底: 无 avatar 仍占 1200ms (防空 tween)
	# 影子 + HUD: 原地全程 1200ms 淡出 (与本体演出并行, 影子不随 hop 移动 → 接地)
	var fade := create_tween().set_parallel(true)
	if shadow_d != null and is_instance_valid(shadow_d):
		fade.tween_property(shadow_d, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_QUAD)
	if hud_d != null:
		fade.tween_property(hud_d, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_QUAD)
	await tw.finished


# ─── HUD / 日志 ───────────────────────────────────────────────

func _set_title(text: String) -> void:
	if title_label:
		title_label.text = text


# ── 顶部回合进度线 (1:1 PoC BattleTopRow timeline + BattleScene.ts:546-558 数据模型) ──
var _timeline_holder: CenterContainer = null
var _cur_side: String = "left"

func _ensure_timeline() -> void:
	if _timeline_holder != null and is_instance_valid(_timeline_holder):
		return
	var topbar := get_node_or_null("UI/TopBar")
	if topbar == null:
		return
	var holder := CenterContainer.new()
	holder.name = "TurnTimeline"
	holder.anchor_left = 0.0; holder.anchor_right = 1.0
	holder.offset_top = 50.0; holder.offset_bottom = 126.0   # 在标题pill(y8-50)下方, 溢出 TopBar 不裁
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topbar.add_child(holder)
	_timeline_holder = holder


## 5-window 回合进度线 (当前±2). side: 当前行动阵营 (染当前节点 side pill).
func _update_turn_timeline(side: String = "") -> void:
	if side != "":
		_cur_side = side
	_ensure_timeline()
	if _timeline_holder == null:
		return
	for c in _timeline_holder.get_children():
		c.queue_free()
	# 数据模型 1:1 PoC BattleScene.ts:546-558: 开局equip + 每回合 event(3/6/9/12)/shop(4/8/12)/normal
	var nodes: Array = [{"round": 0, "type": "equip"}]
	var cur_idx := 1
	for t in range(1, turn + 6):
		if t == 3 or t == 6 or t == 9 or t == 12:
			nodes.append({"round": t, "type": "event"})
		if (t == 4 or t == 8 or t == 12) and GameState.mode != "duallane":
			nodes.append({"round": t, "type": "shop"})   # 双路整备商店常驻+每回合换货(云顶式) → 不标特定商店回合 (用户 2026-06-18)
		nodes.append({"round": t, "type": "normal"})
		if t == turn:
			cur_idx = nodes.size() - 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for offset in range(-2, 3):
		var i := cur_idx + offset
		if i < 0 or i >= nodes.size():
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(52, 0)
			row.add_child(spacer)
			continue
		var pos := "current" if offset == 0 else ("past" if offset < 0 else "future")
		row.add_child(_make_timeline_node(nodes[i], pos))
	_timeline_holder.add_child(row)


func _make_timeline_node(node: Dictionary, pos: String) -> Control:
	var ntype := str(node.get("type", "normal"))
	var rnd := int(node.get("round", 0))
	var is_cur := pos == "current"
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size = Vector2(52, 0)
	if is_cur:
		var pin := Label.new()
		pin.text = "▼"
		pin.add_theme_font_size_override("font_size", 13)
		pin.add_theme_color_override("font_color", Color("#ffd86b"))
		pin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(pin)
	# 圆点
	var dot_size := 52 if is_cur else 40
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(dot_size, dot_size)
	var dsb := StyleBoxFlat.new()
	dsb.set_corner_radius_all(dot_size / 2)
	dsb.set_border_width_all(2)
	dsb.content_margin_left = 0; dsb.content_margin_right = 0
	dsb.content_margin_top = 0; dsb.content_margin_bottom = 0
	match ntype:
		"event": dsb.bg_color = Color("#ffb01f"); dsb.border_color = Color("#ffe066")
		"shop": dsb.bg_color = Color("#3a9abf"); dsb.border_color = Color("#aee0ff")
		"equip": dsb.bg_color = Color("#3f9a3a"); dsb.border_color = Color("#c6f2a8")
		_: dsb.bg_color = Color("#8a93a3"); dsb.border_color = Color(1, 1, 1, 0.45)
	if is_cur:
		dsb.border_color = Color("#ffd86b")
		dsb.shadow_color = Color(1, 216.0 / 255.0, 107.0 / 255.0, 0.7)
		dsb.shadow_size = 8
	dot.add_theme_stylebox_override("panel", dsb)
	var dl := Label.new()
	dl.text = "🎁" if ntype == "equip" else ("✦" if ntype == "event" else ("🛒" if ntype == "shop" else str(rnd)))
	dl.add_theme_font_size_override("font_size", 22 if is_cur else 17)
	dl.add_theme_color_override("font_color", Color("#0a0e18"))
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.add_child(dl)
	var dot_center := CenterContainer.new()
	dot_center.custom_minimum_size = Vector2(52, 52)
	dot_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_center.add_child(dot)
	col.add_child(dot_center)
	# 标签
	if is_cur and ntype == "normal":
		var pill := PanelContainer.new()
		var psb := StyleBoxFlat.new()
		psb.set_corner_radius_all(10)
		psb.set_border_width_all(1)
		psb.content_margin_left = 8; psb.content_margin_right = 8
		psb.content_margin_top = 2; psb.content_margin_bottom = 2
		var pl := Label.new()
		pl.add_theme_font_size_override("font_size", 12)
		if _cur_side == "left":
			pl.text = "🐢 我方回合"
			pl.add_theme_color_override("font_color", Color("#06d6a0"))
			psb.bg_color = Color(6.0 / 255.0, 214.0 / 255.0, 160.0 / 255.0, 0.16)
			psb.border_color = Color(6.0 / 255.0, 214.0 / 255.0, 160.0 / 255.0, 0.55)
		else:
			pl.text = "👹 敌方回合"
			pl.add_theme_color_override("font_color", Color("#ff6b6b"))
			psb.bg_color = Color(1, 107.0 / 255.0, 107.0 / 255.0, 0.16)
			psb.border_color = Color(1, 107.0 / 255.0, 107.0 / 255.0, 0.55)
		pill.add_theme_stylebox_override("panel", psb)
		pill.add_child(pl)
		col.add_child(pill)
	else:
		var lbl := Label.new()
		lbl.text = "初始装备" if ntype == "equip" else ("事件" if ntype == "event" else ("商店" if ntype == "shop" else "第%d回合" % rnd))
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color("#d6dde6"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lbl)
	# 远近缩放/透明 (PoC ttl-past/.future/.current)
	col.pivot_offset = Vector2(26, 32)
	if pos == "past":
		col.modulate.a = 0.4
		col.scale = Vector2(0.8, 0.8)
	elif pos == "future":
		col.modulate.a = 0.72
		col.scale = Vector2(0.88, 0.88)
	else:
		col.scale = Vector2(1.16, 1.16)
	return col


# ══════════════════════════════════════════════════════════════════
# 浮层 HUD — 1:1 移植 PoC 表现层子系统 (CanvasLayer, 不随相机 zoom/pan)
#   ① GlobalToolbar  (PoC GlobalToolbar.ts + BattleTopRow.ts 图标行)
#   ② StatsRail      (PoC BattleStatsRail.ts: 深海币 pill + 羁绊 chip 竖排)
#   ③ BenchRail      (PoC BenchRail.ts: 装备席 rail, 双方各一条)
# 全部叠加层, 不碰世界层 (龟/血条/技能演出). 坐标/尺寸引 PoC base(scale1) 源码。
# ══════════════════════════════════════════════════════════════════

# PoC :root 单位 (BattleStatsRail.ts:82-95 / BattleTopRow.ts:72-76, scale=1):
const HUD_CHROME_BTN := 52        # --poc-chrome-btn
const HUD_CHROME_UNIT := 62       # --poc-chrome-unit (52 + 10 gap)
const HUD_SLOT_SIZE := 52         # --poc-bench-slot-size
const HUD_SLOT_GAP := 7           # --poc-bench-slot-gap
const HUD_SLOT_COUNT := 10        # --poc-bench-slot-count
const HUD_RAIL_PAD_V := 9         # --poc-bench-rail-pad-v
const HUD_RAIL_PAD_H := 9         # --poc-bench-rail-pad-h
const HUD_RAIL_MARGIN := 6        # --poc-bench-rail-margin
const HUD_RAIL_WIDTH := 72        # --poc-bench-rail-width
# rail-height = count*size + (count-1)*gap + pad-v*2 = 10*52 + 9*7 + 18 = 601
const HUD_RAIL_HEIGHT := HUD_SLOT_COUNT * HUD_SLOT_SIZE + (HUD_SLOT_COUNT - 1) * HUD_SLOT_GAP + HUD_RAIL_PAD_V * 2
const HUD_RAIL_HALF := HUD_RAIL_HEIGHT / 2.0
# stats-offset-x = margin + rail-width + 8 = 86
const HUD_STATS_OFFSET_X := HUD_RAIL_MARGIN + HUD_RAIL_WIDTH + 8
const HUD_SYNERGY_GAP := 40       # --poc-stats-synergy-gap
# ── 云顶式横排备战席 (用户 2026-06-26 拍板): 备战席从左侧竖排改成战场下方一条横排, 商店落最底, 上下分层不重叠。
#   纵向预算: 战场最低龟(front-2/back-2 @ y=69%×720=497, 脚底锚)→ 屏底 720 仅 223px;
#   商店内容实测需 ≥160 高(_shop_probe: 143内容+12边距, 150会裁控制行) → 商店定 160 (y560-720);
#   横席落商店正上方贴底 → 顶沿 720-160-64 = 496, 恰在龟脚 497 上方 (龟身全在 ≤497 → 不被席挡)。
#   横席竖向内边距收到 6 (非 9) 把高压到 64, 给"龟脚之上"挤出这 1px 余量。
const HUD_BENCHROW_PAD_V := 6     # 横席竖向内边距 (收紧版, 非竖排的 HUD_RAIL_PAD_V=9)
const HUD_BENCHROW_WIDTH := HUD_SLOT_COUNT * HUD_SLOT_SIZE + (HUD_SLOT_COUNT - 1) * HUD_SLOT_GAP + HUD_RAIL_PAD_H * 2   # = 10*52+9*7+18 = 601
const HUD_BENCHROW_HEIGHT := HUD_SLOT_SIZE + HUD_BENCHROW_PAD_V * 2   # = 52+12 = 64
const HUD_BENCHROW_SHOP_H := 160  # 底部商店条高 (= _battle_shop_root offset_top -160); 横席落其正上方
const HUD_BENCHROW_GAP := 0       # 横席底沿紧贴商店顶沿 (无缝, 纵向预算已极限)

var _deep_coin_val_l: Label = null
var _deep_coin_val_r: Label = null
var _deep_coin_pill_l: PanelContainer = null   # pill 容器 (pulse 缩放用)
var _deep_coin_pill_r: PanelContainer = null
var _deep_coin_shown_l := 0   # 当前显示值 (count-up 起点)
var _deep_coin_shown_r := 0
var _coin_tween_l: Tween = null
var _coin_tween_r: Tween = null
var _synergy_box_l: VBoxContainer = null
var _synergy_box_r: VBoxContainer = null


func _create_battle_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 8   # 在世界层之上, 在 action_panel(10)/banner(20) 之下
	hud_layer.name = "BattleHud"
	add_child(hud_layer)
	# 旧的独立 📜 LogToggle 由新工具栏图标行取代 → 隐藏避免重复
	var old_toggle: Button = get_node_or_null("UI/LogToggle")
	if old_toggle:
		old_toggle.visible = false
	_build_global_toolbar()
	_build_stats_rail()
	_build_bench_rail()
	_refresh_battle_hud()


# ─── ① GlobalToolbar (PoC GlobalToolbar.ts + BattleTopRow.ts 图标行) ─────────
# 右起序 (PoC BattleTopRow:88-93 + GlobalToolbar:59-60):
#   全屏(right:8) 音乐(right:8+unit) | 统计(8+2u) 日志(8+3u) 术语(8+4u), 全 top:12
# 左: 返回(left:16, top:12) → PoC .btn-battle-back
func _build_global_toolbar() -> void:
	# 返回键 (左上) — PoC confirmSurrender → 这里接 _on_return_pressed
	_mk_chrome_btn("ui/btn-back.png", Vector2(16, 12), "退出", _on_return_pressed)
	# 右侧图标行: 从右边缘按 unit 步进定位 (右锚定)
	_mk_chrome_btn_right("ui/btn-fullscreen.png", 8, "全屏", _hud_toggle_fullscreen)
	_hud_sound_btn = _mk_chrome_btn_right("ui/btn-sound.png", 8 + HUD_CHROME_UNIT, "音量", _hud_toggle_sound_panel)
	_mk_chrome_btn_right("ui/btn-stats.png", 8 + 2 * HUD_CHROME_UNIT, "战斗统计", _on_dmg_stats_toggle)
	_mk_chrome_btn_right("ui/btn-log.png", 8 + 3 * HUD_CHROME_UNIT, "战斗日志", _on_log_toggle)
	_mk_chrome_btn_right("ui/btn-help.png", 8 + 4 * HUD_CHROME_UNIT, "术语说明", _hud_toggle_help)
	_add_rule_badge()   # F7: 规则之日徽章 (返回键右侧, 显示本局规则)


## 规则之日徽章 (F7, 1:1 PoC BattleTopRow.setRule:309) — 返回键右侧药丸: 图标+名(规则色), hover 出 desc.
func _add_rule_badge() -> void:
	if rule == "" or rule == "正常对局":
		return
	var rdef: Dictionary = {}
	for r in DataRegistry.battle_rules:
		if str(r.get("name", "")) == rule:
			rdef = r
			break
	if rdef.is_empty():
		return
	var ci: int = int(rdef.get("color", 0x888888))
	var col := Color8((ci >> 16) & 0xff, (ci >> 8) & 0xff, ci & 0xff)
	var pill := PanelContainer.new()
	pill.position = Vector2(16 + HUD_CHROME_BTN + 10, 14)
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.tooltip_text = str(rdef.get("desc", ""))
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.04, 0.08, 0.12, 0.85)
	psb.border_color = col
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	psb.content_margin_left = 10; psb.content_margin_right = 10
	psb.content_margin_top = 5; psb.content_margin_bottom = 5
	pill.add_theme_stylebox_override("panel", psb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_rel := str(rdef.get("icon", ""))
	var ipath := "res://assets/sprites/%s" % icon_rel
	if ResourceLoader.exists(ipath):
		var ic := TextureRect.new()
		ic.texture = load(ipath)
		ic.custom_minimum_size = Vector2(22, 22)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ic)
	var nm := Label.new()
	nm.text = rule
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", col)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(nm)
	pill.add_child(hb)
	hud_layer.add_child(pill)


## 建一个贴图按钮 (左/绝对定位). pos = (left, top) 像素. PoC .btn-help-icon: 透明底, 图满铺, hover 放大.
func _mk_chrome_btn(icon_rel: String, pos: Vector2, tip: String, cb: Callable) -> TextureButton:
	var btn := TextureButton.new()
	var path := "res://assets/sprites/%s" % icon_rel
	if ResourceLoader.exists(path):
		btn.texture_normal = load(path)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(HUD_CHROME_BTN, HUD_CHROME_BTN)
	btn.size = Vector2(HUD_CHROME_BTN, HUD_CHROME_BTN)
	btn.position = pos
	btn.tooltip_text = tip
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素图
	if cb.is_valid():
		btn.pressed.connect(cb)
	# hover 放大 1.1 (PoC .btn-help-icon:hover img{transform:scale(1.1)})
	btn.pivot_offset = Vector2(HUD_CHROME_BTN, HUD_CHROME_BTN) / 2.0
	btn.mouse_entered.connect(func(): btn.scale = Vector2(1.1, 1.1))
	btn.mouse_exited.connect(func(): btn.scale = Vector2.ONE)
	hud_layer.add_child(btn)
	return btn


## 建一个右锚定贴图按钮. right_off = 距右边缘像素 (按钮右沿). top 固定 12.
func _mk_chrome_btn_right(icon_rel: String, right_off: int, tip: String, cb: Callable) -> TextureButton:
	var left := VIEW_W - right_off - HUD_CHROME_BTN
	var btn := _mk_chrome_btn(icon_rel, Vector2(left, 12), tip, cb)
	_anchor_hud_right(btn, right_off + HUD_CHROME_BTN)   # 右锚: ENVELOP 下贴真实右边缘
	return btn


func _hud_toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


var _hud_muted := false
var _hud_sound_btn: TextureButton = null
var _sound_panel: PanelContainer = null
var _sound_mute_btn: Button = null
var _sound_catcher: Control = null   # 点空白关面板 (PoC outside-click auto-dismiss)


## 音量键点击 → 弹/收 sound panel (PoC GlobalToolbar.toggleSoundPanel 1:1).
## 面板含: 静音切换 + 主音乐滑条(GameState/Audio.bgm_volume) + 音效滑条(sfx_volume), 点空白关.
func _hud_toggle_sound_panel() -> void:
	if _sound_panel == null:
		_build_sound_panel()
	if _sound_panel == null:
		return
	var opening := not _sound_panel.visible
	_sound_panel.visible = opening
	if _sound_catcher != null:
		_sound_catcher.visible = opening


## 静音切换 (PoC toggleMute): Master bus mute + 音量键灰显.
func _hud_toggle_mute() -> void:
	_hud_muted = not _hud_muted
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, _hud_muted)
	if _sound_mute_btn != null:
		_sound_mute_btn.text = "🔇" if _hud_muted else "🔊"
	if _hud_sound_btn != null:
		_hud_sound_btn.modulate = Color(0.6, 0.6, 0.6, 1.0) if _hud_muted else Color.WHITE


## 构造 sound panel (PoC .poc-sound-panel: top:52 right:16, 暗底圆角, 静音键 + 2 滑条).
func _build_sound_panel() -> void:
	# 点空白关面板的透明全屏 catcher (在面板下方; 仅面板开时可见)
	_sound_catcher = Control.new()
	_sound_catcher.name = "SoundPanelCatcher"
	_sound_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sound_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_sound_catcher.visible = false
	_sound_catcher.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _sound_panel != null:
				_sound_panel.visible = false
			_sound_catcher.visible = false)
	hud_layer.add_child(_sound_catcher)

	var panel := PanelContainer.new()
	panel.name = "SoundPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.059, 0.078, 0.118, 0.95)   # rgba(15,20,30,.95)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(220, 0)
	# top:52 right:16 (PoC @media min-width:801)
	panel.position = Vector2(VIEW_W - 16 - 220, 52)
	_anchor_hud_right(panel, 16 + 220)   # 右锚: ENVELOP 重排贴边
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	# 行1: 静音键 + "音量" 标题
	var row0 := HBoxContainer.new()
	row0.add_theme_constant_override("separation", 8)
	vb.add_child(row0)
	_sound_mute_btn = Button.new()
	_sound_mute_btn.text = "🔇" if _hud_muted else "🔊"
	_sound_mute_btn.add_theme_font_size_override("font_size", 14)
	_sound_mute_btn.pressed.connect(_hud_toggle_mute)
	row0.add_child(_sound_mute_btn)
	var title := Label.new()
	title.text = "音量"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row0.add_child(title)

	# 行2: 主音乐滑条
	_mk_sound_slider(vb, "主音乐", GameState.bgm_volume, func(v: float):
		GameState.bgm_volume = v
		Audio.bgm_volume = v
		Audio.apply_bgm_volume()
		GameState.save())
	# 行3: 音效滑条 (拖完试播一声 hit, PoC SettingsScene 同款反馈)
	_mk_sound_slider(vb, "音效", GameState.sfx_volume, func(v: float):
		GameState.sfx_volume = v
		Audio.sfx_volume = v
		GameState.save())

	panel.visible = false
	hud_layer.add_child(panel)
	_sound_panel = panel


## sound panel 一行滑条: 标签(48宽) + HSlider + 百分比(38宽). cb(v∈0..1).
func _mk_sound_slider(parent: VBoxContainer, label: String, init: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color("#aabbcc"))
	lbl.custom_minimum_size = Vector2(48, 0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = round(clampf(init, 0.0, 1.0) * 100.0)
	slider.custom_minimum_size = Vector2(100, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var pct := Label.new()
	pct.text = "%d%%" % int(slider.value)
	pct.add_theme_font_size_override("font_size", 12)
	pct.add_theme_color_override("font_color", Color("#aabbcc"))
	pct.custom_minimum_size = Vector2(38, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pct)
	slider.value_changed.connect(func(v: float):
		pct.text = "%d%%" % int(round(v))
		cb.call(v / 100.0))


# ═══ HelpPanel 术语说明面板 (1:1 PoC HelpPanel.ts / JS index.html:380-460) ═══
# 19 个 help-item, 顺序严格 (PoC HELP_ITEMS): icon('img:'贴图/'col:'色块/'emoji:') + 标题 + 描述.
# 布局 = auto-fill grid minmax(240,1fr); 此处 Godot 用 2 列 GridContainer + 滚动.
const HELP_ITEMS: Array = [
	["img:stats/atk-icon.png",       "攻击力 (ATK)",      "技能伤害基于攻击力百分比计算，如\"90%ATK\""],
	["img:stats/def-icon.png",       "护甲",              "减少受到的物理伤害。减伤% = 护甲÷(护甲+40)"],
	["img:stats/mr-icon.png",        "魔抗",              "减少受到的魔法伤害。减伤% = 魔抗÷(魔抗+40)"],
	["img:stats/armor-pen-icon.png", "护甲穿透",          "无视目标等量护甲值"],
	["img:stats/magic-pen-icon.png", "魔法穿透",          "无视目标等量魔抗值"],
	["col:#ff4444",                  "物理伤害（红色）",   "受护甲减免"],
	["col:#4dabf7",                  "魔法伤害（蓝色）",   "受魔抗减免"],
	["col:#ffffff",                  "真实伤害（白色）",   "无视护甲和魔抗，但会被护盾吸收"],
	["col:#ffffff",                  "护盾（白色）",       "额外生命层，所有伤害先消耗护盾再扣血。血条上白色部分"],
	["img:stats/hp-icon.png",        "生命值（绿色回复）", "恢复生命值，不超过最大HP"],
	["img:stats/crit-icon.png",      "暴击率",            "基础暴击率25%，暴击时触发额外伤害"],
	["img:stats/crit-dmg-icon.png",  "暴击伤害",          "暴击时伤害倍率，基础×1.5倍。暴击数字前显示此图标"],
	["img:stats/lifesteal-icon.png", "生命偷取",          "造成伤害时按比例回复自身生命值"],
	["img:status/dodge-icon.png",    "闪避率",            "有概率完全闪避一段攻击，不受伤害"],
	["emoji:🔥",                      "灼烧 / 持续伤害",   "统一：0.4×ATK+8%最大HP 魔法伤害，4回合，被魔抗减免，被护盾吸收，不叠加只刷新"],
	["emoji:⬇️",                      "减益效果",          "减攻/减护甲/减魔抗：降低百分比，持续若干回合。眩晕：跳过1回合行动"],
	["emoji:⭐",                      "被动技能",          "每只龟的固有能力，战斗中自动触发。点击卡片上的图标查看详情"],
	["emoji:📊",                      "伤害公式",          "物理伤害 = 基础值 × 暴击倍率 × (1 - 护甲减伤%)\n魔法伤害 = 基础值 × 暴击倍率 × (1 - 魔抗减伤%)\n真实伤害 = 基础值 × 暴击倍率（无视护甲和魔抗）\n伤害顺序：先打泡泡盾 → 护盾 → 生命值"],
	["emoji:🎮",                      "回合规则",          "第1回合：左方出1只 → 右方全部出手\n第2回合起：左方全部 → 右方全部\n每回合双方选择哪只龟行动"],
]

func _hud_toggle_help() -> void:
	# 术语说明面板 — toggle: 已开则关, 否则建 (1:1 PoC HelpPanel.toggle)
	if hud_layer == null:
		return
	var existing := hud_layer.get_node_or_null("HelpPanelModal")
	if existing:
		existing.queue_free()
		return
	_show_help_panel()


## 术语说明面板 (PoC HelpPanel.ts: #poc-help-veil 半透遮罩 + #poc-help-panel 居中卡片).
##   标题 "术语说明" + ✕; 19 项 help-item 双列网格; 点遮罩/✕ 关. 样式引 PoC css (#161b22/#1c2333/#e6edf3/#8b949e).
func _show_help_panel() -> void:
	# 全屏遮罩 (PoC #poc-help-veil rgba(0,0,0,.55)) — 点空白关
	var modal := Control.new()
	modal.name = "HelpPanelModal"
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(dim)
	modal.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			modal.queue_free())

	# 卡片 (PoC #poc-help-panel: 720宽, 底 #161b22, 1px rgba(255,255,255,.1) 边, 圆12, padding16)
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color("#161b22")
	csb.border_color = Color(1, 1, 1, 0.1)
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(12)
	csb.content_margin_left = 16; csb.content_margin_right = 16
	csb.content_margin_top = 16; csb.content_margin_bottom = 16
	csb.shadow_color = Color(0, 0, 0, 0.6)
	csb.shadow_size = 12
	card.add_theme_stylebox_override("panel", csb)
	card.custom_minimum_size = Vector2(720, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	# 标题行 (PoC .help-title: 15px bold #e6edf3, 两端对齐 + ✕)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var title := Label.new()
	title.text = "术语说明"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("#e6edf3"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 18)   # PoC .help-close font-size:18px
	close_btn.add_theme_color_override("font_color", Color("#8b949e"))
	close_btn.pressed.connect(modal.queue_free)
	head.add_child(close_btn)

	# 网格 (PoC .help-grid auto-fill 240px → Godot 双列). 滚动容器防超高 (PoC max-height:84vh overflow-y)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for item in HELP_ITEMS:
		grid.add_child(_mk_help_item(item[0], item[1], item[2]))

	hud_layer.add_child(modal)
	# 居中卡片 (布局后取实际尺寸)
	_center_modal_card(modal, card)


## 单个 help-item (PoC .help-item: flex gap10 padding8/10 底#1c2333 圆8, 图标 + (标题<b>/描述<div>)).
func _mk_help_item(icon: String, title: String, desc: String) -> PanelContainer:
	var block := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2333")
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	block.add_theme_stylebox_override("panel", sb)
	block.custom_minimum_size = Vector2(330, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	block.add_child(row)
	# 图标列 (PoC .help-icon width24 居中)
	row.add_child(_mk_help_icon(icon))
	# 文字列: 标题(白 12 bold) + 描述(灰 #8b949e 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 12)
	tl.add_theme_color_override("font_color", Color("#e6edf3"))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(tl)
	var dl := Label.new()
	dl.text = desc
	dl.add_theme_font_size_override("font_size", 12)
	dl.add_theme_color_override("font_color", Color("#8b949e"))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(270, 0)
	col.add_child(dl)
	return block


## help-item 图标: 'img:'→贴图(20×20), 'col:#xxx'→色块■(16), 'emoji:x'→emoji 文字(20). PoC renderIcon.
func _mk_help_icon(icon: String) -> Control:
	if icon.begins_with("img:"):
		# PoC renderIcon: <img class="help-icon"(cell width24) style="width:20px;height:20px"> → 图20×20 居中于24格
		var cell := CenterContainer.new()
		cell.custom_minimum_size = Vector2(24, 24)
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tex := TextureRect.new()
		var path := "res://assets/sprites/%s" % icon.substr(4)
		if ResourceLoader.exists(path):
			tex.texture = load(path)
		tex.custom_minimum_size = Vector2(20, 20)
		tex.size = Vector2(20, 20)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(tex)
		return cell
	if icon.begins_with("col:"):
		var lbl := Label.new()
		lbl.text = "■"
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(icon.substr(4)))
		lbl.custom_minimum_size = Vector2(24, 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return lbl
	# emoji:
	var el := Label.new()
	el.text = icon.substr(6)
	el.add_theme_font_size_override("font_size", 20)
	el.custom_minimum_size = Vector2(24, 0)
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return el


# ─── ② StatsRail (PoC BattleStatsRail.ts: 深海币 pill + 羁绊 chip 竖排) ────────
func _build_stats_rail() -> void:
	# 深海币 pill — 我方(left)接 GameState.battle_coins, 敌方(right)接 enemy_coins (PoC deepCoin)
	_deep_coin_val_l = _mk_deep_coin("left")
	_deep_coin_val_r = _mk_deep_coin("right")
	# 羁绊 chip 竖排 (PoC synergy-bar): 在 pill 下方 synergy-gap 处
	_synergy_box_l = _mk_synergy_box("left")
	_synergy_box_r = _mk_synergy_box("right")


## 深海币 pill (PoC .poc-deep-coin-pill: 蓝金属药丸 + 币图标 + 数值). 返回数值 Label.
func _mk_deep_coin(side: String) -> Label:
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.46, 0.745, 0.95)   # PoC rgba(28,118,190,.95)
	sb.border_color = Color("#58d3ff")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 15; sb.content_margin_right = 15
	sb.content_margin_top = 7; sb.content_margin_bottom = 7
	sb.shadow_color = Color(0.345, 0.827, 1.0, 0.55)
	sb.shadow_size = 8
	pill.add_theme_stylebox_override("panel", sb)
	var top := HUD_RAIL_HEIGHT / -2.0 + VIEW_H / 2.0   # 50% - rail-half
	pill.position = Vector2(HUD_STATS_OFFSET_X if side == "left" else 0, top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	pill.add_child(hb)
	var icon := TextureRect.new()
	var coin_path := "res://assets/sprites/battle/deep-coin.png"
	if ResourceLoader.exists(coin_path):
		icon.texture = load(coin_path)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon)
	var val := Label.new()
	val.text = "0"
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", Color("#cdf3ff"))
	hb.add_child(val)
	hud_layer.add_child(pill)
	# pulse 缩放绕中心 (PoC deep-coin-pulse transform:scale(1.18)) — pivot 在布局后设
	if side == "left":
		_deep_coin_pill_l = pill
	else:
		_deep_coin_pill_r = pill
	# 右侧: 右锚定 (pill 右沿距右边缘 HUD_STATS_OFFSET_X) — 布局完成后再定位
	if side == "right":
		_defer_anchor_right(pill, top)
	return val


## 深海币更新 (PoC BattleStatsRail.setDeepCoin 1:1): 数字 count-up 缓动滚动 (420ms easeOutCubic),
## 变化时 pill 脉冲 scale 1.18 yoyo (220ms). 非瞬切.
func _set_deep_coin(side: String, val: int, pulse: bool = false) -> void:
	var lbl := _deep_coin_val_l if side == "left" else _deep_coin_val_r
	var pill := _deep_coin_pill_l if side == "left" else _deep_coin_pill_r
	if lbl == null:
		return
	var from := _deep_coin_shown_l if side == "left" else _deep_coin_shown_r
	# 旧 tween 还在跑就杀掉, 从当前值续滚
	var old_tw := _coin_tween_l if side == "left" else _coin_tween_r
	if old_tw != null and old_tw.is_valid():
		old_tw.kill()
	if from == val:
		lbl.text = str(val)
	else:
		# count-up: tween_method 从 from 滚到 val, 每帧 round 显示 (PoC requestAnimationFrame 同款)
		var setter := func(v: float):
			var iv := int(round(v))
			lbl.text = str(iv)
			if side == "left":
				_deep_coin_shown_l = iv
			else:
				_deep_coin_shown_r = iv
		var tw := create_tween()
		tw.tween_method(setter, float(from), float(val), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if side == "left":
			_coin_tween_l = tw
		else:
			_coin_tween_r = tw
	if side == "left":
		_deep_coin_shown_l = val
	else:
		_deep_coin_shown_r = val
	# pulse: pill scale 1.18 → 1.0 (绕中心)
	if pulse and pill != null and is_instance_valid(pill):
		pill.pivot_offset = pill.size / 2.0
		var ptw := create_tween()
		ptw.tween_property(pill, "scale", Vector2(1.18, 1.18), 0.11)
		ptw.tween_property(pill, "scale", Vector2.ONE, 0.11)


## 布局结束后把节点右沿对齐到 (右边缘 - HUD_STATS_OFFSET_X). 在 size 算好后跑.
func _defer_anchor_right(node: Control, top_y: float) -> void:
	await get_tree().process_frame
	if is_instance_valid(node):
		node.position = Vector2(VIEW_W - HUD_STATS_OFFSET_X - node.size.x, top_y)
		_anchor_hud_right(node, HUD_STATS_OFFSET_X + node.size.x)   # 右锚: ENVELOP 重排贴边


## 羁绊 chip 竖排容器 (PoC .poc-synergy-bar): 左队左对齐 / 右队右对齐.
func _mk_synergy_box(side: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	var top := HUD_RAIL_HEIGHT / -2.0 + VIEW_H / 2.0 + HUD_SYNERGY_GAP
	box.position = Vector2(HUD_STATS_OFFSET_X if side == "left" else 0, top)
	hud_layer.add_child(box)
	if side == "right":
		# 右队: 容器靠右边缘对齐 (随 chip 宽变化在刷新时重定位)
		box.position.x = VIEW_W - HUD_STATS_OFFSET_X
		_anchor_hud_right(box, HUD_STATS_OFFSET_X)   # 右锚: ENVELOP 重排贴边
	return box


## 渲染一侧羁绊 chip 列 (双维度: 12 类型(职业) + 11 学派(种族))。
## 每个 chip 可点 → 两区式 TFT 详情(头·主区·档位区, 用户 2026-06-25)。
##   激活的: 边框/字色随档升级(铜→银→金→钻→彩), 显 "名 件数/下一档"。
##   未激活的(件数不足首档): 灰显, 显 "名 件数/首档阈值".
func _render_school_chips(side: String, team: Array) -> void:
	var box := _synergy_box_l if side == "left" else _synergy_box_r
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	# ── 类型(职业)维: 激活在前(按件数), 未激活灰显在后 ──
	var type_active: Array = Phase2Types.calc_active(team)
	var type_seen: Dictionary = {}
	for a in type_active:
		type_seen[str(a.get("type", ""))] = true
		_add_synergy_chip(box, "type", str(a.get("type", "")), int(a.get("count", 0)),
				int(a.get("tier", 1)), a.get("tiers", []))
	var type_raw: Dictionary = Phase2Types.raw_counts(team)
	for t in type_raw:
		if type_seen.has(t):
			continue
		_add_synergy_chip(box, "type", str(t), int(type_raw.get(t, 0)),
				0, Phase2Types.TYPES.get(t, {}).get("tiers", []))
	# ── 学派(种族)维: 激活在前, 未激活灰显在后 ──
	var school_active: Array = Phase2Schools.calc_active(team)
	var school_seen: Dictionary = {}
	for a in school_active:
		school_seen[str(a.get("school", ""))] = true
		_add_synergy_chip(box, "school", str(a.get("school", "")), int(a.get("count", 0)),
				int(a.get("tier", 1)), a.get("tiers", []))
	var school_raw: Dictionary = Phase2Schools.raw_counts(team)
	for s in school_raw:
		if school_seen.has(s) or not Phase2Schools.SCHOOLS.has(s):
			continue
		_add_synergy_chip(box, "school", str(s), int(school_raw.get(s, 0)),
				0, Phase2Schools.SCHOOLS.get(s, {}).get("tiers", []))


## 单个羁绊 chip (可点弹两区详情). dim = "type"/"school"; tier=0 表示未激活(灰显).
func _add_synergy_chip(box: VBoxContainer, dim: String, key: String, count: int, tier: int, tiers: Array) -> void:
	var emoji: String = (Phase2Types.emoji_of(key) if dim == "type" else Phase2Schools.emoji_of(key))
	var disp: String = (Phase2Types.display_name(key) if dim == "type" else key)
	# 云顶之弈式档位色: 铜→银→金→钻→彩; 未激活=灰.
	var tier_col: Color = Color("#5a6072")   # 未激活灰
	var prog: String
	if tier > 0:
		tier_col = [Color("#cd7f32"), Color("#c0c0c0"), Color("#ffd700"), Color("#5af0ff"), Color("#ff7de0")][clampi(tier - 1, 0, 4)]
		var next_thr: int = int(tiers[tier]) if tier < tiers.size() else 0   # 0 = 已满档
		prog = ("%d/%d" % [count, next_thr]) if next_thr > 0 else ("%d ★满" % count)
	else:
		var first_thr: int = int(tiers[0]) if tiers.size() > 0 else 0
		prog = "%d/%d" % [count, first_thr]
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.063, 0.082, 0.125, 0.92)
	sb.border_color = tier_col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 7; sb.content_margin_right = 7
	sb.content_margin_top = 3; sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	if tier <= 0:
		chip.modulate.a = 0.6   # 未激活灰显整体压暗
	var lbl := Label.new()
	lbl.text = "%s %s %s" % [emoji, disp, prog]
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", tier_col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	chip.tooltip_text = "%s · 件数 %d (点击查看羁绊详情)" % [disp, count]
	# 可点 → 两区式详情 modal
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.mouse_entered.connect(func():
		chip.pivot_offset = chip.size / 2.0
		var tw := create_tween()
		tw.tween_property(chip, "scale", Vector2(1.06, 1.06), 0.1))
	chip.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(chip, "scale", Vector2.ONE, 0.1))
	chip.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_synergy_detail_2zone(dim, key, count, tier, tiers))
	box.add_child(chip)


## 两区式 TFT 羁绊详情 (用户 2026-06-25): 全屏遮罩 + 卡片.
##   头: emoji+名 + 当前件数/下一档(或"满档"/"未激活")
##   主区: 当前激活档完整效果(属性写全; 未激活则提示"差 N 件激活"+首档预览)
##   档位区: 列全部档位, 高亮当前档 / 已过低档暗 / 未达高档灰.
func _show_synergy_detail_2zone(dim: String, key: String, count: int, cur_tier: int, tiers: Array) -> void:
	if hud_layer == null:
		return
	var old := hud_layer.get_node_or_null("SynergyDetailModal")
	if old:
		old.queue_free()
	var emoji: String = (Phase2Types.emoji_of(key) if dim == "type" else Phase2Schools.emoji_of(key))
	var disp: String = (Phase2Types.display_name(key) if dim == "type" else key)

	# 全屏遮罩 — 点空白关
	var modal := Control.new()
	modal.name = "SynergyDetailModal"
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim_bg := ColorRect.new()
	dim_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_bg.color = Color(0, 0, 0, 0.7)
	dim_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(dim_bg)
	modal.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			modal.queue_free())

	# 卡片
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color("#142036")
	csb.border_color = Color("#58a6ff")
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(12)
	csb.content_margin_left = 26; csb.content_margin_right = 26
	csb.content_margin_top = 22; csb.content_margin_bottom = 22
	csb.shadow_color = Color(0, 0, 0, 0.6)
	csb.shadow_size = 12
	card.add_theme_stylebox_override("panel", csb)
	card.custom_minimum_size = Vector2(520, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	# ── 头: emoji + 名 + 件数/下一档 + ✕ ──
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var em := Label.new()
	em.text = emoji
	em.add_theme_font_size_override("font_size", 30)
	head.add_child(em)
	var nm := Label.new()
	nm.text = disp
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Color("#ffd93d"))
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nm)
	# 件数/下一档 进度徽标
	var prog_str: String
	if cur_tier > 0:
		var next_thr: int = int(tiers[cur_tier]) if cur_tier < tiers.size() else 0
		prog_str = ("%d/%d" % [count, next_thr]) if next_thr > 0 else ("%d ★满档" % count)
	else:
		var first_thr: int = int(tiers[0]) if tiers.size() > 0 else 0
		prog_str = "%d/%d" % [count, first_thr]
	var prog_lbl := Label.new()
	prog_lbl.text = prog_str
	prog_lbl.add_theme_font_size_override("font_size", 18)
	prog_lbl.add_theme_color_override("font_color", Color("#9fb4d6") if cur_tier <= 0 else Color("#cfe0ff"))
	prog_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(prog_lbl)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(modal.queue_free)
	head.add_child(close_btn)

	# ── 主区: 当前激活档完整效果(属性写全) ──
	var main_panel := PanelContainer.new()
	var msb := StyleBoxFlat.new()
	if cur_tier > 0:
		msb.bg_color = Color(1.0, 0.843, 0.0, 0.1)
		msb.border_color = Color("#ffd93d")
	else:
		msb.bg_color = Color(0.35, 0.4, 0.5, 0.12)
		msb.border_color = Color("#6a7488")
	msb.border_width_left = 3
	msb.set_corner_radius_all(5)
	msb.content_margin_left = 13; msb.content_margin_right = 13
	msb.content_margin_top = 10; msb.content_margin_bottom = 10
	main_panel.add_theme_stylebox_override("panel", msb)
	var main_col := VBoxContainer.new()
	main_col.add_theme_constant_override("separation", 4)
	main_panel.add_child(main_col)
	var main_head := Label.new()
	if cur_tier > 0:
		main_head.text = "当前激活 (第%d档)" % cur_tier
		main_head.add_theme_color_override("font_color", Color("#ffd93d"))
	else:
		var miss: int = maxi(0, (int(tiers[0]) if tiers.size() > 0 else 0) - count)
		main_head.text = "未激活 — 差 %d 件激活" % miss
		main_head.add_theme_color_override("font_color", Color("#9fb4d6"))
	main_head.add_theme_font_size_override("font_size", 15)
	main_col.add_child(main_head)
	var main_body := Label.new()
	var cur_desc: String = ""
	if cur_tier > 0:
		cur_desc = (Phase2Types.tier_desc(key, cur_tier) if dim == "type" else Phase2Schools.tier_desc(key, cur_tier))
	else:
		# 未激活: 预览首档效果
		cur_desc = "凑齐 %d 件激活首档:\n%s" % [
			(int(tiers[0]) if tiers.size() > 0 else 0),
			(Phase2Types.tier_desc(key, 1) if dim == "type" else Phase2Schools.tier_desc(key, 1))]
	main_body.text = cur_desc
	main_body.add_theme_font_size_override("font_size", 13)
	main_body.add_theme_color_override("font_color", Color("#eef1f8") if cur_tier > 0 else Color("#c3ccdc"))
	main_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_body.custom_minimum_size = Vector2(460, 0)
	main_col.add_child(main_body)
	vb.add_child(main_panel)

	# ── 档位区: 列全部档位, 高亮当前 / 已过暗 / 未达灰 ──
	var tier_head := Label.new()
	tier_head.text = "全部档位"
	tier_head.add_theme_font_size_override("font_size", 13)
	tier_head.add_theme_color_override("font_color", Color("#8fa0bd"))
	vb.add_child(tier_head)
	# 档位列表套 ScrollContainer 限高 — 长羁绊(唤灵5档/潮汐4档)行数多, 整卡可能超 VIEW_H=720
	# → 顶部头/关闭钮被顶出屏外。限滚动区 ≤520, 头+主区+边距留在卡内, 超出走滚动。
	var tier_scroll := ScrollContainer.new()
	tier_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tier_scroll.custom_minimum_size = Vector2(0, 0)   # 短羁绊自然高(不强撑), 长羁绊由 max 钳
	tier_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tier_list := VBoxContainer.new()
	tier_list.add_theme_constant_override("separation", 8)
	tier_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_scroll.add_child(tier_list)
	vb.add_child(tier_scroll)
	for i in range(tiers.size()):
		var tno: int = i + 1
		var thr: int = int(tiers[i])
		var tdesc: String = (Phase2Types.tier_desc(key, tno) if dim == "type" else Phase2Schools.tier_desc(key, tno))
		var state: int = 0   # 0=未达(灰)  1=已过(暗)  2=当前(高亮)
		if cur_tier > 0:
			if tno == cur_tier:
				state = 2
			elif tno < cur_tier:
				state = 1
		tier_list.add_child(_mk_2zone_tier_row(tno, thr, tdesc, state))

	hud_layer.add_child(modal)
	# 布局后: 档位区实际高超 520 才限高启滚动 (短羁绊保持自然高=不出现滚动条)
	_cap_synergy_tier_scroll(tier_scroll, tier_list)
	_center_modal_card(modal, card)


## 布局后限档位滚动区高: 内容自然高 ≤520 则不限(无滚动条); >520 才钳到 520 启用滚动。
##   防长羁绊(唤灵5档/潮汐4档)整卡超 VIEW_H=720 顶出屏外。
func _cap_synergy_tier_scroll(scroll: ScrollContainer, list: Control) -> void:
	await get_tree().process_frame
	if not (is_instance_valid(scroll) and is_instance_valid(list)):
		return
	var natural_h: float = list.get_combined_minimum_size().y
	const TIER_SCROLL_MAX: float = 520.0
	if natural_h > TIER_SCROLL_MAX:
		scroll.custom_minimum_size = Vector2(0, TIER_SCROLL_MAX)
		scroll.size_flags_vertical = Control.SIZE_FILL


## 档位区单行: [档号 阈值] + 效果文本; state 0=灰未达 / 1=暗已过 / 2=高亮当前.
func _mk_2zone_tier_row(tno: int, thr: int, desc: String, state: int) -> PanelContainer:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 11; sb.content_margin_right = 11
	sb.content_margin_top = 7; sb.content_margin_bottom = 7
	var head_col: Color
	var body_col: Color
	match state:
		2:   # 当前激活: 金辉高亮
			sb.bg_color = Color(1.0, 0.843, 0.0, 0.12)
			sb.border_color = Color("#ffd93d")
			sb.shadow_color = Color(1.0, 0.851, 0.239, 0.35)
			sb.shadow_size = 10
			head_col = Color("#ffe27a"); body_col = Color("#f2f4fb")
		1:   # 已过低档: 暗
			sb.bg_color = Color(0.5, 0.55, 0.65, 0.07)
			sb.border_color = Color("#6f7790")
			head_col = Color("#9aa3b8"); body_col = Color("#9aa3b8")
		_:   # 未达高档: 灰
			sb.bg_color = Color(0.3, 0.33, 0.4, 0.05)
			sb.border_color = Color("#454b5a")
			head_col = Color("#646b7d")
			body_col = Color("#646b7d")
	row.add_theme_stylebox_override("panel", sb)
	if state == 0:
		row.modulate.a = 0.78
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var h := Label.new()
	var marker: String = "  ←当前" if state == 2 else ""
	h.text = "第%d档 (%d件)%s" % [tno, thr, marker]
	h.add_theme_font_size_override("font_size", 13)
	h.add_theme_color_override("font_color", head_col)
	col.add_child(h)
	var b := Label.new()
	b.text = desc
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", body_col)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(460, 0)
	col.add_child(b)
	return row


## 双路: 战中装备变动后重刷两侧学派 chip (从 fighters 现取队伍)。
func _refresh_school_chips_all() -> void:
	if GameState.mode != "duallane":
		return
	var lt: Array = []
	var rt: Array = []
	for f in fighters:
		if f.get("side", "") == "left":
			lt.append(f)
		elif f.get("side", "") == "right":
			rt.append(f)
	_render_school_chips("left", lt)
	_render_school_chips("right", rt)


func _render_synergy(side: String, synergies: Array) -> void:
	var box := _synergy_box_l if side == "left" else _synergy_box_r
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	for s in synergies:
		var tag: String = s.get("tag", "")
		var tier: int = int(s.get("tier", 2))
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		if tier == 3:
			sb.bg_color = Color("#f4c33c"); sb.border_color = Color("#ffe066")   # 金
			sb.shadow_color = Color(1.0, 0.824, 0.275, 0.5)
		else:
			sb.bg_color = Color("#b9c2d2"); sb.border_color = Color("#f2f5fb")   # 银
			sb.shadow_color = Color(0.784, 0.831, 0.92, 0.45)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 6; sb.content_margin_right = 13
		sb.content_margin_top = 5; sb.content_margin_bottom = 5
		sb.shadow_size = 6
		chip.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 7)
		chip.add_child(hb)
		# 标签图标 (assets/sprites/tags/<tag>标签.png)
		var icon_path := "res://assets/sprites/tags/%s标签.png" % tag
		if ResourceLoader.exists(icon_path):
			var ic := TextureRect.new()
			var itex: Texture2D = load(icon_path)
			ic.texture = itex
			# 1:1 PoC .poc-synergy-chip-icon (BattleStatsRail.ts:172-174): height:50 width:auto 保持长宽比
			#   (原固定50×50: 非方标签图被缩小letterbox; PoC注释明说固定50×50压扁是bug已改)
			var iaspect: float = float(itex.get_width()) / maxf(1.0, float(itex.get_height()))
			ic.custom_minimum_size = Vector2(50.0 * iaspect, 50.0)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			hb.add_child(ic)
		else:
			var tl := Label.new()
			tl.text = tag
			tl.add_theme_font_size_override("font_size", 18)
			tl.add_theme_color_override("font_color", Color("#1a2030") if tier == 2 else Color("#3a2606"))
			hb.add_child(tl)
		var tier_lbl := Label.new()
		tier_lbl.text = "×%d" % tier
		tier_lbl.add_theme_font_size_override("font_size", 20)
		tier_lbl.add_theme_color_override("font_color", Color("#1a2030") if tier == 2 else Color("#3a2606"))
		tier_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(tier_lbl)
		chip.tooltip_text = "%s ×%d (点击查看详情)" % [tag, tier]
		# hover scale 1.08 (PoC .poc-synergy-chip:hover) + 点击弹羁绊详情 modal (PoC onSynergyClick→showSynergyDetail)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_entered.connect(func():
			chip.pivot_offset = chip.size / 2.0
			var tw := create_tween()
			tw.tween_property(chip, "scale", Vector2(1.08, 1.08), 0.12))
		chip.mouse_exited.connect(func():
			var tw := create_tween()
			tw.tween_property(chip, "scale", Vector2.ONE, 0.12))
		chip.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_show_synergy_detail(tag, tier))
		box.add_child(chip)
	# 右队 chip 右对齐: 重定位容器右沿 (布局完成后)
	if side == "right":
		var top := HUD_RAIL_HEIGHT / -2.0 + VIEW_H / 2.0 + HUD_SYNERGY_GAP
		_defer_anchor_right(box, top)


## 羁绊详情 modal (PoC BattleScene.showSynergyDetail 1:1): 全屏半透明遮罩 + 480宽卡片,
## emoji + 名称 + ✕, tier2/tier3 描述, 当前激活档金辉高亮 + "(当前激活)". 点遮罩/✕ 关.
func _show_synergy_detail(tag: String, current_tier: int) -> void:
	if hud_layer == null:
		return
	var cfg: Dictionary = DataRegistry.synergies.get(tag, {})
	if cfg.is_empty():
		return
	# 移除旧 modal
	var old := hud_layer.get_node_or_null("SynergyDetailModal")
	if old:
		old.queue_free()
	var emoji: String = cfg.get("emoji", "⚔")
	var name_str: String = cfg.get("name", tag)
	var t2_desc: String = cfg.get("tier2", {}).get("desc", "(无 ×2 效果)")
	var t3_desc: String = cfg.get("tier3", {}).get("desc", "(无 ×3 效果)")

	# 全屏遮罩 (PoC inset:0 rgba(0,0,0,.7)) — 点空白关
	var modal := Control.new()
	modal.name = "SynergyDetailModal"
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(dim)
	modal.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			modal.queue_free())

	# 卡片 (PoC 480宽, 渐变底 #1a2740→#0e1828, 2px #58a6ff 边, 圆12)
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color("#142036")
	csb.border_color = Color("#58a6ff")
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(12)
	csb.content_margin_left = 28; csb.content_margin_right = 28
	csb.content_margin_top = 24; csb.content_margin_bottom = 24
	csb.shadow_color = Color(0, 0, 0, 0.6)
	csb.shadow_size = 12
	card.add_theme_stylebox_override("panel", csb)
	card.custom_minimum_size = Vector2(480, 0)
	# 卡片自身吃点击 (不穿透关闭)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	# 标题行: emoji + 名称 + ✕
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var em := Label.new()
	em.text = emoji
	em.add_theme_font_size_override("font_size", 32)
	head.add_child(em)
	var nm := Label.new()
	nm.text = name_str
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Color("#ffd93d"))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nm)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(modal.queue_free)
	head.add_child(close_btn)

	# tier2 / tier3 描述块
	vb.add_child(_mk_synergy_tier_block(2, t2_desc, current_tier == 2))
	vb.add_child(_mk_synergy_tier_block(3, t3_desc, current_tier == 3))

	hud_layer.add_child(modal)
	# 居中卡片 (布局后取实际尺寸)
	_center_modal_card(modal, card)


## 羁绊详情 tier 描述块 (PoC ×2/×3 块: 左竖条 + 标题 + 描述, 当前档金辉高亮).
func _mk_synergy_tier_block(tier: int, desc: String, is_active: bool) -> PanelContainer:
	var block := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if tier == 3:
		sb.bg_color = Color(1.0, 0.843, 0.0, 0.1)   # rgba(255,215,0,.1)
		sb.border_color = Color("#ffd93d")
	else:
		sb.bg_color = Color(0.588, 0.588, 0.706, 0.12)
		sb.border_color = Color("#aaaaaa")
	# 左竖条 3px (PoC border-left)
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	if is_active:
		sb.shadow_color = Color(1.0, 0.851, 0.239, 0.4)   # 金辉 box-shadow
		sb.shadow_size = 12
	block.add_theme_stylebox_override("panel", sb)
	if not is_active:
		block.modulate.a = 0.7   # PoC opacity:.7
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	block.add_child(col)
	var head := Label.new()
	var active_suffix := "  (当前激活)" if is_active else ""
	head.text = "×%d%s" % [tier, active_suffix]
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color("#ffd93d") if tier == 3 else Color("#cfd0d8"))
	col.add_child(head)
	var body := Label.new()
	body.text = desc
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color("#ddddee"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(420, 0)
	col.add_child(body)
	return block


## modal 卡片居中 (布局完成后用实际尺寸算).
func _center_modal_card(modal: Control, card: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(card) and is_instance_valid(modal):
		card.position = (Vector2(VIEW_W, VIEW_H) - card.size) / 2.0
		# 安全网: 卡片过高(长羁绊唤灵5档/潮汐4档)时顶部被顶出屏外 → 钳到至少留 8px 上边距,
		# 确保头部档位/关闭钮不出 VIEW_H 顶。(内部已套 ScrollContainer 限高, 此为兜底防越界)
		card.position.y = maxf(8.0, card.position.y)
		card.position.x = maxf(8.0, card.position.x)


# ─── ③ BenchRail (PoC BenchRail.ts: 装备席 rail, 双方各一条) ──────────────────
# 木/金属托盘 + 10 槽; filled 槽显装备图标. 拖拽/点击装备留待操作批次 (PoC bench.js drag-drop).
func _build_bench_rail() -> void:
	_mk_bench_rail("left")
	if GameState.mode != "duallane":   # 双路: 线上只看自己(左)装备席, 不显敌方(右)席位 (用户 2026-06-21)
		_mk_bench_rail("right")


func _mk_bench_rail(side: String) -> void:
	var rail := PanelContainer.new()
	rail.name = "BenchRail_%s" % side
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.106, 0.086, 0.063, 0.93)   # PoC 木/金属渐变近似 rgba(27,22,16,.93)
	sb.border_color = Color("#6b5430")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = HUD_RAIL_PAD_H; sb.content_margin_right = HUD_RAIL_PAD_H
	sb.content_margin_top = HUD_BENCHROW_PAD_V; sb.content_margin_bottom = HUD_BENCHROW_PAD_V   # 横排收紧竖向内边距 (高 64)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	rail.add_theme_stylebox_override("panel", sb)
	# 云顶式横排: 横条 (10 槽一行) 落战场下方、商店上方 (用户 2026-06-26).
	rail.custom_minimum_size = Vector2(HUD_BENCHROW_WIDTH, HUD_BENCHROW_HEIGHT)
	# Y: 贴底 — 横席底沿坐落于底部商店条顶沿之上 (留 GAP 缝). 商店条高 SHOP_H → 顶沿 = VIEW_H - SHOP_H.
	var row_top := VIEW_H - HUD_BENCHROW_SHOP_H - HUD_BENCHROW_GAP - HUD_BENCHROW_HEIGHT
	# X: 双路(只左席+底部商店) → 整条水平居中 (对齐商店居中观感); 老模式(左右双席无商店) → 左席贴左、右席镜像贴右, 两条并排不撞.
	var center_x := (VIEW_W - HUD_BENCHROW_WIDTH) / 2.0
	var left_x: float = center_x if GameState.mode == "duallane" else float(HUD_RAIL_MARGIN)
	rail.position = Vector2(left_x if side == "left" else VIEW_W - HUD_RAIL_MARGIN - HUD_BENCHROW_WIDTH, row_top)
	if side == "right":
		_anchor_hud_right(rail, HUD_RAIL_MARGIN + HUD_BENCHROW_WIDTH)   # 右锚: ENVELOP 重排贴边
	var vb := HBoxContainer.new()   # 横排 (原 VBoxContainer 竖排 → 改横)
	vb.name = "Slots"
	vb.add_theme_constant_override("separation", HUD_SLOT_GAP)
	rail.add_child(vb)
	# 收集本侧装备 (PoC bench = 后备装备席; Godot 装备开局已自动上身, 这里列已装备图标作席位视觉)
	var eq_ids := _collect_bench_equips(side)
	for i in range(HUD_SLOT_COUNT):
		var slot := PanelContainer.new()
		var ssb := StyleBoxFlat.new()
		# bench 项: phase1 是字符串 eid; phase2(双路商店买入) 是 {id,star} 字典 → 安全取 id (防 dict→String 崩)
		var bench_item = eq_ids[i] if i < eq_ids.size() else ""
		var eid: String = str(bench_item.get("id", "")) if bench_item is Dictionary else str(bench_item)
		var p2def: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
		if eid != "":
			ssb.bg_color = Color(0.157, 0.118, 0.047, 0.5)   # filled 金调
			ssb.border_color = Color("#ffd966")
		else:
			ssb.bg_color = Color(0, 0, 0, 0.4)                # empty 凹槽
			ssb.border_color = Color(0, 0, 0, 0.45)
		ssb.set_border_width_all(2)
		ssb.set_corner_radius_all(9)
		# PoC .poc-bench-slot img/emoji 居中且小于槽 (img 41 于 52 槽) → 内缩 5.5px 用 content_margin 实现
		ssb.content_margin_left = 5.5; ssb.content_margin_right = 5.5
		ssb.content_margin_top = 5.5; ssb.content_margin_bottom = 5.5
		slot.add_theme_stylebox_override("panel", ssb)
		slot.custom_minimum_size = Vector2(HUD_SLOT_SIZE, HUD_SLOT_SIZE)
		if eid != "":
			if _bench_buff_items.has(eid):
				# 单体增益: emoji 图标 (名字首 token, 1:1 PoC buff.icon = name.split[0])
				var bdef: Dictionary = _bench_buff_items[eid]
				var bname: String = str(bdef.get("name", ""))
				var el := Label.new()
				el.text = bname.split(" ")[0] if bname != "" else "✨"
				el.set_anchors_preset(Control.PRESET_FULL_RECT)
				el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				el.add_theme_font_size_override("font_size", 30)
				el.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot.add_child(el)
				slot.tooltip_text = "%s\n%s" % [bname, str(bdef.get("desc", ""))]
			elif not p2def.is_empty():
				# p2eq 备战席格: 有 img(.png 按机制对齐PoC装备图)用图, 无图回退 emoji
				var _b_rel := str(p2def.get("img", ""))
				var _b_full := "res://assets/sprites/%s" % _b_rel if _b_rel != "" else ""
				if _b_full != "" and ResourceLoader.exists(_b_full):
					var bic := TextureRect.new()
					bic.texture = load(_b_full)
					bic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					bic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					bic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					bic.mouse_filter = Control.MOUSE_FILTER_IGNORE
					slot.add_child(bic)
				else:
					var pl2 := Label.new()
					pl2.text = str(p2def.get("emoji", "📦"))
					pl2.set_anchors_preset(Control.PRESET_FULL_RECT)
					pl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					pl2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					pl2.add_theme_font_size_override("font_size", 28)
					pl2.mouse_filter = Control.MOUSE_FILTER_IGNORE
					slot.add_child(pl2)
				slot.tooltip_text = str(p2def.get("name", eid))
			else:
				var eq_def: Dictionary = DataRegistry.equipment_by_id.get(eid, {})
				var icon_rel: String = eq_def.get("icon", "")
				var ipath := "res://assets/sprites/%s" % icon_rel if icon_rel.ends_with(".png") else ""
				if ipath != "" and ResourceLoader.exists(ipath):
					var ic := TextureRect.new()
					ic.texture = load(ipath)
					ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					slot.add_child(ic)
					slot.tooltip_text = EquipmentRuntime.display_name(eid)
				elif icon_rel != "":
					# emoji 图标 (口哨 📯 等 special, 无 png) — 1:1 PoC ghost/icon 用 emoji
					var eel := Label.new()
					eel.text = icon_rel
					eel.set_anchors_preset(Control.PRESET_FULL_RECT)
					eel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					eel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					eel.add_theme_font_size_override("font_size", 28)
					eel.mouse_filter = Control.MOUSE_FILTER_IGNORE
					slot.add_child(eel)
					slot.tooltip_text = str(eq_def.get("name", eid))
			# 左栏库存格: 按下记待判定; 移动≥5px→拖拽装备, 未移动松手→点击看详情 (1:1 PoC BenchRail:217-251)
			if side == "left":
				slot.mouse_filter = Control.MOUSE_FILTER_STOP
				slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				var act: String = str(DataRegistry.equipment_by_id.get(eid, {}).get("actionable", ""))
				if act == "blow":
					# 训龟大师口哨: 点击「吹响」召唤大师 (不可装备→不走拖拽); 紫色徽标提示 (1:1 PoC onAction 吹响)
					slot.tooltip_text = "训龟大师的口哨 — 点击吹响"
					slot.gui_input.connect(func(ev: InputEvent) -> void:
						if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
							_blow_master_whistle("left"))
					var badge := Label.new()
					badge.text = "吹响"
					badge.add_theme_font_size_override("font_size", 11)
					badge.add_theme_color_override("font_color", Color("#e0b3ff"))
					badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
					badge.add_theme_constant_override("outline_size", 3)
					badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM   # PanelContainer 覆盖锚点→靠文本对齐贴底
					badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
					slot.add_child(badge)
				elif act == "break":
					# 糖果罐: 点击「打碎」按回合掉落 (不可装备→不走拖拽); 黄色徽标 (1:1 PoC onAction 打碎)
					slot.tooltip_text = "糖果罐 — 点击打碎, 按回合掉落奖励"
					slot.gui_input.connect(func(ev: InputEvent) -> void:
						if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
							_break_candy_jar("left"))
					var bbadge := Label.new()
					bbadge.text = "打碎"
					bbadge.add_theme_font_size_override("font_size", 11)
					bbadge.add_theme_color_override("font_color", Color("#ffd93d"))
					bbadge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
					bbadge.add_theme_constant_override("outline_size", 3)
					bbadge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					bbadge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
					bbadge.mouse_filter = Control.MOUSE_FILTER_IGNORE
					slot.add_child(bbadge)
				else:
					var bench_eid := eid
					slot.gui_input.connect(func(ev: InputEvent) -> void:
						if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
							_drag_pending_eid = bench_eid
							_drag_start = get_viewport().get_mouse_position())
					# 出售 = 云顶式拖卖: 把该装备拖到商店区松手即售 (见 _finish_equip_drag); 原格内小红「卖N」钮已删。
		vb.add_child(slot)
	hud_layer.add_child(rail)


## 一侧后备(未装备)装备 id — 装备席列"未上身的库存"(PoC benchInventory).
## 左栏 = per-battle 装备席 bench_inventory (1:1 PoC :311 开战空, 战中掉落/dungeon 跨关才有).
## 右栏 = 敌方后备(暂空; PoC aiDrainBench, Godot AI 直接上身).
## 【勿用 GameState.inventory】那是自创全局累加器, 开局塞满 = 用户报"那么多装备"根因.
func _collect_bench_equips(side: String) -> Array:
	if side == "left":
		return bench_inventory.duplicate()
	return []


## 重建装备席 (库存变化/待装高亮 后刷新)
# 装备席满 (10/10) 补偿: 该侧全员存活龟 +10%maxHp 回血 (有人缺血才触发) — 1:1 PoC addToBench(BattleScene.ts:8268-8280)
func _bench_full_heal(side: String) -> void:
	var any_hurt := false
	for f in fighters:
		if f.get("side", "") == side and f.get("alive", false) and int(f.get("hp", 0)) < int(f.get("maxHp", 0)):
			any_hurt = true
			break
	if not any_hurt:
		battle_log.append_text("[color=#c9a86a]📦 装备席满且全员满血, 装备遗失[/color]\n")
		return
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if f.get("side", "") != side or not f.get("alive", false):
			continue
		var before: int = int(f.get("hp", 0))
		f["hp"] = mini(int(f.get("maxHp", 0)), before + roundi(f.get("maxHp", 0) * 0.10))
		var healed: int = int(f["hp"]) - before
		if healed > 0:
			_spawn_float_text(i, healed, "heal")
			_refresh_slot(i)
	battle_log.append_text("[color=#7fe07f]📦 装备席满, 全员 +10%HP 回血 (装备遗失)[/color]\n")


func _rebuild_bench_rail() -> void:
	if hud_layer == null:
		return
	for nm in ["BenchRail_left", "BenchRail_right"]:
		var old := hud_layer.get_node_or_null(nm)
		if old != null:
			old.queue_free()
	_build_bench_rail()


## 开始拖拽: 建跟随鼠标的残影 — 44×44 框(深底+金边) + 38 图标, 1:1 PoC BenchRail:223-226
func _start_equip_drag(eid: String) -> void:
	if _drag_layer == null:
		_drag_layer = CanvasLayer.new()
		_drag_layer.layer = 210
		add_child(_drag_layer)
	_end_drag_ghost()
	# 44×44 框 (1:1 PoC BenchRail ghost: 44px 框 + 38px 图标, bg rgba(10,14,24,.85)+2px#ffd966+radius8)。
	#   用 PanelContainer 让图标【布局约束在框内】(原 Panel+绝对定位子节点 size 不夹紧 → 图标溢出框外)。
	#   content_margin 3 → 38 图标 + 6 边 = 44 框。
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(0.039, 0.055, 0.094, 0.85)
	gsb.border_color = Color("#ffd966")
	gsb.set_border_width_all(2)
	gsb.set_corner_radius_all(8)
	gsb.content_margin_left = 3; gsb.content_margin_right = 3
	gsb.content_margin_top = 3; gsb.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", gsb)
	box.modulate = Color(1, 1, 1, 0.9)
	if _bench_buff_items.has(eid):
		# 单体增益残影: emoji (1:1 PoC ghost 用 buff.icon emoji)
		var bname: String = str(_bench_buff_items[eid].get("name", ""))
		var el := Label.new()
		el.text = bname.split(" ")[0] if bname != "" else "✨"
		el.custom_minimum_size = Vector2(38, 38)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		el.add_theme_font_size_override("font_size", 26)
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(el)
	elif not DataRegistry.phase2_equipment_by_id.get(eid, {}).is_empty():
		# p2eq 双路装备: 有 img(.png 按机制对齐PoC装备图)用图(38), 无图回退 emoji。原只走 equipment_by_id 查不到 p2eq → 空白残影
		var _p2d: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
		var _g_rel := str(_p2d.get("img", ""))
		var _g_full := "res://assets/sprites/%s" % _g_rel if _g_rel != "" else ""
		if _g_full != "" and ResourceLoader.exists(_g_full):
			var gic := TextureRect.new()
			gic.texture = load(_g_full)
			gic.custom_minimum_size = Vector2(38, 38)
			gic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			gic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			gic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			gic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(gic)
		else:
			var pl := Label.new()
			pl.text = str(_p2d.get("emoji", "📦"))
			pl.custom_minimum_size = Vector2(38, 38)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			pl.add_theme_font_size_override("font_size", 26)
			pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(pl)
	else:
		var edef: Dictionary = DataRegistry.equipment_by_id.get(eid, {})
		var erel: String = str(edef.get("icon", ""))
		var efull := "res://assets/sprites/%s" % erel if erel != "" else ""
		if efull != "" and ResourceLoader.exists(efull):
			var ic := TextureRect.new()
			ic.texture = load(efull)
			ic.custom_minimum_size = Vector2(38, 38)   # 容器据此夹紧 (非 .size, 后者在容器内不生效)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(ic)
		else:
			box.custom_minimum_size = Vector2(44, 44)
	# 残影跟装备席同空间(内容缩放层), 44 逻辑px → 与席位 52 恒定 44:52 比例随窗口同步缩放,
	#   跟 PoC 残影随页面缩放一致 (之前加反缩固定物理px = 自创错误, 反而比 PoC 小)。
	_drag_layer.add_child(box)
	_drag_ghost = box
	if Engine.has_singleton("CursorTheme") or get_node_or_null("/root/CursorTheme") != null:
		get_node("/root/CursorTheme").force_state("grabbing")   # 拖装备 → 卷爪握拳态
	_update_drag_ghost(get_viewport().get_mouse_position())


func _update_drag_ghost(pos: Vector2) -> void:
	if _drag_ghost != null:
		_drag_ghost.position = pos - Vector2(22, 22)   # 44/2 居中跟手


func _end_drag_ghost() -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null
	_hide_sell_hint()
	if get_node_or_null("/root/CursorTheme") != null:
		get_node("/root/CursorTheme").force_state("")   # 恢复自动光标态


## 云顶式拖卖: 鼠标点(屏幕坐标)是否在常驻商店区内。商店是 CanvasLayer 内 Control(不吃相机) →
##   global_rect 即屏幕像素, 与 get_viewport().get_mouse_position() 同空间, 直接命中测试。
func _point_over_shop(pos: Vector2) -> bool:
	if _battle_shop_root == null or not is_instance_valid(_battle_shop_root):
		return false
	if _battle_shop_layer != null and is_instance_valid(_battle_shop_layer) and not _battle_shop_layer.visible:
		return false
	# 排除备战席矩形: 横排席现落商店正上方 (上下分层, 几何上已不重叠) → 此排除多为冗余守卫;
	#   仍保留, 防 ENVELOP 缩放/留缝边界上"既算席又算商店"的临界点把抓起的装备误判成卖 (见 _finish_equip_drag).
	if _point_over_bench(pos):
		return false
	# 卖区 = 【可见面板】矩形, 非 root 全宽 (用户报: 边距空白也卖). 内嵌 panel 相对 root 内缩 (建店时 offset_left=16/right=-16/top=4/bottom=-8).
	#   优先取真实子 panel 的 global_rect; 取不到 (建店中) 退化为 root 内缩同款边距, 都对齐可见框.
	var sell_rect: Rect2 = _battle_shop_root.get_global_rect()
	var inner: Control = null
	for c in _battle_shop_root.get_children():
		if c is Panel:
			inner = c
			break
	if inner != null and is_instance_valid(inner):
		sell_rect = inner.get_global_rect()
	else:
		sell_rect = Rect2(sell_rect.position + Vector2(16, 4), sell_rect.size - Vector2(32, 12))   # root 内缩 16/16/4/8
	return sell_rect.has_point(pos)


## 落点是否在备战席 rail 矩形内 (左侧库存席, 唯一可拖的来源). 用于商店卖区排除席格.
func _point_over_bench(pos: Vector2) -> bool:
	if hud_layer == null:
		return false
	var rail := hud_layer.get_node_or_null("BenchRail_left")
	if rail is Control and (rail as Control).get_global_rect().has_point(pos):
		return true
	return false


## 拖动过程中, 装备悬在商店区 → 显「出售 +N币」高亮浮层(贴商店区上沿居中); 离开则隐藏。
## eid=正在拖的库存件; 仅可售(phase2 字典席项)才显金色出售提示, 否则不显(buff/口哨拖到商店不可售)。
func _show_sell_hint(eid: String, pos: Vector2) -> void:
	var bidx := _bench_idx_of(eid)
	var sellable := bidx >= 0 and bench_inventory[bidx] is Dictionary
	if not sellable or not _point_over_shop(pos):
		_hide_sell_hint()
		return
	var item: Dictionary = bench_inventory[bidx]
	var amt := GameState.sell_value(str(item.get("id", "")), int(item.get("star", 1)))
	if _sell_hint == null or not is_instance_valid(_sell_hint):
		if _drag_layer == null:
			return
		var box := PanelContainer.new()
		box.name = "SellHint"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hsb := StyleBoxFlat.new()
		hsb.bg_color = Color(0.45, 0.10, 0.10, 0.95)   # 出售=红底金字 (云顶卖区配色)
		hsb.border_color = Color("#ffd966"); hsb.set_border_width_all(2); hsb.set_corner_radius_all(10)
		hsb.content_margin_left = 14; hsb.content_margin_right = 14
		hsb.content_margin_top = 6; hsb.content_margin_bottom = 6
		box.add_theme_stylebox_override("panel", hsb)
		var lbl := Label.new(); lbl.name = "Txt"
		lbl.add_theme_font_override("font", _get_panel_font(true))
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color("#ffe08a"))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lbl)
		_drag_layer.add_child(box)
		_sell_hint = box
		# 商店区四周金色高亮边 (区分"现在落手=卖"): 给商店区临时加发光描边模拟 — 用整块半透明金罩
		_battle_shop_root.modulate = Color(1.25, 1.15, 0.9, 1.0)
	var txt := _sell_hint.get_node_or_null("Txt")
	if txt is Label:
		(txt as Label).text = "💰 出售 +%d币" % amt
	# 贴商店区上沿居中显示
	var srect := _battle_shop_root.get_global_rect()
	_sell_hint.position = Vector2(srect.position.x + srect.size.x / 2.0 - 70.0, srect.position.y - 36.0)


func _hide_sell_hint() -> void:
	if _sell_hint != null and is_instance_valid(_sell_hint):
		_sell_hint.queue_free()
	_sell_hint = null
	if _battle_shop_root != null and is_instance_valid(_battle_shop_root):
		_battle_shop_root.modulate = Color(1, 1, 1, 1)   # 撤销商店区高亮


## 拖拽释放: 物理点查询落点下的左队龟 hitbox → 装上 (复用龟点击 Area2D, 吃相机变换)
## bench 项匹配 (phase1=字符串 / phase2=｛id,star｝字典, 都按 id 找首个匹配), 返 -1 未找到
func _bench_idx_of(eid: String) -> int:
	for i in range(bench_inventory.size()):
		var b = bench_inventory[i]
		var bid: String = str(b.get("id", "")) if b is Dictionary else str(b)
		if bid == eid:
			return i
	return -1


## 备战席某 id 的星级 (云顶式 popup 显当前星属性用). 默认 1.
func _bench_star_of(eid: String) -> int:
	var i := _bench_idx_of(eid)
	if i >= 0 and bench_inventory[i] is Dictionary:
		return int(bench_inventory[i].get("star", 1))
	return 1


func _finish_equip_drag() -> void:
	var eid := _drag_eid
	_drag_eid = ""
	_drag_pending_eid = ""
	var drop_pos: Vector2 = get_viewport().get_mouse_position()
	_end_drag_ghost()
	if eid == "" or _bench_idx_of(eid) < 0:
		return
	# 云顶式拖卖: 松手落在商店区 → 出售退币 (仅 phase2 字典席项可售; buff/口哨等字符串项落商店= sell_bench_item 返 false 不卖)
	if _point_over_shop(drop_pos) and not _bench_buff_items.has(eid):
		var sidx := _bench_idx_of(eid)
		if sidx >= 0 and bench_inventory[sidx] is Dictionary:
			if GameState.sell_bench_item(sidx, "left"):
				_set_deep_coin("left", int(GameState.dual_coins.get("left", 0)), true)
				if is_instance_valid(battle_log):
					var _sn: String = str(DataRegistry.phase2_equipment_by_id.get(eid, {}).get("name", eid))
					battle_log.append_text("[color=#ffd166]💰 出售了「%s」[/color]\n" % _sn)
				_rebuild_bench_rail()
				if _battle_shop_root != null and is_instance_valid(_battle_shop_root):
					_rebuild_battle_shop()
				return
	# wantsEnemy 单体buff(必中标记) 落到敌方(右); 其余落到我方(左)。1:1 PoC benchItem.target='enemy'。
	var want_side := "left"
	if _bench_buff_items.has(eid) and _bench_buff_items[eid].get("wantsEnemy", false):
		want_side = "right"
	var space := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = get_global_mouse_position()
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for h in space.intersect_point(params, 8):
		var col = h.get("collider")
		if col == null:
			continue
		var idx := slot_nodes.find(col.get_parent())
		if idx >= 0 and idx < fighters.size():
			var f: Dictionary = fighters[idx]
			if f.get("side", "") == want_side and f.get("alive", false):
				_equip_from_bench_to(f, eid)
				return


## 把库存件装到龟 f (从 bench_inventory 移除, on_attach + recalc, 刷新席位/槽位)
func _equip_from_bench_to(f: Dictionary, eid: String) -> void:
	if eid == "" or _bench_idx_of(eid) < 0:
		return
	# 单体增益 buff 项: 应用到目标 f (不走装备 attach), 1:1 PoC benchItem.apply(f)
	if _bench_buff_items.has(eid):
		var buff: Dictionary = _bench_buff_items[eid]
		ShopData.apply_single_buff(buff, f)
		bench_inventory.erase(eid)
		_bench_buff_items.erase(eid)
		var ba: Array = []
		for a in fighters:
			if a.get("side", "") == f.get("side", "") and a.get("alive", false):
				ba.append(a)
		StatsRecalc.recalc(f, ba)   # atkUp 等改 stat 后立即生效
		var fi2 := fighters.find(f)
		if fi2 >= 0:
			_spawn_passive_text(fi2, str(buff.get("name", "✨")).split(" ")[0])
			_refresh_slot(fi2)
		if is_instance_valid(battle_log):
			battle_log.append_text("[color=#7dffb3]✨ %s 使用了「%s」[/color]\n" % [str(f.get("name", "?")), str(buff.get("name", ""))])
		_rebuild_bench_rail()
		return
	# 二阶段装备(双路 p2eq): 战中给【任意我方单位(含小将/精英)】装 → apply_stats + 存 _p2_equips + 010授横扫 + recalc
	var p2bidx := _bench_idx_of(eid)
	var p2item = bench_inventory[p2bidx] if p2bidx >= 0 else null
	if p2item is Dictionary and not DataRegistry.phase2_equipment_by_id.get(eid, {}).is_empty():
		# 槽位上限 (随局内等级开放 1-5) — 修原战中拖装绕过 equip_to_turtle 的 cap = 可无限堆装备 (审计)
		var slot_cap: int = Phase2Config.equip_slots_for_level(int(GameState.dual_level.get(str(f.get("side", "left")), 1)))
		if not f.get("_isEgg", false) and (f.get("_p2_equips", []) as Array).size() >= slot_cap:
			var fcap := fighters.find(f)
			if fcap >= 0:
				_spawn_passive_text(fcap, "装备槽满(%d)" % slot_cap, "#ff6b6b")
			return
		var istar: int = int(p2item.get("star", 1))
		bench_inventory.remove_at(p2bidx)
		Phase2EquipRuntime.apply_stats(f, eid, istar)
		if eid == "p2eq_010":
			if not f.has("skills"):
				f["skills"] = []
			(f["skills"] as Array).append({"type": "p2Sweep", "name": "⚡横扫", "energyCost": 0, "cd": 0, "cdLeft": 0, "hits": 1, "icon": "📏", "p2Star": istar, "target": "enemy", "brief": "横扫一列(3★全体)敌人; 只命中1则竖斩; 回血"})
		if not f.has("_p2_equips"):
			f["_p2_equips"] = []
		(f["_p2_equips"] as Array).append({"id": eid, "star": istar})
		var p2allies: Array = []
		for a in fighters:
			if a.get("side", "") == f.get("side", "") and a.get("alive", false):
				p2allies.append(a)
		StatsRecalc.snapshot_base(f)
		StatsRecalc.recalc(f, p2allies)
		if is_instance_valid(battle_log):
			battle_log.append_text("[color=#7dffb3]🔧 %s 装备了「%s」[/color]\n" % [str(f.get("name", "?")), str(DataRegistry.phase2_equipment_by_id.get(eid, {}).get("name", eid))])
		_rebuild_bench_rail()
		var p2fi := fighters.find(f)
		if p2fi >= 0:
			_refresh_slot(p2fi)
		_build_duallane_equip_displays()   # 双路: 战中装备后重刷"龟周围装备"显示 (原只 setup 调一次, 装了不显)
		_refresh_school_chips_all()        # 战中装备改变学派件数 → 重刷学派 chip
		_battle_merge_p2eq()               # 装备后若凑齐3件同款(龟身+席) → 战中3合1(可见)
		return
	bench_inventory.erase(eid)   # 移除一件 (erase 删首个匹配)
	EquipmentRuntime.on_attach(f, eid)
	if not f.has("_equipped_ids"):
		f["_equipped_ids"] = []
	(f["_equipped_ids"] as Array).append(eid)
	var allies: Array = []
	for a in fighters:
		if a.get("side", "") == "left" and a.get("alive", false):
			allies.append(a)
	StatsRecalc.snapshot_base(f)
	StatsRecalc.recalc(f, allies)
	if _tutorial_guide != null:   # 教程: 拖装成功 → 推进步骤 (1:1 PoC notify 'equip-dropped')
		_tutorial_guide.notify("equip-dropped")
	if is_instance_valid(battle_log):
		battle_log.append_text("[color=#7dffb3]🔧 %s 装备了「%s」[/color]\n" % [str(f.get("name", "?")), EquipmentRuntime.display_name(eid)])
	_rebuild_bench_rail()
	var fi := fighters.find(f)
	if fi >= 0:
		_refresh_slot(fi)


## 每回合刷新: 深海币数值(我方/敌方) + 羁绊 chip (阵容固定但首回合后才有数据).
func _refresh_battle_hud() -> void:
	if hud_layer == null:
		return
	# 伤害统计面板开着就跟着刷 (PoC bus 'stats:updated'; Godot 无 bus → 挂每回合 HUD 刷新)
	if _dmg_stats_panel != null and _dmg_stats_panel.visible:
		_render_dmg_stats()
	# F8: 战斗日志封顶 200 段 (1:1 PoC BattleLog MAX_LINES=200), 删最旧
	if battle_log != null:
		while battle_log.get_paragraph_count() > 200:
			battle_log.remove_paragraph(0)
	# count-up 滚动 + 变化脉冲 (PoC setDeepCoin): 仅当值变了才 pulse
	# 双路用局内币 dual_coins (商店花的是它); 老模式用 battle_coins/enemy_coins
	var _dl: bool = GameState.mode == "duallane"
	var _lc: int = int(GameState.dual_coins.get("left", 0)) if _dl else GameState.battle_coins
	var _rc: int = int(GameState.dual_coins.get("right", 0)) if _dl else GameState.enemy_coins
	if _deep_coin_val_l:
		if _dl:   # V2 阶段1: 局内不显深海币 (经济挪局外) -> 隐藏左 pill (同右侧)
			if _deep_coin_pill_l != null and is_instance_valid(_deep_coin_pill_l):
				_deep_coin_pill_l.visible = false
		else:
			_set_deep_coin("left", _lc, _lc != _deep_coin_shown_l)
	if _deep_coin_val_r:
		if _dl:   # 双路: 线上只看自己侧 → 隐藏敌方(右)深海币 pill (同敌方装备席已隐藏)
			if _deep_coin_pill_r != null and is_instance_valid(_deep_coin_pill_r):
				_deep_coin_pill_r.visible = false
		else:
			_set_deep_coin("right", _rc, _rc != _deep_coin_shown_r)
	var left_team: Array = []
	var right_team: Array = []
	for f in fighters:
		if f.get("side", "") == "left":
			left_team.append(f)
		elif f.get("side", "") == "right":
			right_team.append(f)
	if GameState.mode == "duallane":
		# 双路: 显装备套装【学派】chip (Phase2Schools 计数), 替代已移除的乌龟羁绊; 线上只看自己(左), 敌方羁绊不显
		_render_school_chips("left", left_team)
	else:
		_render_synergy("left", Synergies.calc_active(left_team))
		_render_synergy("right", Synergies.calc_active(right_team))


## 标题"第N回合"做成居中金边药丸 (PoC BattleTopRow .turn-banner: 渐变底/2px金边/发光);
## 日志开关 📜 默认隐藏日志 (PoC battle.css .battle-log{display:none}, 点 📜 才开).
func _style_top_chrome() -> void:
	if title_label:
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(0.078, 0.106, 0.196, 0.96)   # rgba(20,27,50,.96) 渐变近似
		pill.border_color = Color("#ffd86b")
		pill.set_border_width_all(2)
		pill.set_corner_radius_all(14)
		pill.content_margin_left = 30; pill.content_margin_right = 30
		pill.content_margin_top = 8; pill.content_margin_bottom = 8
		pill.shadow_color = Color(1, 0.85, 0.42, 0.3)
		pill.shadow_size = 10
		title_label.add_theme_stylebox_override("normal", pill)
		title_label.add_theme_color_override("font_color", Color("#ffe9a8"))
		title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# 日志开关
	var toggle: Button = get_node_or_null("UI/LogToggle")
	if toggle:
		toggle.toggle_mode = true
		toggle.pressed.connect(_on_log_toggle)
	var lp: Panel = get_node_or_null("UI/LogPanel")
	if lp:
		var lsb := StyleBoxFlat.new()
		lsb.bg_color = Color(0.031, 0.043, 0.071, 0.86)   # rgba(8,11,18,.86) PoC .battle-log 底
		lsb.border_color = Color("#6b5430")               # 金棕左边框
		lsb.border_width_left = 2
		lp.add_theme_stylebox_override("panel", lsb)
		lp.self_modulate = Color(1, 1, 1, 1)


func _on_log_toggle() -> void:
	var lp: Panel = get_node_or_null("UI/LogPanel")
	if lp:
		lp.visible = not lp.visible


# ══════════════════════════════════════════════════════════════
# 伤害统计面板 (1:1 PoC DmgStatsPanel.ts:26-229)
#   top56 left12 w540, 4 tab(造成/承受/治疗/护盾) × 双列(我方/敌方) × stacked bar.
#   数据来自 battle_stats.by_side(); 过滤 isNeutral; 各列按当前 tab 值降序; 阵亡行半透.
#   (省略 emoji — Godot 默认字体无彩色 emoji; 用纯中文标签)
# ══════════════════════════════════════════════════════════════
const _DS_TABS := [["dealt", "⚔ 造成"], ["taken", "🛡 承受"], ["heal", "💚 治疗"], ["shield", "🔵 护盾"]]

func _on_dmg_stats_toggle() -> void:
	if _dmg_stats_panel == null:
		_build_dmg_stats_panel()
	_dmg_stats_panel.visible = not _dmg_stats_panel.visible
	if _dmg_stats_panel.visible:
		_render_dmg_stats()


func _build_dmg_stats_panel() -> void:
	var p := PanelContainer.new()
	p.name = "DmgStatsPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.075, 0.11, 0.97)        # PoC linear-gradient 暗底近似
	sb.border_color = Color("#6b5430")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 12; sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.6); sb.shadow_size = 8
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(12, 56)                          # PoC top:56 left:12

	var col_root := VBoxContainer.new()
	col_root.add_theme_constant_override("separation", 10)
	col_root.custom_minimum_size = Vector2(508, 0)        # 540 - 2*16 margin
	p.add_child(col_root)

	# 标题行 + 关闭
	var hdr := HBoxContainer.new()
	var title := Label.new()
	title.text = "📊 战斗统计"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#ffd86b"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.add_theme_font_size_override("font_size", 22)   # PoC .dmg-close font-size:22px
	close.add_theme_color_override("font_color", Color("#8b949e"))
	close.pressed.connect(func() -> void: _dmg_stats_panel.visible = false)
	hdr.add_child(close)
	col_root.add_child(hdr)

	# tab 行
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_dmg_stats_tab_btns = {}
	for t in _DS_TABS:
		var key: String = t[0]
		var b := Button.new()
		b.text = t[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)   # PoC .ds-tab font-size:14px
		b.pressed.connect(func() -> void:
			_dmg_stats_tab = key
			_update_ds_tab_styles()
			_render_dmg_stats())
		tabs.add_child(b)
		_dmg_stats_tab_btns[key] = b
	col_root.add_child(tabs)

	# 双列 (我方 / 敌方)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	_dmg_stats_cols = []
	for label_text in ["我方", "敌方"]:
		var colv := VBoxContainer.new()
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colv.add_theme_constant_override("separation", 5)
		var cl := Label.new()
		cl.text = label_text
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.add_theme_font_size_override("font_size", 13)
		cl.add_theme_color_override("font_color", Color("#c9d1d9"))
		colv.add_child(cl)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 5)
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colv.add_child(rows)
		cols.add_child(colv)
		_dmg_stats_cols.append(rows)
	col_root.add_child(cols)

	p.visible = false
	hud_layer.add_child(p)
	_dmg_stats_panel = p
	_update_ds_tab_styles()


## tab 高亮 (active = 蓝底白字, PoC .ds-tabs .active)
func _update_ds_tab_styles() -> void:
	for key in _dmg_stats_tab_btns:
		var b: Button = _dmg_stats_tab_btns[key]
		var active: bool = key == _dmg_stats_tab
		var s := StyleBoxFlat.new()
		# active = 蓝底(PoC gradient #6db3ff→#3d82e0 纯色近似) 白字 边#8fc4ff; inactive = 白@.05 字#8b949e 边白@.08
		s.bg_color = Color(0.26, 0.55, 0.88) if active else Color(1, 1, 1, 0.05)
		s.set_corner_radius_all(8)                          # PoC .ds-tab border-radius:8px
		s.content_margin_top = 8; s.content_margin_bottom = 8   # PoC padding:8px 0
		s.content_margin_left = 0; s.content_margin_right = 0
		s.set_border_width_all(1)                           # PoC border:1px
		s.border_color = Color("#8fc4ff") if active else Color(1, 1, 1, 0.08)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, s)
		b.add_theme_color_override("font_color", Color("#ffffff") if active else Color("#8b949e"))


## 当前 tab 的统计值 (排序/显示用)
func _ds_val(s: Dictionary, tab: String) -> int:
	match tab:
		"dealt": return int(s.get("dmgDealt", 0))
		"taken": return int(s.get("dmgTaken", 0))
		"heal": return int(s.get("healDone", 0))
		"shield": return int(s.get("shieldGained", 0))
	return 0


## 当前 tab 的 bar 分段 [[值, 色], ...] (PoC battle.css 配色, alpha 同 PoC)
func _ds_parts(s: Dictionary, tab: String) -> Array:
	if tab == "dealt" or tab == "taken":
		var bt: Dictionary = s.get("dmgDealtByType" if tab == "dealt" else "dmgTakenByType", {})
		return [
			[int(bt.get("phy", 0)), Color(1, 0.267, 0.267, 0.6)],                       # 物理红
			[int(bt.get("mag", 0)), Color(0.302, 0.671, 0.969, 0.6)],                   # 法术蓝
			[int(bt.get("tru", 0)) + int(bt.get("dot", 0)), Color(1, 1, 1, 0.6)],       # 真实+DoT 白
		]
	elif tab == "heal":
		return [[int(s.get("healDone", 0)), Color(0.024, 0.839, 0.627, 0.65)]]          # 绿
	else:
		return [[int(s.get("shieldGained", 0)), Color(0.345, 0.827, 1, 0.6)]]            # 青


## stacked bar: 各段按值占比 (stretch_ratio), 余量= col_max 内空轨.
## 1:1 PoC .ds-bar-wrap (DmgStatsPanel.ts): height:12 / border-radius:4 / overflow:hidden / bg空轨rgba(255,255,255,.05).
##   原 Godot 用裸 ColorRect HBox = 方角(用户报"方的条"); 改: 圆角Panel包裹(corner4)+clip + 透明余量露圆角轨.
func _make_ds_bar(parts: Array, col_max: int) -> Control:
	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(0, 12)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = true                            # PoC overflow:hidden
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(1, 1, 1, 0.05)                  # 空轨 rgba(255,255,255,.05)
	wsb.set_corner_radius_all(4)                         # 1:1 PoC border-radius:4
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
	var spacer := Control.new()                          # 透明余量 → 露出 wrap 圆角空轨 bg
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = maxf(0.0001, float(rem))
	hb.add_child(spacer)
	wrap.add_child(hb)
	return wrap


func _make_ds_row(s: Dictionary, side: String, col_max: int) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var f: Dictionary = s.get("_fighter", {})
	if not bool(f.get("alive", true)):
		row.modulate.a = 0.4                            # PoC .ds-dead opacity .4
	var top := HBoxContainer.new()
	var nm := Label.new()
	nm.text = str(s.get("name", ""))
	nm.add_theme_font_size_override("font_size", 15)   # PoC .ds-name font-size:15px
	nm.add_theme_color_override("font_color", Color("#06d6a0") if side == "left" else Color("#ff6b6b"))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var val := Label.new()
	val.text = str(_ds_val(s, _dmg_stats_tab))
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", Color("#e6edf3"))
	top.add_child(val)
	row.add_child(top)
	row.add_child(_make_ds_bar(_ds_parts(s, _dmg_stats_tab), col_max))
	return row


func _render_dmg_stats() -> void:
	if _dmg_stats_cols.size() < 2:
		return
	var sides := ["left", "right"]
	for ci in range(2):
		var side: String = sides[ci]
		var rows_vb: VBoxContainer = _dmg_stats_cols[ci]
		for c in rows_vb.get_children():
			rows_vb.remove_child(c)
			c.queue_free()
		var list: Array = []
		for s in battle_stats.by_side(side):
			if s.get("isNeutral", false):
				continue
			list.append(s)
		var tab := _dmg_stats_tab
		list.sort_custom(func(a, b): return _ds_val(a, tab) > _ds_val(b, tab))
		var col_max := 1
		for s in list:
			col_max = maxi(col_max, _ds_val(s, tab))
		for s in list:
			rows_vb.add_child(_make_ds_row(s, side, col_max))


# ══════════════════════════════════════════════════════════════
# 点龟详情面板 (1:1 PoC DetailPanel.ts) — 点战斗中任意龟弹出.
#   header(头像/名/Lv/HP) + 8项属性 + 10装备格 + 技能 tile + veil点空白关 + 同龟再点关.
#   (v1: 省略 装备弹窗/技能蓄力大卡/状态列/宝箱专属模式 — 二期; 已覆盖用户报的"点了没面板")
# ══════════════════════════════════════════════════════════════
func _rarity_color(r: String) -> Color:
	match r:
		"SSS": return Color("#ff6b6b")
		"SS": return Color("#ffd93d")
		"S": return Color("#c77dff")
		"A": return Color("#3a9abf")
		"B": return Color("#4cc9f0")
		_: return Color("#06d6a0")   # C


func _hide_fighter_detail() -> void:
	_hover_token += 1   # 修(审计): 关面板作废待触发的 hover 开卡定时器 (否则点veil关板后 0.7s 仍冒出技能卡)
	_clear_hover_ring()
	if _skill_card_layer != null and is_instance_valid(_skill_card_layer):
		_skill_card_layer.queue_free()   # 关面板连带关技能大卡
	_skill_card_layer = null
	if _detail_layer != null and is_instance_valid(_detail_layer):
		_detail_layer.queue_free()
	_detail_layer = null
	_detail_fighter_uid = -99
	_resume_turn_timer()   # 决策态看完 ⓘ 信息关面板 → 从暂停处续跑倒计时 (无暂停态=no-op)


## 点龟身 → 是否弹详情面板 (方案A, 用户 2026-06-25, 删长按; 抽出供单测).
##   决策态(was_decision = _picker_active or _targeting_active): 点龟身=出手/选靶, 抑制面板 (看信息走 ⓘ 钮)。
##   闲置态: 点龟身=弹面板。
func _should_open_detail(was_decision: bool) -> bool:
	return not was_decision


func _show_fighter_detail(f: Dictionary) -> void:
	var uid: int = int(f.get("_uid", -1))
	if _detail_layer != null and is_instance_valid(_detail_layer) and _detail_fighter_uid == uid:
		_hide_fighter_detail()      # 同一只再点 → 关 (PoC toggle)
		return
	_build_fighter_detail(f)
	_detail_fighter_uid = uid


## 分隔线 (1:1 PoC border-top 1px rgba(255,255,255,.1), 见 fdp-equip-wrap/skills-wrap): 1px 白.1 横线 (替默认HSeparator灰).
func _detail_divider() -> Control:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(1, 1, 1, 0.1)   # rgba(255,255,255,.1)
	line.add_theme_stylebox_override("panel", lsb)
	return line


## 区块标题 (1:1 PoC .fdp-col-label DetailPanel.ts:210-220): 左侧 3px 金渐变竖条(#ffe27a→#ffb01f) + 13px 标题. 原缺竖条.
func _detail_col_label(txt: String, col: Color) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)   # PoC padding-left:8 (竖条到字)
	var bar := TextureRect.new()
	var bgrad := Gradient.new()
	bgrad.set_color(0, Color("#ffe27a")); bgrad.set_color(1, Color("#ffb01f"))   # PoC linear-gradient(180deg,#ffe27a,#ffb01f)
	var btex := GradientTexture2D.new()
	btex.gradient = bgrad
	btex.width = 3; btex.height = 14
	btex.fill_from = Vector2(0, 0); btex.fill_to = Vector2(0, 1)
	bar.texture = btex
	bar.custom_minimum_size = Vector2(3, 13)
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", col)
	box.add_child(lbl)
	return box


## 属性比初始值: 1=增益(绿) / -1=减益(红) / 0=不变(白) — 1:1 PoC sc() fdp-up/fdp-down
func _stat_ud(cur: float, init_v: float) -> int:
	return 1 if cur > init_v else (-1 if cur < init_v else 0)


func _detail_stat_chip(icon_rel: String, label_txt: String, value_txt: String, tip: String = "", updown: int = 0) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 7)   # 1:1 PoC fdp-stat gap:7px
	var ipath := "res://assets/sprites/stats/%s" % icon_rel
	if ResourceLoader.exists(ipath):
		var ic := TextureRect.new()
		ic.texture = load(ipath)
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		chip.add_child(ic)
	else:
		var ll := Label.new()
		ll.text = label_txt + ":"
		ll.add_theme_font_size_override("font_size", 12)
		ll.add_theme_color_override("font_color", Color("#9aa6b2"))
		chip.add_child(ll)
	var vl := Label.new()
	vl.text = value_txt
	vl.add_theme_font_size_override("font_size", 14)
	# 增益绿/减益红/不变白 (1:1 PoC fdp-up #06d6a0 / fdp-down #ff6b6b vs 初始值; 原永远白)
	var vcol := Color("#e6edf3")
	if updown > 0:
		vcol = Color("#06d6a0")
	elif updown < 0:
		vcol = Color("#ff6b6b")
	vl.add_theme_color_override("font_color", vcol)
	chip.add_child(vl)
	chip.tooltip_text = tip if tip != "" else ("%s = %s" % [label_txt, value_txt])   # PoC data-tip (护甲/魔抗含减免%)
	return chip


## HP 子资源进度条 (1:1 PoC .fdp-wall-line + .fdp-wall-bar): 行标签(名+值) + 比例填充条
## wall_style=true → 用 PoC .fdp-wall-bar 样式 (HP条下资源条: 坚壁/泡泡/怒气/财宝/储能, 高8金槽#ffd45c标);
##   false → PoC .fdp-meter (属性区小条, 高5黑槽). 二者 PoC 是不同 class.
func _detail_meter(label_txt: String, val_txt: String, pct: float, fill_col: Color, wall_style: bool = false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3 if wall_style else 2)   # PoC wall-line margin-bottom:3
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4 if wall_style else 5)   # PoC wall-line gap:4
	var nl := Label.new()
	nl.text = label_txt
	nl.add_theme_font_size_override("font_size", 11)
	nl.add_theme_color_override("font_color", Color("#ffd45c") if wall_style else Color(1, 1, 1, 0.8))   # PoC .fdp-wall-line color:#ffd45c
	line.add_child(nl)
	var vl := Label.new()
	vl.text = val_txt
	vl.add_theme_font_size_override("font_size", 11)
	vl.add_theme_color_override("font_color", Color("#ffe9a8") if wall_style else fill_col)   # PoC .fdp-wall-val color:#ffe9a8 (恒, 非bar色)
	line.add_child(vl)
	box.add_child(line)
	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(0, 8 if wall_style else 5)   # PoC .fdp-wall-bar height:8 / .fdp-meter height:5
	var tsb := StyleBoxFlat.new()
	if wall_style:
		tsb.bg_color = Color(1.0, 200.0 / 255.0, 80.0 / 255.0, 0.12)   # PoC .fdp-wall-bar bg rgba(255,200,80,.12)
		tsb.border_color = Color(1.0, 200.0 / 255.0, 80.0 / 255.0, 0.3)   # border rgba(255,200,80,.3)
		tsb.set_corner_radius_all(5)   # PoC border-radius:5
	else:
		tsb.bg_color = Color(0, 0, 0, 0.5)   # 1:1 PoC fdp-meter background rgba(0,0,0,.5) (原.35)
		tsb.set_corner_radius_all(3)
		tsb.border_color = Color(1, 1, 1, 0.12)   # 1:1 PoC border:1px rgba(255,255,255,.12) (原无边)
	tsb.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", tsb)
	var fillbox := HBoxContainer.new()
	fillbox.add_theme_constant_override("separation", 0)
	var fr := ColorRect.new()
	fr.color = fill_col
	fr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr.size_flags_stretch_ratio = maxf(0.0001, pct)
	fillbox.add_child(fr)
	var rem := ColorRect.new()
	rem.color = Color(0, 0, 0, 0)
	rem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rem.size_flags_stretch_ratio = maxf(0.0001, 100.0 - pct)
	fillbox.add_child(rem)
	track.add_child(fillbox)
	box.add_child(track)
	return box


## 技能/被动 tile (1:1 PoC fdp-skill): 54框图标(+可选右上"+"角标) + 名 + ("被动"pill 或 CD文字)
func _detail_skill_tile(icon_full: String, emoji_fb: String, nm: String, sub_text: String, is_passive: bool, show_plus: bool) -> Control:
	# 1:1 PoC .fdp-skill.fdp-skill-compact (DetailPanel.ts:459-465): tile 无底无框(透明), 仅图标有金框 socket
	var st := VBoxContainer.new()
	st.alignment = BoxContainer.ALIGNMENT_BEGIN   # 1:1 PoC flex-start 顶对齐
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # 1:1 PoC .fdp-skill flex:1 1 0 — tile 弹性平分整行(原 shrink → 挤一边)
	st.add_theme_constant_override("separation", 5)   # PoC fdp-skill-compact gap:5px
	# 图标 socket (PoC .fdp-skill-icon 64×64 金框, 被动/主动同款 — 原自创绿/蓝 socket)
	var skb := PanelContainer.new()
	skb.custom_minimum_size = Vector2(64, 64)
	skb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # 1:1 PoC .fdp-skill-icon 恒64×64方框 — 原FILL会被长技能名拉宽变扁
	var sksb := StyleBoxFlat.new()
	sksb.bg_color = Color(0, 0, 0, 0.3)                       # PoC bg rgba(0,0,0,.3)
	sksb.border_color = Color(1.0, 0.851, 0.239, 0.55)       # PoC border rgba(255,217,61,.55) 金
	sksb.set_border_width_all(2)
	sksb.set_corner_radius_all(10)
	sksb.shadow_color = Color(0, 0, 0, 0.45); sksb.shadow_size = 4   # 1:1 PoC socket 投影
	skb.add_theme_stylebox_override("panel", sksb)
	var icon_area := Control.new()
	icon_area.custom_minimum_size = Vector2(58, 58)
	if icon_full != "" and ResourceLoader.exists(icon_full):
		var ski := TextureRect.new()
		ski.texture = load(icon_full)
		ski.set_anchors_preset(Control.PRESET_FULL_RECT)
		ski.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ski.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ski.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_area.add_child(ski)
	else:
		var el := Label.new()
		el.text = emoji_fb
		el.add_theme_font_size_override("font_size", 38 if emoji_fb.length() <= 1 else 16)   # 1:1 PoC fdp-skill-icon-emoji 38px (原36)
		el.set_anchors_preset(Control.PRESET_FULL_RECT)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_area.add_child(el)
	if show_plus:   # 强化被动 "+" 角标 (PoC .fdp-skill-plus 绿圆#06d6a0 17px 黑边, 原自创黄)
		var plb := PanelContainer.new()
		plb.custom_minimum_size = Vector2(22, 22)   # 1:1 PoC .fdp-skill-plus min-width:22 height:22 (满圆)
		var plsb := StyleBoxFlat.new()
		plsb.bg_color = Color("#06d6a0")
		plsb.set_corner_radius_all(11)
		plsb.border_color = Color("#0c1018")
		plsb.set_border_width_all(2)
		plsb.shadow_color = Color(0, 0, 0, 0.55); plsb.shadow_size = 3   # 1:1 PoC +N 徽章投影
		plsb.content_margin_left = 3; plsb.content_margin_right = 3
		plb.add_theme_stylebox_override("panel", plsb)
		var pl := Label.new()
		pl.text = "+"
		pl.add_theme_font_size_override("font_size", 17)
		pl.add_theme_color_override("font_color", Color("#05382a"))
		pl.add_theme_font_override("font", _get_panel_font(true))   # 1:1 PoC +N weight 900
		plb.add_child(pl)
		plb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		plb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		plb.grow_vertical = Control.GROW_DIRECTION_END
		plb.position += Vector2(5, -5)
		icon_area.add_child(plb)
	skb.add_child(icon_area)
	st.add_child(skb)
	var skn := Label.new()
	skn.text = nm
	skn.add_theme_font_size_override("font_size", 15)        # PoC .fdp-skill-name font-size:15px (原11)
	skn.add_theme_color_override("font_color", Color("#e6edf3"))
	skn.add_theme_font_override("font", _get_panel_font(true))   # 1:1 PoC font-weight:700
	skn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skn.clip_text = true   # 1:1 PoC .fdp-skill-name nowrap/ellipsis — 防长名撑宽 tile 破坏平分填充
	skn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # 1:1 PoC text-overflow:ellipsis
	st.add_child(skn)
	if is_passive:
		# PoC .fdp-passive-tag: 纯紫文字 #c77dff 11px bold (无底, 原自创绿底)
		var tl := Label.new()
		tl.text = "被动"
		tl.add_theme_font_size_override("font_size", 11)
		tl.add_theme_color_override("font_color", Color("#c77dff"))
		tl.add_theme_font_override("font", _get_panel_font(true))   # 1:1 PoC .fdp-passive-tag weight 700
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.add_child(tl)
	elif sub_text != "":
		var cdl := Label.new()
		cdl.text = sub_text
		cdl.add_theme_font_size_override("font_size", 10)
		cdl.add_theme_color_override("font_color", Color("#ff6b6b"))   # PoC .fdp-cd #ff6b6b 红 (原灰)
		cdl.add_theme_font_override("font", _get_panel_font(true))   # 1:1 PoC .fdp-cd weight 700
		cdl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.add_child(cdl)
	return st


## 信息面板 技能/被动 tile 点击 → 弹描述大卡 (1:1 PoC 点 tile 出 skillCard/被动大卡)
## 被动卡实时状态行 (1:1 PoC DetailPanel.ts buildPassiveParts state 1448-1488): 4 被动显当前值, 余空.
func _passive_state_line(f: Dictionary, pas: Dictionary) -> String:
	match str(pas.get("type", "")):
		"fortuneGold":
			return "🪙 金币：%d" % int(f.get("_goldCoins", 0))
		"hunterKill":
			return "🎯 击杀数：%d　窃取攻+%d 防+%d 抗+%d 血+%d" % [int(f.get("_hunterKills", 0)), int(f.get("_hunterStolenAtk", 0)), int(f.get("_hunterStolenDef", 0)), int(f.get("_hunterStolenMr", 0)), int(f.get("_hunterStolenHp", 0))]
		"gamblerBlood":
			var oc: float = maxf(0.0, float(f.get("crit", 0.0)) - 1.0)
			return "🩸 暴击溢出：%s" % (("%d%%→+%d%%爆伤" % [roundi(oc * 100.0), roundi(oc * float(pas.get("overflowMult", 1.5)) * 100.0)]) if oc > 0.0 else "无")
		"undeadRage":
			var bonus: int = roundi(minf(float(pas.get("atkMaxBonus", 0)), (1.0 - float(f.get("hp", 0)) / maxf(1.0, float(f.get("maxHp", 1)))) * 100.0 * float(pas.get("atkPerLostPct", 0))))
			return "💀 攻击加成：+%d%%　生命偷取：%d%%" % [bonus, int(pas.get("lifestealBase", 0))]
	return ""


## 双形态龟(双头/火山): 当前技能在「另一形态」同 index 的配对技能 (1:1 PoC pairedFormSkill)。
##   返回 {skill, label, color} 或 {} (无配对)。融合(_isCommon)不配对。
func _paired_form_skill(f: Dictionary, cur: Dictionary) -> Dictionary:
	if cur.get("_isCommon", false):
		return {}
	var petdef: Dictionary = DataRegistry.pet_by_id.get(str(f.get("id", "")), {})
	if petdef.is_empty():
		return {}
	var melee: Array = petdef.get("meleeSkills", [])
	var volcano: Array = petdef.get("volcanoSkills", [])
	var pool: Array = petdef.get("skillPool", [])
	var src: Array = []
	var other: Array = []
	var label := ""
	var color := ""
	if melee is Array and not melee.is_empty():
		var in_melee: bool = f.has("_rangedSkills")   # 近战形态: 远程套已暂存到 _rangedSkills
		src = melee if in_melee else pool
		other = pool if in_melee else melee
		label = "远程形态" if in_melee else "近战形态"
		color = "#7ec8ff"
	elif volcano is Array and not volcano.is_empty() and str(f.get("name", "")) != "火山龟":
		src = pool; other = volcano; label = "火山形态"; color = "#ff8a3d"
	if src.is_empty() or other.is_empty():
		return {}
	var orig_idx := -1
	for i in range(src.size()):
		var sx = src[i]
		if sx is Dictionary and str(sx.get("type", "")) == str(cur.get("type", "")) and str(sx.get("name", "")) == str(cur.get("name", "")):
			orig_idx = i
			break
	if orig_idx < 0 or orig_idx >= other.size():
		return {}
	var oth = other[orig_idx]
	if not (oth is Dictionary) or str(oth.get("name", "")) == str(cur.get("name", "")):
		return {}
	return {"skill": oth, "label": label, "color": color}


## 被动状态行 bbcode 后缀 (空=非状态被动)。大卡实时拼用。
func _passive_state_suffix(rf_f: Dictionary, rf_pas: Dictionary) -> String:
	if rf_f.is_empty() or rf_pas.is_empty():
		return ""
	var st: String = _passive_state_line(rf_f, rf_pas)
	return (char(10) + "[color=#9fd6ff]" + st + "[/color]") if st != "" else ""


## _process: 被动大卡开着时实时刷新状态行(展开详细时不刷)。
func _refresh_skill_card_state() -> void:
	if _skill_card_refresh.is_empty():
		return
	var bn = _skill_card_refresh.get("body")
	var exp = _skill_card_refresh.get("expanded", [false])
	if bn == null or not is_instance_valid(bn) or (exp is Array and exp.size() > 0 and bool(exp[0])):
		return
	(bn as RichTextLabel).text = str(_skill_card_refresh.get("base", "")) + _passive_state_suffix(_skill_card_refresh.get("f", {}), _skill_card_refresh.get("pas", {}))


## 悬浮蓄力圈 (1:1 PoC startSkillRing): tile 中心画金色进度弧, 0.7s 填满 → 开大卡。
func _show_hover_ring(tile: Control) -> void:
	_clear_hover_ring()
	if not is_instance_valid(tile):
		return
	var layer := CanvasLayer.new()
	layer.layer = 65   # 详情面板(60)之上, 大卡(70)之下
	add_child(layer)
	_hover_ring = layer
	var ring := Control.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = tile.get_global_rect().get_center()
	var prog := [0.0]
	ring.draw.connect(func() -> void:
		ring.draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 3.0, true)
		if prog[0] > 0.001:
			ring.draw_arc(Vector2.ZERO, 22.0, -PI / 2.0, -PI / 2.0 + prog[0] * TAU, 48, Color("#ffd766"), 3.0, true))
	layer.add_child(ring)
	var tw := create_tween()
	tw.tween_method(func(v: float): prog[0] = v; if is_instance_valid(ring): ring.queue_redraw(), 0.0, 1.0, 0.7)


## 清蓄力圈。
func _clear_hover_ring() -> void:
	if _hover_ring != null and is_instance_valid(_hover_ring):
		_hover_ring.queue_free()
	_hover_ring = null


func _make_detail_tile_clickable(tile: Control, title_txt: String, icon_full: String, body_bbcode: String, detail_bbcode: String = "", rf_f: Dictionary = {}, rf_pas: Dictionary = {}) -> void:
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 子控件(图标socket/名/CD)默认 mouse_filter=STOP 会吞掉点击 → tile.gui_input 永不触发(点技能tile没反应=预览不出)。
	#   递归设子节点 IGNORE, 让点击落到 tile 本身。
	_detail_ignore_children_mouse(tile)
	_detail_tiles.append({"node": tile, "title": title_txt, "icon": icon_full, "body": body_bbcode, "detail": detail_bbcode, "rf_f": rf_f, "rf_pas": rf_pas})   # 注册(大卡开着时点此 tile 直接切换)
	tile.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_skill_desc_popup(title_txt, icon_full, body_bbcode, detail_bbcode, rf_f, rf_pas))
	# 悬浮 0.7s 自动开大卡 + 蓄力进度圈 (1:1 PoC startSkillRing — Steam 式 hover-open)
	tile.mouse_entered.connect(func() -> void:
		_hover_token += 1
		var my_token: int = _hover_token
		_show_hover_ring(tile)
		_detail_hover_scale(tile, true)   # 1:1 PoC .fdp-skill-icon:hover 即时放大1.06 + 金边亮 + 金色辉光
		var ht := get_tree().create_timer(0.7)
		ht.timeout.connect(func() -> void:
			if _hover_token == my_token:
				_clear_hover_ring()
				_show_skill_desc_popup(title_txt, icon_full, body_bbcode, detail_bbcode, rf_f, rf_pas)))
	tile.mouse_exited.connect(func() -> void:
		_hover_token += 1
		_clear_hover_ring()
		_detail_hover_scale(tile, false))


## 1:1 PoC .fdp-skill-icon:hover (DetailPanel.ts:438-441) — 悬浮即时: 图标socket放大1.06 + 金边变亮#ffe9a8 + 金色辉光。
func _detail_hover_scale(tile: Control, on: bool) -> void:
	if not is_instance_valid(tile) or tile.get_child_count() == 0:
		return
	var first = tile.get_child(0)   # _detail_skill_tile 首子 = 图标 socket (skb)
	if not (first is Control):
		return
	var skb := first as Control
	skb.pivot_offset = skb.size / 2.0
	var tw := create_tween()
	tw.tween_property(skb, "scale", Vector2(1.06, 1.06) if on else Vector2.ONE, 0.12)
	var box = skb.get_theme_stylebox("panel")
	if box is StyleBoxFlat:
		var sbf := box as StyleBoxFlat
		sbf.border_color = Color("#ffe9a8") if on else Color(1.0, 0.851, 0.239, 0.55)   # PoC hover #ffe9a8 / base 金.55
		sbf.shadow_color = Color(1.0, 0.851, 0.239, 0.6) if on else Color(0, 0, 0, 0.45)  # PoC hover 金辉光.6 / base 投影
		sbf.shadow_size = 13 if on else 4


## 递归把某节点的所有子控件 mouse_filter 设 IGNORE (让点击穿到可点击的父 tile)。
func _detail_ignore_children_mouse(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail_ignore_children_mouse(c)


func _show_skill_desc_popup(title_txt: String, icon_full: String, body_bbcode: String, detail_bbcode: String = "", rf_f: Dictionary = {}, rf_pas: Dictionary = {}) -> void:
	if _skill_card_layer != null and is_instance_valid(_skill_card_layer):
		_skill_card_layer.queue_free()   # 单例: 先关旧卡 → 点别的 tile 切换不叠卡
	var layer := CanvasLayer.new()
	_skill_card_layer = layer
	layer.layer = 70   # 高于信息面板(60)
	layer.name = "SkillDescPopup"
	add_child(layer)
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0, 0, 0, 0.5)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			# 1:1 PoC: 点到别的技能 tile → 直接切换内容; 点空白处 → 关闭 (PoC close 排除 .fdp-skill-icon)
			var pos: Vector2 = ev.position
			for t in _detail_tiles:
				var tn = t.get("node")
				if tn != null and is_instance_valid(tn) and (tn as Control).get_global_rect().has_point(pos):
					_show_skill_desc_popup(str(t["title"]), str(t["icon"]), str(t["body"]), str(t["detail"]), t.get("rf_f", {}), t.get("rf_pas", {}))
					return
			layer.queue_free()
			_skill_card_layer = null)
	layer.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#0a0e18")
	bsb.border_color = Color(1, 216.0 / 255.0, 107.0 / 255.0, 0.5)
	bsb.set_border_width_all(1)
	bsb.set_corner_radius_all(8)
	bsb.content_margin_left = 14; bsb.content_margin_right = 14
	bsb.content_margin_top = 10; bsb.content_margin_bottom = 10
	bsb.shadow_color = Color(0, 0, 0, 0.6); bsb.shadow_size = 14
	box.add_theme_stylebox_override("panel", bsb)
	center.add_child(box)
	var vbx := VBoxContainer.new()
	vbx.add_theme_constant_override("separation", 6)
	box.add_child(vbx)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	if icon_full != "" and ResourceLoader.exists(icon_full):
		var hi := TextureRect.new()
		hi.texture = load(icon_full)
		hi.custom_minimum_size = Vector2(28, 28)
		hi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		head.add_child(hi)
	var ht := Label.new()
	ht.text = title_txt
	ht.add_theme_font_size_override("font_size", 15)
	ht.add_theme_color_override("font_color", Color(1, 1, 1))
	ht.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(ht)
	vbx.add_child(head)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(300, 0)
	body.add_theme_font_size_override("normal_font_size", 12)
	body.add_theme_font_override("normal_font", _get_panel_font(false))
	body.add_theme_font_override("bold_font", _get_panel_font(true))
	body.add_theme_color_override("default_color", Color("#cccccc"))   # 1:1 PoC fdp-detail-box/passive-brief/skill-brief color:#ccc (原#bccdde蓝灰=偏差)
	var _expanded := [false]   # 简略/详细切换状态 (实时刷新+折叠共用)
	var _brief_suffix := _passive_state_suffix(rf_f, rf_pas)   # 被动实时状态行(空=非状态被动)
	body.text = body_bbcode + _brief_suffix
	vbx.add_child(body)
	_skill_card_refresh = ({"body": body, "base": body_bbcode, "f": rf_f, "pas": rf_pas, "expanded": _expanded} if (not rf_pas.is_empty() and _brief_suffix != "") else {})
	# ── 详细▾/简略▴ 折叠 (1:1 PoC fdp-toggle DetailPanel.ts:1648-1664): 默认简略(brief), 点击展开详细(desc) ──
	#   仅当 detail 非空且与 brief 不同时才显切换钮 (否则两者一致, 切换无意义).
	if detail_bbcode != "" and detail_bbcode != body_bbcode:
		var toggle := Button.new()
		toggle.text = "详细 ▾"
		toggle.flat = true
		toggle.add_theme_font_size_override("font_size", 11)   # PoC fdp-toggle font-size:11px
		toggle.add_theme_color_override("font_color", Color("#ffe9a8"))   # PoC color:#ffe9a8
		toggle.add_theme_color_override("font_hover_color", Color("#ffffff"))
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # display:inline-block 左对齐
		var sb_btn := StyleBoxFlat.new()
		sb_btn.bg_color = Color(1.0, 217.0 / 255.0, 61.0 / 255.0, 0.1)   # PoC 立体小金按钮底(渐变近似)
		sb_btn.border_color = Color(1.0, 217.0 / 255.0, 61.0 / 255.0, 0.4)   # border rgba(255,217,61,.4)
		sb_btn.set_border_width_all(1)
		sb_btn.set_corner_radius_all(6)   # PoC border-radius:6px
		sb_btn.content_margin_left = 10; sb_btn.content_margin_right = 10   # padding 2px 10px
		sb_btn.content_margin_top = 2; sb_btn.content_margin_bottom = 2
		toggle.add_theme_stylebox_override("normal", sb_btn)
		toggle.add_theme_stylebox_override("hover", sb_btn)
		toggle.add_theme_stylebox_override("pressed", sb_btn)
		toggle.pressed.connect(func() -> void:
			_expanded[0] = not _expanded[0]
			body.text = detail_bbcode if _expanded[0] else (body_bbcode + _passive_state_suffix(rf_f, rf_pas))
			toggle.text = "简略 ▴" if _expanded[0] else "详细 ▾")
		vbx.add_child(toggle)


## 取某 buff 的 value (无则 0) — 用于面板防御属性 (healReduce/dmgReduce/dodge)
func _buff_value(f: Dictionary, btype: String) -> float:
	for b in f.get("buffs", []):
		if b is Dictionary and str((b as Dictionary).get("type", "")) == btype:
			return float((b as Dictionary).get("value", 0))
	return 0.0


# ── 状态徽章 (1:1 PoC buildStatusHtml DetailPanel.ts:1238-1412) ──
func _fmt_dur(t) -> String:
	var ti: int = int(t) if t != null else 999
	return "永久" if (ti >= 999 or ti < 0) else "剩 %d 回合" % ti


func _badge_turns(t) -> String:
	var ti: int = int(t) if t != null else 999
	return "∞" if (ti >= 999 or ti < 0) else str(ti)


## PoC tag(): 边框文字 chip (可带前置小图标) — border+字同色
func _status_tag(border_hex: String, txt: String, icon_rel: String = "") -> Control:
	var pc := PanelContainer.new()
	var col := Color(border_hex)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)   # 1:1 PoC .fdp-buff-tag 无背景(透明) — 原黑.25是自创
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)   # 1:1 PoC fdp-buff-tag border-radius:4px (原5)
	sb.content_margin_left = 6; sb.content_margin_right = 6   # PoC padding 2px 6px
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var p := "res://assets/sprites/%s" % icon_rel
	if icon_rel != "" and ResourceLoader.exists(p):
		var ic := TextureRect.new()
		ic.texture = load(p)
		ic.custom_minimum_size = Vector2(13, 13)   # 1:1 PoC fdp-buff-tag img 13×13
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(ic)
	var lb := Label.new()
	lb.text = txt
	lb.add_theme_font_size_override("font_size", 11)
	lb.add_theme_color_override("font_color", col)
	row.add_child(lb)
	pc.add_child(row)
	return pc


## PoC sBadge(): 带框图标 + 右下角数字徽章 (层数/剩余回合). symbol!="" 时用彩色符号代替图标(花色/光色).
func _status_badge(icon_rel: String, border_hex: String, num_text: String, tip: String, symbol: String = "", sym_hex: String = "") -> Control:
	var pc := PanelContainer.new()
	pc.tooltip_text = tip
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(40.0/255.0, 28.0/255.0, 12.0/255.0, 0.55)   # 1:1 PoC rgba(40,28,12,.55) 暖棕 — 原冷蓝(.06,.08,.12,.9)是自创
	sb.border_color = Color(border_hex) if border_hex != "" else Color("#ffc850")   # 1:1 PoC 默认边框金#ffc850 — 原白.3是自创
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4; sb.content_margin_right = 4   # 1:1 PoC 徽章30×30(border-box)含22img → margin4(22+8=30)
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(22, 22)   # 1:1 PoC .fdp-rock-badge img 22×22 — 原30偏大
	if symbol != "":
		var sl := Label.new()
		sl.text = symbol
		sl.add_theme_font_size_override("font_size", 18)
		sl.add_theme_color_override("font_color", Color(sym_hex) if sym_hex != "" else Color(1, 1, 1))
		sl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		sl.add_theme_constant_override("outline_size", 3)
		sl.set_anchors_preset(Control.PRESET_FULL_RECT)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		inner.add_child(sl)
	else:
		var p := "res://assets/sprites/%s" % icon_rel
		if ResourceLoader.exists(p):
			var ic := TextureRect.new()
			ic.texture = load(p)
			ic.set_anchors_preset(Control.PRESET_FULL_RECT)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			inner.add_child(ic)
	if num_text != "":
		var nb := Label.new()
		nb.text = num_text
		nb.add_theme_font_size_override("font_size", 11)   # 1:1 PoC .fdp-rock-n font-size:11px — 原10
		nb.add_theme_color_override("font_color", Color("#ffe9a8"))   # 1:1 PoC .fdp-rock-n color:#ffe9a8 暖奶油 — 原白
		nb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		nb.add_theme_constant_override("outline_size", 3)
		nb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		nb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		nb.grow_vertical = Control.GROW_DIRECTION_BEGIN
		inner.add_child(nb)
	pc.add_child(inner)
	return pc


## 状态徽章列表 (1:1 PoC buildStatusHtml) — buff switch + 非buff状态字段
func _status_badges(f: Dictionary) -> Array:
	var parts: Array = []
	if f.get("_huntTarget", false):   # 黑礁猎团: 猎物视觉标记 (修原猎物无任何标记, 玩家看不到谁是猎物 — 审计)
		var hb := int(round(float(f.get("_huntDmgBoost", 0.0)) * 100.0))
		parts.append(_status_tag("#ff4d4d", "🎯猎物 +%d%%" % hb))
	var buffs: Array = f.get("buffs", [])
	var has_blackhole := false
	for b in buffs:
		if b is Dictionary and str((b as Dictionary).get("type", "")) == "blackhole":
			has_blackhole = true
	for b in buffs:
		if not (b is Dictionary):
			continue
		var ty := str(b.get("type", ""))
		var vi := int(round(float(b.get("value", 0))))
		var t = b.get("duration", 0)
		match ty:
			"burn": parts.append(_status_badge("status/burn-icon.png", "#ff6600", str(vi), "灼烧 %d 层" % vi))
			"poison": parts.append(_status_badge("status/poison-icon.png", "#6b8e23", str(vi), "中毒 %d 层" % vi))
			"bleed": parts.append(_status_badge("status/bleed-icon.png", "#cc3333", str(vi), "流血 %d 层" % vi))
			"dot", "curse": parts.append(_status_badge("status/curse-debuff-icon.png", "#9b59b6", _badge_turns(t), "诅咒 — 每回合真实伤害 (%s)" % _fmt_dur(t)))
			"physImmune": parts.append(_status_badge("status/stealth-icon.png", "#b8b8ff", _badge_turns(t), "虚化 — 免疫物理伤害 (%s)" % _fmt_dur(t)))
			"atkUp": parts.append(_status_tag("#06d6a0", "⬆攻+%d %s" % [vi, _fmt_dur(t)]))
			"atkDown": parts.append(_status_tag("#ff6b6b", "⬇攻-%d%% %s" % [vi, _fmt_dur(t)]))
			"defUp": parts.append(_status_tag("#06d6a0", "⬆护+%d %s" % [vi, _fmt_dur(t)]))
			"defDown": parts.append(_status_tag("#ff6b6b", "⬇护-%d%% %s" % [vi, _fmt_dur(t)]))
			"mrUp": parts.append(_status_tag("#4dabf7", "⬆魔抗+%d %s" % [vi, _fmt_dur(t)]))
			"mrDown": parts.append(_status_tag("#ff6b6b", "⬇魔抗-%d%% %s" % [vi, _fmt_dur(t)]))
			"dodge": parts.append(_status_tag("#aaaaaa", "闪避 %d%% %s" % [vi, _fmt_dur(t)], "status/dodge-new-icon.png"))
			"shield": pass
			"stun":
				if not has_blackhole:
					parts.append(_status_tag("#ffee00", "眩晕 %s" % _fmt_dur(t), "status/stun-icon.png"))
			"blackhole": parts.append(_status_badge("skills/space-3.png", "#9b59b6", _badge_turns(t), "黑洞 — 不可被选中 / 无法出手 (%s)" % _fmt_dur(t)))
			"healReduce": parts.append(_status_tag("#6b8e23", "治疗削减 %d%% %s" % [vi, _fmt_dur(t)], "status/heal-reduce-icon.png"))
			"markedDmg": parts.append(_status_badge("equip/consumable-mark.png", "#ff5252", _badge_turns(t), "必中标记 — 受到所有伤害 +%d%% (%s)" % [vi, _fmt_dur(t)]))
			"hot": parts.append(_status_tag("#06d6a0", "持续回复 %d/回 %s" % [int(round(float(b.get("hpPerTurn", b.get("value", 0))))), _fmt_dur(t)]))
			"fear": parts.append(_status_badge("status/fear-icon.png", "#9b59b6", _badge_turns(t), "恐惧 — 造成伤害 -%d%% (%s)" % [vi, _fmt_dur(t)]))
			"chilled": parts.append(_status_tag("#87ceeb", "冰寒 ATK-20%% %s" % _fmt_dur(t), "status/chilled-icon.png"))
			"confused": parts.append(_status_tag("#c39bd3", "😵 混乱 — 技能封禁, 胡乱攻击 %s" % _fmt_dur(t)))
			"bubbleBind": parts.append(_status_badge("passive/bubble-store-icon.png", "#4cc9f0", _badge_turns(t), "泡泡束缚 %s" % _fmt_dur(t)))
			"hunterMark": parts.append(_status_badge("skills/hunter-mark.png", "#ff8c42", _badge_turns(t), "猎杀印记 — HP<%d%% 时被斩杀 (%s)" % [vi, _fmt_dur(t)]))
			"counter": parts.append(_status_badge("skills/lightning-4.png", "#ffe14d", "", "雷盾 — 受击反击魔法 + 叠1层电击 (%s)" % _fmt_dur(t)))
			"trap": parts.append(_status_tag("#ff9f43", "陷阱", "passive/ninja-instinct-icon.png"))
			"diceFateCrit": parts.append(_status_badge("passive/gambler-blood-icon.png", "", str(vi), "命运骰子 暴击+%d%%（%s）" % [vi, _fmt_dur(t)]))
			"gamblerPierceConvert": parts.append(_status_tag("#ffd93d", "穿透转换 %s" % _fmt_dur(t), "passive/gambler-blood-icon.png"))
			"taunt": parts.append(_status_tag("#ff9f43", "嘲讽 %s" % _fmt_dur(t), "status/taunt-icon.png"))   # buff 名是 taunt(非 redirectAll), 原 case 名错→嘲讽徽章从不显示
			"armorBreak": parts.append(_status_tag("#ff6b6b", "⬇破甲-%d%% %s" % [vi, _fmt_dur(t)]))
			"corrode":
				# 深渊议会[腐蚀]: 每层 +pct% 受伤, 满5层额外30%转真伤无视盾 (徽章原缺 — 叠层玩家看不见, 审计补)
				var cpct := int(round(float(b.get("pct", 0.0)) * 100.0))
				parts.append(_status_tag("#7ed957", "🦠腐蚀 %d层 (+%d%%受伤)" % [vi, vi * cpct]))
			"lifesteal": parts.append(_status_tag("#06d6a0", "🩸吸血+%d%% %s" % [vi, _fmt_dur(t)]))
			"critUp": parts.append(_status_tag("#ffd93d", "⬆暴击+%d%% %s" % [vi, _fmt_dur(t)]))
			_: pass
	# 非 buff 状态层 (DetailPanel.ts:1311+)
	var ink := int(f.get("_inkStacks", 0))
	if ink > 0:
		parts.append(_status_badge("passive/ink-mark-icon.png", "#b8b8ff", str(ink), "墨迹 %d层 (受伤额外承受 +%d%% 伤害)" % [ink, ink * 5]))
	var shock := int(f.get("_shockStacks", 0))
	if shock > 0:
		parts.append(_status_badge("passive/lightning-storm-icon.png", "#ffd700", str(shock), "电击 %d层 (满8层引爆雷暴 / 感电按层真伤)" % shock))
	var stiff := int(f.get("_stiffnessStacks", 0))
	if stiff > 0:
		# 极地小队[僵硬]: 每层 -2% 攻 (max20层=-40%), stats_recalc 消费 (徽章原缺 — 减攻隐形, 审计补)
		parts.append(_status_tag("#9fd8e8", "🧊僵硬 %d层 (攻-%d%%)" % [stiff, stiff * 2]))
	var surge := int(f.get("_lightningSurgeTurns", 0))
	if surge > 0:
		var sv := maxi(1, surge - 1)
		parts.append(_status_badge("skills/lightning-1.png", "#ffd86b", _badge_turns(sv), "涌动 %s (被动电击真伤 +50%%)" % _fmt_dur(sv)))
	var ink_link = f.get("_inkLink", null)
	if ink_link is Dictionary and int((ink_link as Dictionary).get("turns", 0)) > 0:
		var lkt := int((ink_link as Dictionary).get("turns", 0))
		parts.append(_status_badge("skills/line-1.png", "#c77dff", _badge_turns(lkt), "连笔 %s (受伤按比例传递给连接目标)" % _fmt_dur(lkt)))
	var undead := int(f.get("_undeadLockTurns", 0))
	if undead > 0:
		parts.append(_status_badge("passive/undead-rage-icon.png", "#9b59b6", _badge_turns(undead), "亡灵之力 — 无法死亡 (剩 %d 回合)" % undead))
	var cryst := int(f.get("_crystallize", 0))
	if cryst > 0:
		parts.append(_status_badge("passive/crystal-resonance-icon.png", "#4cc9f0", str(cryst), "结晶 %d/4 — 满4层引爆魔法" % cryst))
	var lava_shield := int(round(float(f.get("_lavaShieldVal", 0))))
	if lava_shield > 0 and int(f.get("_lavaShieldTurns", 0)) > 0:
		parts.append(_status_badge("battle/lava-shield-icon.png", "#ff6600", str(lava_shield), "熔岩盾 %d（剩 %d 回合, 持盾受击反击）" % [lava_shield, int(f.get("_lavaShieldTurns", 0))]))
	if bool(f.get("_lavaTransformed", false)) and int(f.get("_lavaTransformTurns", 0)) > 0:
		var ltt := int(f.get("_lavaTransformTurns", 0))
		parts.append(_status_badge("passive/lava-heart-icon.png", "#ff3300", _badge_turns(ltt), "火山形态 — 变身中 (剩 %d 回合后变回)" % ltt))
	var p_d = f.get("passive")
	if p_d is Dictionary and str((p_d as Dictionary).get("type", "")) == "starEnergy":
		var max_e := int(round(float(f.get("maxHp", 0)) * float((p_d as Dictionary).get("maxChargePct", 40)) / 100.0))
		if max_e > 0 and int(f.get("_starEnergy", 0)) >= max_e:
			parts.append(_status_badge("passive/star-energy-icon.png", "#ffd166", "", "星能已满 — 技能获得强化"))
	var gold_l := int(f.get("_goldLightning", 0))
	if gold_l > 0:
		parts.append(_status_tag("#ffd700", "⚡金闪电 %d/5" % gold_l))
	var bub_shield := int(round(float(f.get("bubbleShieldVal", 0))))
	if bub_shield > 0 and int(f.get("bubbleShieldTurns", 0)) > 0:
		parts.append(_status_badge("skills/bubble-1.png", "#4cc9f0", _badge_turns(f.get("bubbleShieldTurns", 0)), "泡泡盾 %d（剩 %d 回合, 到期爆裂）" % [bub_shield, int(f.get("bubbleShieldTurns", 0))]))
	if bool(f.get("_hasRockArmor", false)) and int(f.get("_rockLayers", 0)) > 0:
		var rl := int(f.get("_rockLayers", 0))
		parts.append(_status_badge("stats/rock-layer-icon.png", "", str(rl), "岩层 %d/30（每层 +1%%减伤 +2%%体型）" % rl))
	if bool(f.get("_bambooCharged", false)):
		parts.append(_status_tag("#10b981", "充能就绪", "passive/bamboo-charge-icon.png"))
	if bool(f.get("_twoHeadResilience", false)) or int(f.get("_twoHeadResStacks", 0)) > 0:
		var ths := int(f.get("_twoHeadResStacks", 0))
		parts.append(_status_badge("skills/twohead-resilience.png", "", str(ths), "双头坚韧 %d/20（每受一段攻击 +1护甲 +1魔抗）" % ths))
	var dcs := int(f.get("_diamondCollideStacks", 0))
	if dcs > 0:
		var dmx := int(f.get("_diamondCollideMax", 2))
		parts.append(_status_badge("skills/diamond-collide.png", "", str(dcs), "碰撞累计 %d/%d（满%d次被眩晕1回合并重置）" % [dcs, dmx, dmx]))
	var coins := int(f.get("_goldCoins", 0))
	if (p_d is Dictionary and str((p_d as Dictionary).get("type", "")) == "fortuneGold") or coins > 0:
		parts.append(_status_badge("passive/fortune-gold-icon.png", "", str(coins), "金币 %d（打击两下加成 / 梭哈消耗 / 招财进宝消耗）" % coins))
	# 彩虹龟 棱镜光色
	if p_d is Dictionary and str((p_d as Dictionary).get("type", "")) == "rainbowPrism":
		var pcolors = f.get("_prismColors", [])
		if pcolors is Array:
			var PRISM_EMOJI := ["🔴", "🔵", "🟢", "🟠", "🟡", "🩵", "🟣"]
			var PRISM_HEX := ["#ff3b6b", "#3b82f6", "#49e06b", "#ff9e2c", "#ffe14d", "#5fd3e0", "#b06bff"]
			for c in pcolors:
				var ci := int(c)
				var hx: String = PRISM_HEX[ci] if ci >= 0 and ci < PRISM_HEX.size() else "#ffffff"
				var em: String = PRISM_EMOJI[ci] if ci >= 0 and ci < PRISM_EMOJI.size() else "?"
				parts.append(_status_badge("passive/rainbow-prism-icon.png", hx, em, "本回合光色"))
	# 赌神龟 命运之轮 4 花色
	var fw_counts = f.get("_fateWheelCounts", null)
	if bool(f.get("_fateWheel", false)) or fw_counts is Dictionary:
		var cnt: Dictionary = fw_counts if fw_counts is Dictionary else {}
		var suits := [["spade", "♠", "#e8e8e8"], ["heart", "♥", "#ef4444"], ["diamond", "♦", "#ffd93d"], ["club", "♣", "#10b981"]]
		for s in suits:
			var n := int(cnt.get(s[0], 0))
			parts.append(_status_badge("", s[2], str(n), "命运之轮 %s — 已抽中 %d 次" % [s[1], n], s[1], s[2]))
	return parts


## 黑礁猎团: 查看敌方单位时, 面板右侧加「设为猎物」钮 — 玩家手动指定猎物 (审计: 设计要玩家拖卡选, 原纯自动选最高血)。
func _add_hunt_prey_btn(layer: CanvasLayer, f: Dictionary) -> void:
	if GameState.mode != "duallane" or str(f.get("side", "")) != "right":
		return
	if not f.get("alive", false) or f.get("_isEgg", false) or f.get("_untargetable", false):
		return
	var has_hunt: bool = false
	for fr in fighters:
		if str(fr.get("side", "")) == "left" and int(fr.get("_huntTier", 0)) >= 1:
			has_hunt = true
			break
	if not has_hunt:
		return
	var is_prey: bool = f.get("_huntTarget", false)
	var btn := PanelContainer.new()
	btn.custom_minimum_size = Vector2(62, 110)
	var bsb := StyleBoxFlat.new()
	if is_prey:
		bsb.bg_color = Color(0.42, 0.10, 0.10, 0.95)
	else:
		bsb.bg_color = Color("#ff4d4d")
	bsb.border_color = Color("#ff8a8a")
	bsb.border_width_top = 3; bsb.border_width_bottom = 3; bsb.border_width_right = 3; bsb.border_width_left = 0
	bsb.corner_radius_top_right = 12; bsb.corner_radius_bottom_right = 12
	bsb.content_margin_left = 4; bsb.content_margin_right = 4; bsb.content_margin_top = 8; bsb.content_margin_bottom = 8
	bsb.shadow_color = Color(0, 0, 0, 0.55); bsb.shadow_size = 5
	btn.add_theme_stylebox_override("panel", bsb)
	var lbl := Label.new()
	lbl.text = "🎯\n已是\n猎物" if is_prey else "🎯\n设为\n猎物"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	btn.add_child(lbl)
	var vp := get_viewport_rect().size
	btn.position = Vector2((vp.x - 920.0) / 2.0 + 920.0, (vp.y - 110.0) / 2.0)   # 面板右外缘
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var fref := f
	btn.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not fref.get("_huntTarget", false):
			_hunt_set_prey(fref)
			_build_fighter_detail(fref))   # 重建面板 → 钮变"已是猎物" + 🎯徽章更新
	layer.add_child(btn)


## 黑礁: 手动把某敌方单位设为猎物 (清旧标 + 标新, 复用 boost 检测)。
func _hunt_set_prey(target: Dictionary) -> void:
	var en_side: String = str(target.get("side", "right"))
	var pl_side: String = "right" if en_side == "left" else "left"
	var boost: float = 0.0
	for fr in fighters:
		if str(fr.get("side", "")) == pl_side and int(fr.get("_huntTier", 0)) >= 1:
			boost = float(fr.get("_huntDmgBoostPct", 0.0))
			break
	if boost <= 0.0:
		return
	for fr in fighters:
		if str(fr.get("side", "")) == en_side:
			fr.erase("_huntTarget")
			fr.erase("_huntDmgBoost")
	target["_huntTarget"] = true
	target["_huntDmgBoost"] = boost
	for i in range(fighters.size()):
		_refresh_slot(i)


## 宝箱龟左侧「专属装备」切换钮 (1:1 PoC #poc-chest-sidebar-btn DetailPanel.ts:564/836): 贴面板左外缘, 点击切换"只看专属装备"模式.
func _add_chest_sidebar_btn(layer: CanvasLayer, f: Dictionary, chest_only: bool) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	var btn := PanelContainer.new()
	btn.custom_minimum_size = Vector2(60, 110)   # PoC 60×110
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(1.0, 217.0 / 255.0, 77.0 / 255.0, 0.95)   # PoC 渐变起 rgba(255,217,77,.95) (纯金近似)
	bsb.border_color = Color("#ffc850")
	bsb.border_width_left = 3; bsb.border_width_top = 3; bsb.border_width_bottom = 3; bsb.border_width_right = 0   # PoC border-right:none
	bsb.corner_radius_top_left = 12; bsb.corner_radius_bottom_left = 12   # PoC radius 12 0 0 12
	bsb.content_margin_left = 4; bsb.content_margin_right = 4; bsb.content_margin_top = 8; bsb.content_margin_bottom = 8
	bsb.shadow_color = Color(0, 0, 0, 0.55); bsb.shadow_size = 5   # PoC box-shadow -5px 0 12px 黑.55 近似
	btn.add_theme_stylebox_override("panel", bsb)
	var lbl := Label.new()
	lbl.text = "📦\n专属\n装备"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)   # PoC font-size:13
	lbl.add_theme_color_override("font_color", Color("#4a2c00"))   # PoC color:#4a2c00
	btn.add_child(lbl)
	# 位置: 面板(920宽)居中 → 钮贴其左外缘竖直居中 (PoC positionChestSidebar: left=panel.left-60)
	var vp := get_viewport_rect().size
	btn.position = Vector2((vp.x - 920.0) / 2.0 - 60.0, (vp.y - 110.0) / 2.0)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var fref := f
	var co := chest_only
	btn.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_build_fighter_detail(fref, not co))   # 切换模式 → 重建面板 (1:1 PoC toggleChestOnlyMode)
	overlay.add_child(btn)


## 只看专属装备 面板内容 (1:1 PoC buildChestOnlyHtml DetailPanel.ts:977): 标题 + 5格(96) + 提示, 整体居中.
func _build_chest_only_content(vb: VBoxContainer, f: Dictionary) -> void:
	vb.alignment = BoxContainer.ALIGNMENT_CENTER   # PoC fdp-chest-only justify-content:center
	var chest_equips: Array = (f.get("_chestEquips", []) as Array) if f.get("_chestEquips", null) is Array else []
	# 标题 "📦 name · 专属装备 N/5" (PoC fdp-chest-title 22px 800 #ffe9a8)
	var title := Label.new()
	title.text = "📦 %s · 专属装备 %d/5" % [str(f.get("name", "?")), chest_equips.size()]
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffe9a8"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(title)
	var sp1 := Control.new(); sp1.custom_minimum_size = Vector2(0, 22); vb.add_child(sp1)   # ≈ PoC margin-bottom28
	# col-label "专属装备 N/5" (PoC buildChestEquipGridInner fdp-col-label)
	var cl := _detail_col_label("专属装备 %d/5" % chest_equips.size(), Color("#ffd93d"))
	cl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(cl)
	# 5格 grid (PoC fdp-chest-only fdp-equip-grid 5×96 gap18 居中)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for i in range(5):
		grid.add_child(_chest_equip_slot(chest_equips[i] if i < chest_equips.size() else null))
	vb.add_child(grid)
	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(0, 28); vb.add_child(sp2)   # PoC fdp-chest-hint margin-top28
	# 提示 (PoC fdp-chest-hint 13px #aab)
	var hint := Label.new()
	hint.text = "再次点击左侧按钮返回完整面板"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#aabbcc"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(hint)


## 专属装备格 (96×96, 1:1 PoC fdp-chest-only .fdp-slot): 填充金框/空虚线; 填充点击弹该装备说明 (inline edef, 不在全量注册表).
func _chest_equip_slot(e) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(96, 96)   # PoC .fdp-chest-only .fdp-slot 96×96
	var has: bool = e is Dictionary and (str((e as Dictionary).get("icon", "")) != "" or str((e as Dictionary).get("name", "")) != "")
	var sb := StyleBoxFlat.new()
	if has:
		sb.bg_color = Color(1.0, 0.843, 0.0, 0.16)   # PoC .fdp-slot.filled rgba(255,215,0,.16)
		sb.border_color = Color(1.0, 0.843, 0.0, 0.55)
	else:
		sb.bg_color = Color(0, 0, 0, 0.28)   # PoC .fdp-slot.empty
		sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 10; sb.content_margin_right = 10   # PoC img76居中于96 → (96-76)/2=10
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	slot.add_theme_stylebox_override("panel", sb)
	if has:
		var ed: Dictionary = e
		var icon: String = str(ed.get("icon", ""))
		if icon.ends_with(".png"):
			var full := "res://assets/sprites/%s" % icon
			if ResourceLoader.exists(full):
				var ic := TextureRect.new()
				ic.texture = load(full)
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				slot.add_child(ic)
		elif icon != "":
			var em := Label.new()
			em.text = icon
			em.add_theme_font_size_override("font_size", 56)   # 96格 emoji (PoC .fdp-eq-emoji放大)
			em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			slot.add_child(em)
		slot.tooltip_text = str(ed.get("name", ""))
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var edef := {"name": str(ed.get("name", "")), "desc": str(ed.get("desc", "")), "icon": icon, "category": "chest"}
		slot.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_show_equip_popup("", edef))   # inline edef (专属装备不在 equipment_by_id)
	return slot


func _build_fighter_detail(f: Dictionary, chest_only: bool = false) -> void:
	_hide_fighter_detail()
	# 决策态(选龟/选靶)开 ⓘ 详情: 暂停倒计时 — 看信息时计时不走, 关面板再续 (防误超时自动出招).
	#   _hide_fighter_detail 刚 resume 过(无暂停态=no-op); 这里在打开新面板前重新暂停.
	var _in_decision: bool = _picker_active or _targeting_active
	if _in_decision:
		_pause_turn_timer()
	_detail_fighter_uid = int(f.get("_uid", -1))   # 修(审计): 直接重建路径(设猎物/宝箱钮)也记 uid, 否则面板 toggle 关失效(点同龟点不掉)
	_detail_tiles.clear()   # 重建面板 → 清空可点 tile 注册(大卡切换用)
	var layer := CanvasLayer.new()
	layer.add_to_group("ui_modal")   # modal 浮层: 开着时挡住背后龟身 Area2D 点击 (修"点穿透到后面")
	layer.layer = 60
	layer.name = "DetailLayer"
	add_child(layer)
	_detail_layer = layer

	# veil — 点空白处关 (PoC 全屏遮罩 + 拦截穿透)
	var veil := ColorRect.new()
	# 决策态: 降遮罩透明 (0.9→0.42) 让背后发光选龟环/选靶环仍隐约可见, 点遮罩=关面板回到选龟/选靶 (计时续跑);
	#   闲置态(纯看信息): 维持 PoC 0.9 深遮罩.
	veil.color = Color(0, 0, 0, 0.42) if _in_decision else Color(0, 0, 0, 0.9)   # 1:1 PoC #poc-detail-veil rgba(0,0,0,.9)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_hide_fighter_detail())
	layer.add_child(veil)

	# 居中 (IGNORE → 空白点击穿到 veil; panel STOP 不穿)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	var side: String = f.get("side", "left")
	var rarity: String = str(f.get("rarity", "C"))
	var rcol := _rarity_color(rarity)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var psb := StyleBoxFlat.new()
	# 实底深蓝 (PoC linear-gradient #1a2236→#0b0f1b 取中值≈(18,24,40)). 走 StyleBox 精确路径 —
	#   GradientTexture2D 运行时生成有色彩空间bug(navy渲成teal), 实测StyleBox底色精确 → 弃渐变TextureRect改实底.
	psb.bg_color = Color(18.0 / 255.0, 24.0 / 255.0, 40.0 / 255.0, 1.0)
	# 金边主框: 1:1 PoC border:2px #5c4a1c (DetailPanel.ts:96). 亮金/暗金/黑槽三圈斜面由 detail_panel_frame overlay 叠在内缘.
	psb.border_color = Color("#5c4a1c")
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(14)         # 1:1 PoC border-radius:14px
	psb.content_margin_left = 19; psb.content_margin_right = 19   # 1:1 PoC fdp padding 15px 19px (左右19)
	psb.content_margin_top = 15; psb.content_margin_bottom = 15   # 上下15
	# 外发光: 1:1 PoC box-shadow 0 0 26px color-mix(rarity-glow 28%) (DetailPanel.ts:105) → 稀有色@28% + size近似26px模糊.
	psb.shadow_color = Color(rcol.r, rcol.g, rcol.b, 0.28)   # PoC 28%
	psb.shadow_size = 14   # 近似 26px 模糊 (Godot shadow_size 是硬偏移非真模糊, 14≈视觉26px光晕)
	panel.add_theme_stylebox_override("panel", psb)
	# frame_root: 普通 Control 包住 [渐变底 → panel → 斜面/铆钉overlay], 因 Container(center)只居中其单子,
	#   而 PanelContainer 会强制 fit 子节点 → 把装饰层放进普通 Control(不重排)才能全 rect 覆盖, 不被容器抢位.
	var frame_root := Control.new()
	frame_root.custom_minimum_size = Vector2(920, 540)   # 1:1 PoC #poc-detail-panel 920×540 (DetailPanel.ts:86)
	frame_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(frame_root)

	# ── 竖渐变底 (1:1 PoC linear-gradient(180deg, rgba(26,34,54,.985)#1a2236 → rgba(11,15,27,.985)#0b0f1b) DetailPanel.ts:90-92) ──
	#   GradientTexture2D 竖直(0,0)→(0,1); 透明 StyleBox 让其透出; 方角被金边圆角盖住.
	var grad := Gradient.new()
	grad.set_color(0, Color(26.0 / 255.0, 34.0 / 255.0, 54.0 / 255.0, 0.985))   # #1a2236 @98.5%
	grad.set_color(1, Color(11.0 / 255.0, 15.0 / 255.0, 27.0 / 255.0, 0.985))   # #0b0f1b @98.5%
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 1
	grad_tex.height = 540
	grad_tex.fill_from = Vector2(0, 0)   # 竖直 from top
	grad_tex.fill_to = Vector2(0, 1)     # to bottom
	var grad_rect := TextureRect.new()
	grad_rect.texture = grad_tex
	grad_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad_rect.stretch_mode = TextureRect.STRETCH_SCALE
	grad_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grad_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_root.add_child(grad_rect)

	# ── 顶部金光晕 (1:1 PoC radial-gradient(130% 80% at 50% -12%, rgba(255,217,61,.07), transparent 62%) DetailPanel.ts:91) ──
	#   很淡的金色径向, 焦点在顶部中间(50%,-12%); GradientTexture2D 是圆形→对椭圆130%×80%作近似(alpha仅.07肉眼难辨差异).
	var halo := Gradient.new()
	halo.set_color(0, Color(1.0, 217.0 / 255.0, 61.0 / 255.0, 0.07))   # #ffd93d @7%
	halo.set_color(1, Color(1.0, 217.0 / 255.0, 61.0 / 255.0, 0.0))    # transparent 62% (近似: 末端全透)
	halo.set_offset(1, 0.62)   # transparent 62%
	var halo_tex := GradientTexture2D.new()
	halo_tex.gradient = halo
	halo_tex.width = 256
	halo_tex.height = 256
	halo_tex.fill = GradientTexture2D.FILL_RADIAL
	halo_tex.fill_from = Vector2(0.5, -0.12)   # at 50% -12%
	halo_tex.fill_to = Vector2(0.5 + 1.3, -0.12)   # 半径≈130% 宽 → UV 边缘
	var halo_rect := TextureRect.new()
	halo_rect.texture = halo_tex
	halo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo_rect.stretch_mode = TextureRect.STRETCH_SCALE
	halo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_root.add_child(halo_rect)

	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_root.add_child(panel)

	# ── 金属斜面3圈 + 四角铆钉 overlay (1:1 PoC box-shadow inset 三环 + ::after 铆钉, DetailPanel.ts:98-128) ──
	#   叠在 panel 之上(最上层), mouse IGNORE; _draw 画 #ffe9a8/#c79a36/黑 三环 + 四角金钉.
	var FrameOverlay := preload("res://scripts/scenes/detail_panel_frame.gd")
	var frame_ov: Control = FrameOverlay.new()
	frame_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_root.add_child(frame_ov)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(882, 0)   # 920 - 左右padding19×2 = 882
	panel.add_child(vb)

	# ── 宝箱龟专属装备面板模式 (1:1 PoC chestOnlyMode + sidebar btn, DetailPanel.ts:826/963/977) ──
	var _pd_chest = f.get("passive")
	var _is_chest_turtle: bool = _pd_chest is Dictionary and str((_pd_chest as Dictionary).get("type", "")) == "chestTreasure"
	if _is_chest_turtle:
		_add_chest_sidebar_btn(layer, f, chest_only)   # 左侧📦切换钮 (完整/只看专属 两模式都显)
	_add_hunt_prey_btn(layer, f)   # 黑礁: 敌方单位 + 玩家有黑礁 → 右侧「设为猎物」钮 (玩家手动指定猎物)
	if chest_only:
		_build_chest_only_content(vb, f)
		return   # 只看专属装备: 跳过完整面板内容 (1:1 PoC buildChestOnlyHtml)

	# ── Header: 头像 + 名/Lv + HP ──
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)   # 1:1 PoC fdp-head gap:12px (原14)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(52, 52)   # 1:1 PoC fdp-avatar 52×52
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var fid: String = str(f.get("id", ""))
	# 1:1 PoC avatarHtml(DetailPanel.ts:714): 海螺小虫→emoji🐛 / 机甲→pets/mech.png / 其余→avatars/{id}.png
	var emoji_av := ""
	if bool(f.get("_isConchWorm", false)):
		emoji_av = str(f.get("emoji", "🐛"))   # 海螺虫用emoji头像(原avatars/conch-worm.png不存在→空环)
	var ppath := ""
	if bool(f.get("_isMech", false)):
		ppath = "res://assets/sprites/pets/mech.png"   # 机甲专属头像(原avatars/mech.png不存在)
	else:
		ppath = "res://assets/sprites/avatars/%s.png" % fid
	if emoji_av == "" and ResourceLoader.exists(ppath):
		portrait.texture = load(ppath)
	# 立绘稀有色辉光环 (1:1 PoC fdp-avatar glow:167-175) — 圆形(border-radius50%) + 稀有色环4 + 外发光
	# 头像光环 (1:1 PoC fdp-avatar box-shadow DetailPanel.ts:172-174): 黑内环2px + 稀有色外环4px(即黑外再2px金) + 外发光12px@55%.
	#   双环用嵌套: portrait_wrap(内,黑2px) ← glow_wrap(外,金2px+shadow). 原单层3px金 = 漏了黑内环.
	var portrait_wrap := PanelContainer.new()
	portrait_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_wrap.clip_contents = true
	var pwsb := StyleBoxFlat.new()
	pwsb.bg_color = Color(0, 0, 0, 0.3)
	pwsb.border_color = Color(0, 0, 0, 0.6)   # PoC 内环: 0 0 0 2px rgba(0,0,0,.6)
	pwsb.set_border_width_all(2)
	pwsb.set_corner_radius_all(28)   # 圆形 (52/2+2边 ≈ 圆)
	portrait_wrap.add_theme_stylebox_override("panel", pwsb)
	if emoji_av != "":
		# emoji 头像 (海螺虫等召唤物, 1:1 PoC fdp-avatar emoji font-size:34 居中)
		var eav := Label.new()
		eav.text = emoji_av
		eav.custom_minimum_size = Vector2(52, 52)   # 保持 52×52 环
		eav.add_theme_font_size_override("font_size", 34)
		eav.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eav.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		portrait_wrap.add_child(eav)
	else:
		portrait_wrap.add_child(portrait)
	var glow_wrap := PanelContainer.new()
	glow_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gwsb := StyleBoxFlat.new()
	gwsb.bg_color = Color(0, 0, 0, 0)
	gwsb.border_color = rcol   # PoC 外环: 0 0 0 4px var(--fdp-glow) → 黑环外侧再 2px 稀有色
	gwsb.set_border_width_all(2)
	gwsb.set_corner_radius_all(30)
	gwsb.shadow_color = Color(rcol.r, rcol.g, rcol.b, 0.55)   # PoC 0 0 12px glow@55%
	gwsb.shadow_size = 6
	glow_wrap.add_theme_stylebox_override("panel", gwsb)
	glow_wrap.add_child(portrait_wrap)
	head.add_child(glow_wrap)

	# 中立/召唤物分类 (1:1 PoC DetailPanel.ts:1025-1029)
	#   isNeutral = _isNeutral (巨蟹/宝箱怪/海葵母, DetailPanel.ts:1025)
	#   isSummonUnit = _isMech || _isConchWorm || (_isSummon && !_isMasterTrainer) (DetailPanel.ts:1029)
	#     PoC 的 _isCandyBomb/_isPirateShip/_isCrystalBall 在 Godot 引擎里统一走 _isSummon=true(BattleScene.gd:3609)→已被覆盖;
	#     _isMech(BattleScene.gd:3281)/_isConchWorm(equipment_runtime.gd:910) 单独置位→显式列出。
	var is_neutral: bool = f.get("_isNeutral", false)
	var is_summon_unit: bool = f.get("_isMech", false) or f.get("_isConchWorm", false) \
		or (f.get("_isSummon", false) and not f.get("_isMasterTrainer", false))

	# 名字行 (Lv金 + 名 同号22; PoC .fdp-head-id, 名右接 badges, 不撑满) — DetailPanel.ts:176-185
	var name_line := HBoxContainer.new()
	name_line.add_theme_constant_override("separation", 10)   # PoC fdp-lv margin-right:10
	name_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 临时等级 (孵化器): 有则显 Lv(基+临) — 1:1 PoC DetailPanel.ts:1035 (_masterTempLevel 引擎未实现→只算 _incubatorTempLevel)
	var base_lv := int(f.get("_level", 1))   # 引擎字段是 _level (非 level → 原面板恒显 Lv 1)
	var tmp_lv := int(f.get("_incubatorTempLevel", 0))
	var lv := Label.new()
	lv.text = "Lv %d" % (base_lv + tmp_lv if tmp_lv > 0 else base_lv)
	lv.add_theme_font_size_override("font_size", 22)
	lv.add_theme_color_override("font_color", Color("#fff3a0"))   # 1:1 PoC fdp-lv color:#fff3a0
	name_line.add_child(lv)
	if tmp_lv > 0:
		# (基N+临M) 子串: PoC 用 #ffd86b 0.8em (22×.8≈18) DetailPanel.ts:1035
		var lv_tmp := Label.new()
		lv_tmp.text = "(基%d+临%d)" % [base_lv, tmp_lv]
		lv_tmp.add_theme_font_size_override("font_size", 18)
		lv_tmp.add_theme_color_override("font_color", Color("#ffd86b"))
		lv_tmp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_line.add_child(lv_tmp)
	var nm := Label.new()
	nm.text = str(f.get("name", "?"))
	nm.add_theme_font_size_override("font_size", 22)   # 1:1 PoC fdp-name font-size:22px
	# 名字色 (1:1 PoC DetailPanel.ts:1030): 中立/召唤物 → 粉 #ffc0e0; 普通龟 → 稀有度色 (非固定白)
	var name_col := rcol if not (is_neutral or is_summon_unit) else Color("#ffc0e0")
	nm.add_theme_color_override("font_color", name_col)
	name_line.add_child(nm)
	head.add_child(name_line)

	# badges: 大号稀有度字 + 羁绊tag图标 一组, 名右HP左 (1:1 PoC .fdp-head-badges gap8 DetailPanel.ts:156-166)
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 8)   # PoC gap:8
	badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if is_neutral:
		# 中立: 不显稀有字母/羁绊tag, 只显 "中立" 14px 蓝 (1:1 PoC DetailPanel.ts:1038)
		var n_lbl := Label.new()
		n_lbl.text = "中立"
		n_lbl.add_theme_font_size_override("font_size", 14)
		n_lbl.add_theme_color_override("font_color", Color("#7ec8ff"))
		n_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badges.add_child(n_lbl)
	elif is_summon_unit:
		# 召唤物: 不显稀有字母/羁绊tag, 只显 "召唤物" 14px 粉 (1:1 PoC DetailPanel.ts:1039)
		var s_lbl := Label.new()
		s_lbl.text = "召唤物"
		s_lbl.add_theme_font_size_override("font_size", 14)
		s_lbl.add_theme_color_override("font_color", Color("#ff9ec4"))
		s_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badges.add_child(s_lbl)
	else:
		# 普通龟: 大号稀有字 28px 稀有色 (PoC fdp-head-rarity DetailPanel.ts:1040; 用默认字体, 原 _float_num_font 缺字母B/S→显豆腐框=用户报"蓝小盒")
		var rar_lbl := Label.new()
		rar_lbl.text = rarity
		rar_lbl.add_theme_font_size_override("font_size", 28)
		rar_lbl.add_theme_color_override("font_color", rcol)
		rar_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badges.add_child(rar_lbl)
			# 羁绊 tag 图标已移除: 双路改用装备套装(学派)替代老乌龟羁绊 → 信息面板头部不再显羁绊标签 (用户 2026-06-23)
	var badges_mc := MarginContainer.new()   # 1:1 PoC fdp-head-badges margin:0 14px (DetailPanel.ts:159)
	badges_mc.add_theme_constant_override("margin_left", 14)
	badges_mc.add_theme_constant_override("margin_right", 14)
	badges_mc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badges_mc.add_child(badges)
	head.add_child(badges_mc)

	# spacer 推 HP 靠右 (1:1 PoC .fdp-head-hp margin-left:auto)
	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_spacer)

	# HP 区 — 1:1 PoC fdp-head-hp width:520 max-width:54%(≈497@920) margin-left:auto(右推)
	var hp_box := VBoxContainer.new()
	hp_box.custom_minimum_size = Vector2(490, 0)
	hp_box.size_flags_horizontal = Control.SIZE_SHRINK_END   # margin-left:auto → 靠右
	var hp_lbl := Label.new()
	# 护盾值 + 海葵寄生盾 (1:1 PoC fdp-hp-line shield-val DetailPanel.ts:1128)
	var _shv := int(f.get("shield", 0))
	var _anv := int(f.get("_anemoneShield", 0))
	var hp_txt := "HP %d / %d" % [int(f.get("hp", 0)), int(f.get("maxHp", 0))]
	if _shv > 0:
		hp_txt += "  🛡%d" % _shv
	if _anv > 0:
		hp_txt += "  🪼%d" % _anv
	hp_lbl.text = hp_txt
	hp_lbl.add_theme_font_size_override("font_size", 14)
	hp_lbl.add_theme_color_override("font_color", Color("#e6edf3"))
	hp_box.add_child(hp_lbl)
	# HP track: 普通 Control (非 Container) → 内部 fill/护盾段可手动绝对定位(1:1 PoC absolute), 不被容器抢位.
	var hp_track := Control.new()
	hp_track.custom_minimum_size = Vector2(490, 16)   # 1:1 PoC fdp-hp-bar height:16 (原12) / width≈497
	hp_track.clip_contents = true   # PoC fdp-hp-bar overflow:hidden → 圆角裁切
	var maxhp: int = maxi(1, int(f.get("maxHp", 1)))
	var hpv: int = clampi(int(f.get("hp", 0)), 0, maxhp)
	var hp_pct := float(hpv) / float(maxhp) * 100.0
	# 底槽 (圆角3, PoC fdp-hp-bar background rgba(0,0,0,.55) → 这里沿用原暗红底)
	var hp_bg := Panel.new()
	hp_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0, 0, 0, 0.55)   # 1:1 PoC fdp-hp-bar background rgba(0,0,0,.55) (原自创暗红底.85)
	tsb.set_corner_radius_all(8)          # 1:1 PoC border-radius:8 (原3)
	tsb.border_color = Color("#333333")   # 1:1 PoC border:1px #333 (原无边)
	tsb.set_border_width_all(1)
	hp_bg.add_theme_stylebox_override("panel", tsb)
	hp_track.add_child(hp_bg)
	# HP fill (阵营色; 手动按 hp_pct 定宽)
	var fill := ColorRect.new()
	fill.color = Color(0.18, 0.82, 0.56) if side == "left" else Color(0.69, 0.44, 0.95)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_track.add_child(fill)
	# ── 护盾白段 (1:1 PoC fdp-shield-fill rgba(255,255,255,.55) DetailPanel.ts:1058-1059,1131) ──
	#   shieldW = min(100, shield/maxHp*100); shieldLeft = max(0, min(hpPct, 100-shieldW)) → 叠在血条上(HP右端).
	#   counter(雷盾)buff 时改金近似(纯金 #ffdb4d@.75); 海葵寄生盾(_anemoneShield)= left:0 紫粉 #d96bff@.8 段.
	var has_counter := false
	for _b in f.get("buffs", []):
		if _b is Dictionary and str((_b as Dictionary).get("type", "")) == "counter":
			has_counter = true
			break
	var sh_overlays: Array = []   # [left_pct, width_pct, color]
	if _anv > 0:
		sh_overlays.append([0.0, minf(100.0, float(_anv) / float(maxhp) * 100.0), Color(217.0 / 255.0, 107.0 / 255.0, 1.0, 0.8)])
	if _shv > 0:
		var sw := minf(100.0, float(_shv) / float(maxhp) * 100.0)
		var sl := maxf(0.0, minf(hp_pct, 100.0 - sw))
		var scol := Color(1, 1, 1, 0.55)   # rgba(255,255,255,.55)
		if has_counter:
			scol = Color(1.0, 219.0 / 255.0, 77.0 / 255.0, 0.75)   # 雷盾金 近似 (PoC 金渐变)
		sh_overlays.append([sl, sw, scol])
	var sh_rects: Array = []
	for ov in sh_overlays:
		var sh_rect := ColorRect.new()
		sh_rect.color = ov[2]
		sh_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_track.add_child(sh_rect)
		sh_rects.append([sh_rect, ov[0], ov[1]])   # [rect, left_pct, width_pct]
	# 单一 resized 回调按比例摆放 fill + 所有护盾段 (绝对定位 1:1 PoC)
	var _layout_hp := func() -> void:
		var tw := hp_track.size.x
		var th := hp_track.size.y
		fill.position = Vector2.ZERO
		fill.size = Vector2(tw * hp_pct / 100.0, th)
		for entry in sh_rects:
			var r: ColorRect = entry[0]
			r.position = Vector2(tw * float(entry[1]) / 100.0, 0)
			r.size = Vector2(tw * float(entry[2]) / 100.0, th)
	hp_track.resized.connect(_layout_hp)
	_layout_hp.call_deferred()
	hp_box.add_child(hp_track)
	head.add_child(hp_box)
	vb.add_child(head)

	# ── header 金渐变下划线 (1:1 PoC border-image linear-gradient(90deg, transparent, rgba(255,217,61,.7), transparent) 2px DetailPanel.ts:146-147) ──
	#   2px 高横向渐变(中间亮两端透) → GradientTexture2D 横向 4 点; 比朴素灰线更"标题栏"感.
	var ul_grad := Gradient.new()
	ul_grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ul_grad.colors = PackedColorArray([
		Color(1.0, 217.0 / 255.0, 61.0 / 255.0, 0.0),   # transparent
		Color(1.0, 217.0 / 255.0, 61.0 / 255.0, 0.7),   # rgba(255,217,61,.7) 中间亮
		Color(1.0, 217.0 / 255.0, 61.0 / 255.0, 0.0),   # transparent
	])
	var ul_tex := GradientTexture2D.new()
	ul_tex.gradient = ul_grad
	ul_tex.width = 256
	ul_tex.height = 1
	ul_tex.fill_from = Vector2(0, 0)   # 横向 left→right
	ul_tex.fill_to = Vector2(1, 0)
	var ul_rect := TextureRect.new()
	ul_rect.texture = ul_tex
	ul_rect.custom_minimum_size = Vector2(0, 2)   # 2px 高
	ul_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ul_rect.stretch_mode = TextureRect.STRETCH_SCALE
	ul_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ul_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(ul_rect)

	# HP 子资源条 (1:1 PoC buildHpBar DetailPanel.ts:1062-1127): 坚壁/泡沫/怒气·火山/财宝/储能
	var p_d = f.get("passive")
	var p_t: String = str((p_d as Dictionary).get("type", "")) if p_d is Dictionary else ""
	if p_t == "stoneWall":
		var gained := int(f.get("_stoneDefGained", 0))
		var init_def := int(f.get("_initDef", f.get("baseDef", f.get("def", 0))))
		var max_cap := int(round(init_def * (float((p_d as Dictionary).get("maxDefInitPct", 100)) / 100.0)))
		hp_box.add_child(_detail_meter("坚壁进度", "+%d/%d" % [gained, max_cap], minf(100.0, float(gained) / maxf(1.0, max_cap) * 100.0), Color("#ffd45c"), true))
	elif p_t == "bubbleStore":
		var store := int(round(float(f.get("bubbleStore", 0))))
		var mhp := int(f.get("maxHp", 1))
		hp_box.add_child(_detail_meter("🫧 泡泡值", "%d/%d" % [store, mhp], minf(100.0, float(store) / maxf(1.0, mhp) * 100.0), Color("#4cc9f0"), true))
	elif p_t == "lavaRage":
		if bool(f.get("_lavaTransformed", false)):
			var dur := int((p_d as Dictionary).get("transformDuration", 6))
			var rem_t := int(f.get("_lavaTransformTurns", 0))
			hp_box.add_child(_detail_meter("🌋 火山形态", "剩 %d 回合" % rem_t, minf(100.0, float(rem_t) / maxf(1.0, dur) * 100.0), Color("#ff5a00"), true))
		else:
			var rage := int(round(float(f.get("_lavaRage", 0))))
			var rmax := int((p_d as Dictionary).get("rageMax", 100))
			hp_box.add_child(_detail_meter("🌋 怒气", "%d/%d" % [rage, rmax], minf(100.0, float(rage) / maxf(1.0, rmax) * 100.0), Color("#ff6600"), true))
	elif p_t == "chestTreasure":
		var treasure := int(round(float(f.get("_chestTreasure", 0))))
		var tier := int(f.get("_chestTier", 0))
		var base_th: Array = [60, 120, 220, 350, 500] if bool(f.get("_chestIntuition", false)) else (p_d as Dictionary).get("thresholds", [80, 130, 240, 360, 590])
		var lv_mult := 1.0 + (float(f.get("_level", 1)) - 1.0) * 0.03
		if tier < base_th.size():
			var next_th := int(round(float(base_th[tier]) * lv_mult))
			hp_box.add_child(_detail_meter("📦 财宝", "%d/%d（第%d件）" % [treasure, next_th, tier + 1], minf(100.0, maxf(0.0, float(treasure) / maxf(1.0, next_th) * 100.0)), Color("#ffd93d"), true))
		else:
			hp_box.add_child(_detail_meter("📦 财宝", "已满 (5/5)", 100.0, Color("#ffd93d"), true))
	elif p_t == "auraAwaken" and (p_d is Dictionary and bool((p_d as Dictionary).get("energyStore", false))):
		# 引擎写 _auraEnergy(damage.gd:269 / wave 3033 / reset 3057) — 原面板读 _storedEnergy(PoC字段名)恒0=空条; 改读引擎实际字段
		var cur := int(round(float(f.get("_auraEnergy", 0))))
		var cap := int(round(float(f.get("maxHp", 1)) * float((p_d as Dictionary).get("energyMaxStorePct", 0.5))))
		hp_box.add_child(_detail_meter("⚡ 储能", "%d/%d" % [cur, cap], minf(100.0, float(cur) / maxf(1.0, cap) * 100.0), Color("#7fe0ff"), true))

	vb.add_child(_detail_divider())   # 1:1 PoC 1px白.1 (原默认HSeparator灰)

	# ── 属性 (8 项, 4 列) ── 公式同 PoC DetailPanel.buildStats
	var crit: float = float(f.get("crit", 0.0))
	var overflow: float = maxf(0.0, crit - 1.0)
	# overflowMult: 1:1 PoC DetailPanel.ts:1153 = passive.overflowMult || 1.5 (赌神龟暴击溢出倍率改读被动字段, 非硬编 1.5)
	var _p_ov = f.get("passive")
	var overflow_mult: float = 1.5
	if _p_ov is Dictionary and float((_p_ov as Dictionary).get("overflowMult", 0.0)) > 0.0:
		overflow_mult = float((_p_ov as Dictionary).get("overflowMult", 1.5))
	var crit_dmg: float = 1.5 + float(f.get("_extraCritDmg", 0.0)) + float(f.get("_extraCritDmgPerm", 0.0)) \
		+ float(f.get("_buffCritDmg", 0.0)) + overflow * overflow_mult   # 1:1 PoC :1157
	var ls_pct: int = roundi(float(f.get("lifestealPct", 0.0)) * 100.0)
	# ── 主体 2 列 (1:1 PoC fdp-cols grid 1.2fr:3fr gap22): 左=属性(无标题) 右=状态 ──
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 左列 属性 (fdp-col-left 1.2fr): 8核心 紧凑icon+值(2列) + 4防御(fdp-stats-col, 承受向倍率)
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # 属性区收缩靠左; 状态区(right_col)占余下 (原EXPAND+ratio被子项min撑满→防御列被推到最右)
	left_col.add_theme_constant_override("separation", 6)
	var core := GridContainer.new()
	core.columns = 2
	core.add_theme_constant_override("h_separation", 10)   # 1:1 PoC fdp-stats column-gap:10px
	core.add_theme_constant_override("v_separation", 12)   # 1:1 PoC fdp-stats row-gap:12px
	# 1:1 PoC buildStats: 每项 tip(护甲/魔抗含减免%) + 增益绿/减益红(对初始值 _initXxx)
	var s_atk := int(f.get("atk", 0))
	var s_def := int(f.get("def", 0))
	var s_mr := int(f.get("mr", f.get("def", 0)))
	var s_ap := int(f.get("armorPen", 0))
	var s_mp := int(f.get("magicPen", 0))
	var s_critp := mini(100, roundi(crit * 100.0))
	var s_cdp := roundi(crit_dmg * 100.0)
	var def_pct := roundi(float(s_def) / float(s_def + 40) * 100.0)   # PoC def/(def+DEF_CONSTANT40)*100 减免
	var mr_pct := roundi(float(s_mr) / float(s_mr + 40) * 100.0)
	core.add_child(_detail_stat_chip("atk-icon.png", "攻击力", str(s_atk), "攻击力 = %d" % s_atk, _stat_ud(s_atk, float(f.get("_initAtk", s_atk)))))
	core.add_child(_detail_stat_chip("lifesteal-icon.png", "生命偷取", "%d%%" % ls_pct, "生命偷取 = %d%%" % ls_pct, _stat_ud(float(ls_pct), float(f.get("_initLifesteal", 0)))))
	core.add_child(_detail_stat_chip("def-icon.png", "护甲", str(s_def), "护甲 %d · 减免 %d%%" % [s_def, def_pct], _stat_ud(s_def, float(f.get("_initDef", s_def)))))
	core.add_child(_detail_stat_chip("mr-icon.png", "魔抗", str(s_mr), "魔抗 %d · 减免 %d%%" % [s_mr, mr_pct], _stat_ud(s_mr, float(f.get("_initMr", s_mr)))))
	core.add_child(_detail_stat_chip("crit-icon.png", "暴击率", "%d%%" % s_critp, "暴击几率 = %d%%" % s_critp, _stat_ud(float(s_critp), float(f.get("_initCrit", crit)) * 100.0)))
	core.add_child(_detail_stat_chip("crit-dmg-icon.png", "暴击伤害", "%d%%" % s_cdp, "暴击伤害倍率 = %d%%" % s_cdp, _stat_ud(float(s_cdp), float(f.get("_initCritDmg", 150.0)))))
	core.add_child(_detail_stat_chip("armor-pen-icon.png", "护甲穿透", str(s_ap), "护甲穿透 = %d" % s_ap, _stat_ud(s_ap, float(f.get("_initArmorPen", s_ap)))))
	core.add_child(_detail_stat_chip("magic-pen-icon.png", "魔抗穿透", str(s_mp), "魔抗穿透 = %d" % s_mp, _stat_ud(s_mp, float(f.get("_initMagicPen", s_mp)))))
	core.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # 核心紧凑不撑开 → 防御列紧贴其右 (原EXPAND把防御推到面板最右)
	var _hr := _buff_value(f, "healReduce")
	var _ripple := float(f.get("_equipRippleHealAmp", 0.0))
	var _guard := float(f.get("_synergyGuardAmp", 0.0))
	var heal_pct := int(round((1.0 - _hr / 100.0) * (1.0 + _ripple / 100.0) * (1.0 + _guard) * Rules.heal_mult() * 100.0))
	var shield_pct := int(round(Rules.shield_mult() * 100.0))
	var rock_pct := minf(30.0, float(int(f.get("_rockLayers", 0))))   # 引擎字段是 _rockLayers (非 rockLayers → 原岩层减伤永不显示)
	var dr_pct := int(minf(100.0, _buff_value(f, "dmgReduce") + rock_pct))
	var dodge_pct := int(_buff_value(f, "dodge") + float(f.get("_extraDodge", 0.0)))
	# 防御列 (1:1 PoC fdp-stats-col DetailPanel.ts:273-276): 竖排4项 + 金左边框分隔 + padding-left12. 原为2列grid堆在8核心下方.
	var def_vcol := VBoxContainer.new()
	def_vcol.add_theme_constant_override("separation", 12)   # PoC fdp-stats-col gap:12
	def_vcol.add_child(_detail_stat_chip("heal-power-icon.png", "治疗效果", "%d%%" % heal_pct, "治疗效果 = %d%% (受到治疗的增幅)" % heal_pct))
	def_vcol.add_child(_detail_stat_chip("shield-power-icon.png", "护盾效果", "%d%%" % shield_pct, "护盾效果 = %d%% (受到护盾的增幅)" % shield_pct))
	def_vcol.add_child(_detail_stat_chip("dmg-reduce-icon.png", "伤害减免", "%d%%" % dr_pct, "伤害减免 = %d%% (承受向)" % dr_pct))
	def_vcol.add_child(_detail_stat_chip("dodge-new-icon.png", "闪避率", "%d%%" % dodge_pct, "闪避率 = %d%%" % dodge_pct))
	var def_panel := PanelContainer.new()
	var dpsb := StyleBoxFlat.new()
	dpsb.bg_color = Color(0, 0, 0, 0)
	dpsb.set_border_width_all(0)
	dpsb.border_width_left = 1   # PoC border-left:1px
	dpsb.border_color = Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.2)   # rgba(255,216,107,.2)
	dpsb.content_margin_left = 12   # PoC padding-left:12
	def_panel.add_theme_stylebox_override("panel", dpsb)
	def_panel.add_child(def_vcol)
	# stats_wrap: [8核心2列grid(flex) | 防御竖列(金左边框)] 横排 (1:1 PoC fdp-stats-wrap flex gap12 DetailPanel.ts:271)
	var stats_wrap := HBoxContainer.new()
	stats_wrap.add_theme_constant_override("separation", 12)
	stats_wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stats_wrap.add_child(core)
	stats_wrap.add_child(def_panel)
	left_col.add_child(stats_wrap)
	cols.add_child(left_col)
	# 右列 状态 (fdp-col-right 3fr): "状态"标题(fdp-col-label #ffd93d) + 徽章 flow
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 3.0
	right_col.add_child(_detail_col_label("状态", Color("#ffd93d")))   # 1:1 PoC fdp-col-label (3px金竖条+13px字)
	var st_badges := _status_badges(f)
	if st_badges.is_empty():
		var none_l := Label.new()
		none_l.text = "无"
		none_l.add_theme_font_size_override("font_size", 11)   # 1:1 PoC fdp-none font-size:11px
		none_l.add_theme_color_override("font_color", Color("#666666"))   # 1:1 PoC fdp-none color:#666
		right_col.add_child(none_l)
	else:
		var st_flow := HFlowContainer.new()
		st_flow.add_theme_constant_override("h_separation", 5)   # 1:1 PoC fdp-buffs gap:5px
		st_flow.add_theme_constant_override("v_separation", 5)
		for badge in st_badges:
			st_flow.add_child(badge)
		right_col.add_child(st_flow)
	cols.add_child(right_col)   # ← 原缺这行! right_col 建好却从未加进 cols → 状态区从来没渲染过 (真机截图抓出)
	vb.add_child(cols)

	# ── 装备 (10 槽) ──
	# 双路 p2eq 存 f._p2_equips=[{id,star}], 老 e_ 存 f._equipped_ids=[id字符串]。合并显示。
	#   原只读 _equipped_ids → 双路装的 p2eq 全不显("装的装备没动")。
	var eq_ids: Array = []
	var eq_stars: Array = []   # 平行: p2eq星级(1/2/3), 老e_=0(无星)
	for _p2 in f.get("_p2_equips", []):
		if _p2 is Dictionary:
			eq_ids.append(str(_p2.get("id", "")))
			eq_stars.append(int(_p2.get("star", 1)))
	for _e in f.get("_equipped_ids", []):
		eq_ids.append(str(_e))
		eq_stars.append(0)
	# 格子数 = 该龟局内等级开放的槽数 (等级2/4/6/8/10→1/2/3/4/5), 非写死10; 防御: 历史遗留已装件多于cap时取较大者不漏显
	var eq_cap: int = maxi(Phase2Config.equip_slots_for_level(int(GameState.dual_level.get(str(f.get("side", "left")), 1))), eq_ids.size())
	vb.add_child(_detail_divider())   # 1:1 PoC fdp-equip-wrap border-top:1px白.1 (DetailPanel.ts:378)
	vb.add_child(_detail_col_label("装备 %d/%d" % [eq_ids.size(), eq_cap], Color("#ffd93d")))   # 1:1 PoC fdp-col-label 色#ffd93d(原#ffd86b)+单空格
	# PoC .fdp-equip-grid 一横排 grid, 槽62×62 gap10 (DetailPanel.ts:58/381); 列数=cap(随等级开放)
	var eq_row := GridContainer.new()
	eq_row.columns = maxi(1, eq_cap)
	eq_row.add_theme_constant_override("h_separation", 10)
	eq_row.add_theme_constant_override("v_separation", 10)
	for i in range(eq_cap):
		var sl := PanelContainer.new()
		sl.custom_minimum_size = Vector2(62, 62)   # PoC .fdp-slot 62×62
		var slb := StyleBoxFlat.new()
		var eid: String = str(eq_ids[i]) if i < eq_ids.size() else ""
		if eid != "":
			slb.bg_color = Color(1.0, 0.843, 0.0, 0.16)   # PoC .fdp-slot.filled rgba(255,215,0,.16)
			slb.border_color = Color(1.0, 0.843, 0.0, 0.55)   # border rgba(255,215,0,.55)
		else:
			slb.bg_color = Color(0, 0, 0, 0.28)   # PoC .fdp-slot.empty rgba(0,0,0,.28)
			slb.border_color = Color(1, 1, 1, 0.14)   # rgba(255,255,255,.14) (PoC dashed→实线近似)
		slb.set_border_width_all(2)
		slb.set_corner_radius_all(7)
		slb.content_margin_left = 6; slb.content_margin_right = 6   # PoC img 50 居中于 62 槽
		slb.content_margin_top = 6; slb.content_margin_bottom = 6
		sl.add_theme_stylebox_override("panel", slb)
		if eid != "":
			var _p2def: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
			var edef: Dictionary = DataRegistry.equipment_by_id.get(eid, {})
			# 双路 p2eq: 优先 img(.png, 按机制对齐PoC装备图) → 有图用图; 无图回退 emoji。老 e_ 用 icon。原只查 equipment_by_id → p2eq 显空格子
			var erel: String = ""
			if not _p2def.is_empty():
				erel = str(_p2def.get("img", "")) if str(_p2def.get("img", "")) != "" else str(_p2def.get("emoji", ""))
			else:
				erel = str(edef.get("icon", ""))
			# 1:1 PoC: e.icon.endsWith('.png') ? <img> : <span emoji 40px> (DetailPanel.ts:1218-1220)
			if erel.ends_with(".png"):
				var efull := "res://assets/sprites/%s" % erel
				if ResourceLoader.exists(efull):
					var eic := TextureRect.new()
					eic.texture = load(efull)
					eic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					eic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					eic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					sl.add_child(eic)
			elif erel != "":
				# 非png图标=emoji (如海螺📯), PoC .fdp-eq-emoji font-size:40 — 原Godot漏渲染→空格子
				var eml := Label.new()
				eml.text = erel
				eml.add_theme_font_size_override("font_size", 40)
				eml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				eml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				sl.add_child(eml)
			# p2eq 星级角标 (左上角 N★, 2/3星才显; 修详情面板看不出几星)
			var star_lv: int = int(eq_stars[i]) if i < eq_stars.size() else 0
			if star_lv >= 2:
				var star_ov := Control.new()
				star_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
				sl.add_child(star_ov)
				var sbl := Label.new()
				sbl.text = "%d★" % star_lv
				sbl.add_theme_font_size_override("font_size", 12)
				sbl.add_theme_color_override("font_color", Color("#ff7de0") if star_lv >= 3 else Color("#ffe9a8"))
				sbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
				sbl.add_theme_constant_override("outline_size", 4)
				sbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				sbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
				sbl.offset_left = 1; sbl.offset_top = -2
				star_ov.add_child(sbl)
			sl.tooltip_text = str(_p2def.get("name", eid)) if not _p2def.is_empty() else EquipmentRuntime.display_name(eid)
			# 重击锤叠层 ×N 角标 (1:1 PoC DetailPanel.ts:1222-1224 fdp-rock-n right:3 bottom:1 12px)
			var hammer_n := int(f.get("_equipHammer", 0))
			if eid == "e_hammer" and hammer_n > 0:
				# overlay Control 填满槽 content rect → Label 锚右下角(PanelContainer fit overlay, 内部锚仍生效)
				var badge_ov := Control.new()
				badge_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
				sl.add_child(badge_ov)
				var bn := Label.new()
				bn.text = "×%d" % hammer_n
				bn.add_theme_font_size_override("font_size", 12)   # PoC font-size:12px
				bn.add_theme_color_override("font_color", Color("#ffe9a8"))   # PoC fdp-rock-n color #ffe9a8
				bn.add_theme_color_override("font_outline_color", Color(0, 0, 0))   # PoC text-shadow 黑描边
				bn.add_theme_constant_override("outline_size", 4)
				bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				bn.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				bn.mouse_filter = Control.MOUSE_FILTER_IGNORE
				bn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
				bn.offset_left = -30; bn.offset_top = -18   # 锚右下角, 反向给字留空间 (right:3/bottom:1 近似)
				bn.offset_right = -1; bn.offset_bottom = -1
				badge_ov.add_child(bn)
			# 点装备格 → 弹装备详情 (左图右文, 1:1 PoC DetailPanel showEquipDescPopup)
			sl.mouse_filter = Control.MOUSE_FILTER_STOP
			sl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var eid_click := eid
			var star_click := maxi(1, star_lv)   # 龟身装备当前星 -> 显当前星属性
			var atk_click := int(f.get("atk", 0))   # 携带龟ATK -> 云顶式算效果实际值 (两区主效果实算)
			var crit_click := float(f.get("crit", 0.0))   # 携带龟暴击率(分数) -> ×暴击率 项实算
			sl.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_show_equip_popup(eid_click, {}, star_click, atk_click, crit_click, true))   # equipped=true: 上龟装备走两区式 (含 atk=0 龟蛋/被清零单位)
		eq_row.add_child(sl)
	vb.add_child(eq_row)

	# ── 技能 (1:1 PoC buildSkills DetailPanel.ts:1538): 天生被动 tile 在前 + 主动技能(+角标/CD) ──
	var skills: Array = f.get("skills", [])
	var passive_raw = f.get("passive")
	var has_passive: bool = passive_raw is Dictionary and not (passive_raw as Dictionary).is_empty()
	if not skills.is_empty() or has_passive:
		vb.add_child(_detail_divider())   # 1:1 PoC fdp-skills-wrap border-top:1px白.1 (DetailPanel.ts:408)
		vb.add_child(_detail_col_label("技能", Color("#ffd93d")))   # 1:1 PoC fdp-col-label 色#ffd93d(原#ffd86b)
		var sk_row := HBoxContainer.new()   # 1:1 PoC .fdp-skills: tile 弹性平分整行(flex:1 1 0); HFlow 不分配余空间→左聚簇
		sk_row.add_theme_constant_override("separation", 8)
		# 天生被动 tile (PoC:1555-1561): 被动图标 + 名 + "被动"标; 点击弹描述大卡 (PoC 点 tile→popup)
		if has_passive:
			var pas: Dictionary = passive_raw
			var pi_rel: String = DataRegistry.passive_icons.get(pas.get("type", ""), "")
			var pi_full := "res://assets/sprites/%s" % pi_rel if pi_rel.ends_with(".png") else ""
			var pas_tile := _detail_skill_tile(pi_full, "⭐", str(pas.get("name", "被动")), "被动", true, false)
			var pbrief := SkillText.render_bbcode(str(pas.get("detail", pas.get("brief", ""))), f, pas)
			# 详细文本 desc (PoC fdp-detail-box) → 折叠展开用; 与 brief 不同时弹卡显切换钮
			var pdetail := SkillText.render_bbcode(str(pas.get("desc", "")), f, pas) if pas.get("desc", "") != "" else ""
			# 状态行不再 bake 进 body → 由大卡实时拼 + _process 刷新; 传 f/pas 给大卡
			_make_detail_tile_clickable(pas_tile, str(pas.get("name", "被动")), pi_full, pbrief, pdetail, f, pas)
			sk_row.add_child(pas_tile)
		# 主动技能 tiles
		for sk in skills:
			var skrel: String = str(sk.get("icon", ""))
			var skfull := "res://assets/sprites/%s" % skrel if skrel != "" else ""
			var show_plus: bool = bool(sk.get("enhancesPassive", false)) or bool(sk.get("iconPlus", false))
			# enhancesPassive 且自身无图标 → 复用被动图标 (PoC:1571)
			if skfull == "" and bool(sk.get("enhancesPassive", false)) and has_passive:
				var ep_rel: String = DataRegistry.passive_icons.get((passive_raw as Dictionary).get("type", ""), "")
				if ep_rel.ends_with(".png"):
					skfull = "res://assets/sprites/%s" % ep_rel
			var sk_cd: int = int(sk.get("cd", 0))
			var cd_txt := ""
			if sk_cd > 0:
				var cd_left: int = int(sk.get("cdLeft", 0))
				cd_txt = "CD%d" % sk_cd + (" (剩%d)" % cd_left if cd_left > 0 else "")   # PoC fdp-cd 格式
			var sk_tile := _detail_skill_tile(skfull, str(sk.get("name", "?")).substr(0, 2), str(sk.get("name", "")), cd_txt, false, show_plus)
			var sbrief := SkillText.render_bbcode(str(sk.get("detail", sk.get("brief", ""))), f, sk)
			# 详细文本 desc → 折叠展开用 (1:1 PoC fdp-toggle 简略↔详细)
			var sdetail := SkillText.render_bbcode(str(sk.get("desc", "")), f, sk) if sk.get("desc", "") != "" else ""
			# 双形态龟(双头/火山): 详细视图末尾追加另一形态同 index 配对技能 (1:1 PoC openSkillCard pairedFormSkill)
			var paired_fs := _paired_form_skill(f, sk)
			if not paired_fs.is_empty():
				var pk: Dictionary = paired_fs["skill"]
				var pbody: String = SkillText.render_bbcode(str(pk.get("detail", pk.get("brief", ""))), f, pk)
				if sdetail == "":
					sdetail = sbrief
				sdetail += char(10) + char(10) + "[color=%s]◆ %s · %s[/color]" % [str(paired_fs["color"]), str(paired_fs["label"]), str(pk.get("name", ""))] + char(10) + "[color=#cdd3da]" + pbody + "[/color]"
			_make_detail_tile_clickable(sk_tile, str(sk.get("name", "?")), skfull, sbrief, sdetail)
			sk_row.add_child(sk_tile)
		# 额外/装备被动 tiles (_passiveSkills: 圣光/强化生长 等; 1:1 PoC extraPassives DetailPanel.ts:1539-1547)
		#   修: 原嵌套在 for sk 循环内 → 每个主动技能后重复渲染一整轮(N×M)+无主动技能时不显。移出循环渲一次, 并去重同名。
		var _active_names: Dictionary = {}
		for sk2 in skills:
			_active_names[str(sk2.get("name", ""))] = true
		for ps in f.get("_passiveSkills", []):
			if not (ps is Dictionary):
				continue
			if _active_names.has(str(ps.get("name", ""))):
				continue
			var psrel: String = str(ps.get("icon", ""))
			var psfull := "res://assets/sprites/%s" % psrel if psrel.ends_with(".png") else ""
			var ps_plus: bool = bool(ps.get("enhancesPassive", false)) or bool(ps.get("iconPlus", false))
			var ps_tile := _detail_skill_tile(psfull, str(ps.get("name", "?")).substr(0, 2), str(ps.get("name", "")), "被动", true, ps_plus)
			var psbrief := SkillText.render_bbcode(str(ps.get("detail", ps.get("brief", ""))), f, ps)
			var psdetail := SkillText.render_bbcode(str(ps.get("desc", "")), f, ps) if ps.get("desc", "") != "" else ""
			_make_detail_tile_clickable(ps_tile, str(ps.get("name", "?")), psfull, psbrief, psdetail)
			sk_row.add_child(ps_tile)
		vb.add_child(sk_row)

	var hint := Label.new()
	hint.text = "点击空白处关闭"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)   # PoC .fdp-close-hint font-size:10px
	hint.add_theme_color_override("font_color", Color("#666666"))   # PoC color:#666 (原 white@.4)
	vb.add_child(hint)


## p2eq 装备 → 弹窗 edef: name + 效果(baseStats1 + effectDesc1 + 3星 effectDesc3 + 学派), icon=emoji。
##   修"点 p2eq 没反应"(老 equipment_by_id 无 p2eq); 字段读取参照图鉴 CodexScene 渲染。
## 装备某星级的属性串 (云顶式: 显当前星单值, 非 5/12/20 进度). 解析 baseStats1 "+攻5/12/20·暴击10/15/25%" 取第 star 档。
static func _p2eq_stat_line_from_str(bs: String, star: int) -> String:
	var out: Array = []
	for g in bs.split("·", false):
		var gs: String = str(g).strip_edges()
		var di := -1
		for i in range(gs.length()):
			if gs[i] >= "0" and gs[i] <= "9":
				di = i; break
		if di < 0:
			out.append(gs); continue
		var label: String = gs.substr(0, di)
		var nums_part: String = gs.substr(di)
		var suffix := ""
		if nums_part.ends_with("%"):
			suffix = "%"; nums_part = nums_part.substr(0, nums_part.length() - 1)
		var nums: Array = nums_part.split("/", false)
		var idx: int = clampi(star - 1, 0, maxi(0, nums.size() - 1))
		out.append(label + str(nums[idx]).strip_edges() + suffix)
	return "·".join(out)


static func _inject_atk_values(text: String, carrier_atk: int, carrier_crit: float = -1.0) -> String:
	# 云顶式: 龟身装备(知道携带龟ATK) -> 效果里 N×攻击力 / N×ATK / N%ATK 补实际值 (≈V)。备战席 carrier_atk=0 不动。
	#   数据用中文"攻击力"(非ATK字面), 原正则只匹 ATK → 实际从不命中; 兼容两写法。
	#   carrier_crit≥0 时再实算 N×暴击率 项 (主效果用; crit 为分数 0~1)。
	if carrier_atk <= 0 or text == "":
		return text
	var out := text
	# 1) 攻击力 / ATK 项 (×=直乘ATK, %=百分比×ATK)
	var re := RegEx.new()
	re.compile("([0-9.]+)(×攻击力|×ATK|%ATK)")
	var ms := re.search_all(out)
	for mi in range(ms.size() - 1, -1, -1):
		var m: RegExMatch = ms[mi]
		var num := m.get_string(1).to_float()
		var val: int = int(round(num * 0.01 * carrier_atk)) if m.get_string(2) == "%ATK" else int(round(num * carrier_atk))
		out = out.substr(0, m.get_start()) + m.get_string(0) + "(≈%d)" % val + out.substr(m.get_end())
	# 2) 暴击率 项 (主效果实算: N×暴击率 → N×crit, crit 为分数). carrier_crit<0=不实算 (席/商店).
	if carrier_crit >= 0.0:
		var rc := RegEx.new()
		rc.compile("([0-9.]+)×暴击率")
		var mc := rc.search_all(out)
		for mi in range(mc.size() - 1, -1, -1):
			var m2: RegExMatch = mc[mi]
			var num2 := m2.get_string(1).to_float()
			var val2: int = int(round(num2 * carrier_crit))
			out = out.substr(0, m2.get_start()) + m2.get_string(0) + "(≈%d)" % val2 + out.substr(m2.get_end())
	return out


## 逐星斜杠组 -> 当前星单值 (主效果实算用). "0.6/0.75/1.0×攻击力·15/28/50%" + star=2 → "0.75×攻击力·28%".
##   只替【3档(a/b/c)】斜杠组; 非3档 (如 "3层/5层" 之类2档或单值) 也按 star 取档 clamp, 但常见为3档。
static func _p2eq_pick_star_text(text: String, star: int) -> String:
	if text == "" or star < 1:
		return text
	var re := RegEx.new()
	re.compile("[0-9.]+(?:/[0-9.]+)+")   # 一组斜杠数列 a/b/c (≥2档)
	var ms := re.search_all(text)
	var out := text
	for mi in range(ms.size() - 1, -1, -1):
		var m: RegExMatch = ms[mi]
		var nums: PackedStringArray = m.get_string(0).split("/", false)
		var idx: int = clampi(star - 1, 0, maxi(0, nums.size() - 1))
		out = out.substr(0, m.get_start()) + str(nums[idx]).strip_edges() + out.substr(m.get_end())
	return out


## 加成区 (BBCode): 属性成长档 (baseStats1) 随星缩放列成 3档 a/[b]/c, 高亮当前星档.
##   只列属性(baseStats1); 效果系数(effectDesc1)已在主效果区按当前星实算, 不再机器抠斜杠组(原会乱码+重复).
##   返回 "" = 无随星缩放属性 (无加成区可显).
static func _p2eq_bonus_block(p2def: Dictionary, star: int) -> String:
	var rows: Array = []
	# ── 属性行: baseStats1 "+攻5/12/20·暴击10/15/25%" → 每组一行 "攻 5/[12]/20" ──
	var bs: String = str(p2def.get("baseStats1", "")).strip_edges()
	if bs != "":
		for g in bs.split("·", false):
			var gs: String = str(g).strip_edges()
			var di := -1
			for i in range(gs.length()):
				if gs[i] >= "0" and gs[i] <= "9":
					di = i; break
			if di < 0:
				continue
			var label: String = gs.substr(0, di).strip_edges()
			var nums_part: String = gs.substr(di)
			var suffix := ""
			if nums_part.ends_with("%"):
				suffix = "%"; nums_part = nums_part.substr(0, nums_part.length() - 1)
			var nums: PackedStringArray = nums_part.split("/", false)
			if nums.size() < 2:
				continue   # 单值不随星 → 不入加成区
			rows.append(label + " " + _p2eq_tier_str(nums, star, suffix))
	# ── 注: effectDesc1 系数行已删. 系数已在主效果区按当前星实算 (×攻击力/×暴击率→实数V), ──
	#    加成区再机器抠斜杠组当"档位"会把斜杠组后的中文(如"的生命/次随机敌人/连斩次数")误当单位→乱码,
	#    且与主效果区重复. 加成区只保留属性成长档 (baseStats1, 上面已收集). _p2eq_coef_unit 保留备用.
	if rows.is_empty():
		return ""
	var body := ""
	for r in rows:
		body += ("\n" if body != "" else "") + "· " + str(r)
	return "[color=#8fb4d6]属性成长 (当前 %d★)[/color]\n%s" % [star, body]


## 3档串高亮当前星: nums=[a,b,c], star=2 → "a/[color=#ffe9a8][b]b[/b][/color]/c" + 后缀. 单档无斜杠.
static func _p2eq_tier_str(nums: PackedStringArray, star: int, suffix: String) -> String:
	var cur: int = clampi(star - 1, 0, maxi(0, nums.size() - 1))
	var parts: Array = []
	for i in range(nums.size()):
		var v: String = str(nums[i]).strip_edges() + suffix
		if i == cur:
			parts.append("[color=#ffe9a8][b]%s[/b][/color]" % v)
		else:
			parts.append("[color=#8a9aa8]%s[/color]" % v)
	return "/".join(parts)


## 取斜杠组后的单位词 (加成行辨识标签). 扫后续中文/符号到下一个标点/数字止.
static func _p2eq_coef_unit(after: String) -> String:
	var u := ""
	for i in range(after.length()):
		var ch: String = after[i]
		if ch == "," or ch == "," or ch == ";" or ch == "；" or ch == "。" or ch == "(" or ch == "（" or ch == ")" or ch == "）" or ch == "·" or ch == "+" or ch == "且" or (ch >= "0" and ch <= "9"):
			break
		u += ch
		if u.length() >= 6:
			break
	u = u.strip_edges()
	return u if u != "" else "系数"


func _p2eq_popup_edef(eid: String, p2def: Dictionary, star: int = 0, carrier_atk: int = 0, carrier_crit: float = -1.0, equipped: bool = false) -> Dictionary:
	# 三上下文: 商店/备战席(equipped=false) → 现状内联三档; 上了龟(equipped=true) → 两区(主实算 + 加成区高亮当前星).
	#   用显式 equipped 而非 carrier_atk>0 判: atk=0 的上龟单位(龟蛋/被清零)也须走两区 (carrier_atk>0 兼判会漏掉它们).
	if equipped:
		return _p2eq_popup_edef_equipped(eid, p2def, maxi(1, star), carrier_atk, carrier_crit)
	var lines: Array = []
	var bs: String = str(p2def.get("baseStats1", "")).strip_edges()
	if bs != "":
		if star >= 1 and star <= 3:   # 云顶式: 知道星级 → 显当前星单值 (非 5/12/20 进度)
			lines.append("📊 属性(%d★): %s" % [star, _p2eq_stat_line_from_str(bs, star)])
		else:
			lines.append("📊 基础属性: " + bs)
	var e1: String = str(p2def.get("effectDesc1", "")).strip_edges()
	if e1 != "":
		lines.append(_inject_atk_values(e1, carrier_atk))
	var e3: String = str(p2def.get("effectDesc3", "")).strip_edges()
	if e3 != "":
		lines.append("⭐ 3星: " + _inject_atk_values(e3, carrier_atk))
	var schools: Array = Phase2Schools.schools_of(eid)
	if not schools.is_empty():
		var snames := ""
		for s in schools:
			snames += ("、" if snames != "" else "") + str(s)
		lines.append("🏛 学派: " + snames)
	var desc := ""
	for ln in lines:
		desc += ("\n\n" if desc != "" else "") + str(ln)
	# 弹窗图标: 有 img(.png 按机制对齐PoC装备图) 用图, 无图回退 emoji (_show_equip_popup 按 .png 后缀分图/emoji)
	var pop_icon := str(p2def.get("img", "")) if str(p2def.get("img", "")) != "" else str(p2def.get("emoji", ""))
	return {"name": str(p2def.get("name", eid)), "desc": desc, "icon": pop_icon, "category": "p2eq"}


## 上了龟 (有携带者) → TFT 两区式 (BBCode). bbcode=true 让 _show_equip_popup 用 RichTextLabel 渲染高亮.
##   主效果区: 效果=当前星实算 (×攻击力/×暴击率 补≈V) + 属性=当前星实数 ("+12攻"); 加成区: 3档高亮当前星.
func _p2eq_popup_edef_equipped(eid: String, p2def: Dictionary, star: int, carrier_atk: int, carrier_crit: float) -> Dictionary:
	var parts: Array = []
	# ── 主效果区 ──
	# 注: 主效果区原有 "📊 属性(当前星单值)" 行已去掉 — 属性成长档(随星3档高亮当前星)统一在下方加成区显示, 避免与加成区重复.
	var e1: String = str(p2def.get("effectDesc1", "")).strip_edges()
	if e1 != "":
		# 先取当前星单值 → 再实算 ×攻击力/×暴击率
		var e1_cur: String = _inject_atk_values(_p2eq_pick_star_text(e1, star), carrier_atk, carrier_crit)
		parts.append(e1_cur)
	var e3: String = str(p2def.get("effectDesc3", "")).strip_edges()
	if e3 != "" and star >= 3:   # 3星效果仅 3★ 携带者才生效 → 仅此时显
		parts.append("[color=#ff9ee6]⭐ 3星[/color]  " + _inject_atk_values(_p2eq_pick_star_text(e3, star), carrier_atk, carrier_crit))
	# ── 加成区 (主效果下方): 每条随星缩放列 3档, 高亮当前星 ──
	var bonus: String = _p2eq_bonus_block(p2def, star)
	if bonus != "":
		parts.append(bonus)
	# ── 学派 (尾) ──
	var schools: Array = Phase2Schools.schools_of(eid)
	if not schools.is_empty():
		var snames := ""
		for s in schools:
			snames += ("、" if snames != "" else "") + str(s)
		parts.append("[color=#c084fc]🏛 学派[/color]  " + snames)
	var desc := ""
	for ln in parts:
		desc += ("\n\n" if desc != "" else "") + str(ln)
	var pop_icon := str(p2def.get("img", "")) if str(p2def.get("img", "")) != "" else str(p2def.get("emoji", ""))
	return {"name": str(p2def.get("name", eid)), "desc": desc, "icon": pop_icon, "category": "p2eq", "bbcode": true}


## 装备详情弹窗 (左图右文 modal, 1:1 PoC DetailPanel showEquipDescPopup): 点详情面板装备格触发。
func _show_equip_popup(eid: String, edef_override: Dictionary = {}, star: int = 0, carrier_atk: int = 0, carrier_crit: float = -1.0, equipped: bool = false) -> void:
	# edef_override 非空 → 直接用 (宝箱专属装备 inline edef, 不在 equipment_by_id); 否则按 id 查注册表
	var edef: Dictionary = edef_override.duplicate() if not edef_override.is_empty() else DataRegistry.equipment_by_id.get(eid, {})
	if edef.is_empty() and _bench_buff_items.has(eid):
		# 单体增益: 用 buff 名/描述拼最小 edef 给弹窗渲染 (点击看详情, 1:1 PoC)
		var b: Dictionary = _bench_buff_items[eid]
		edef = {"name": str(b.get("name", "")), "desc": str(b.get("desc", "")), "category": "buff", "icon": ""}
	if edef.is_empty():
		# 双路 p2eq: 老 equipment_by_id 没有 → 用 phase2_equipment_by_id 的 effectDesc1/3 + emoji 拼 edef
		#   (修"点 p2eq 装备弹窗没反应" — 两表独立, p2eq 不在老注册表, 原 if edef.is_empty(): return 直接吞掉)
		var p2def: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
		if not p2def.is_empty():
			edef = _p2eq_popup_edef(eid, p2def, star, carrier_atk, carrier_crit, equipped)
	if edef.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.add_to_group("ui_modal")   # modal 浮层: 开着时挡住背后龟身 Area2D 点击 (修"点穿透到后面")
	layer.layer = 200   # 盖在详情面板之上
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			layer.queue_free())
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	# 1:1 PoC #poc-equip-popup: 420 宽, 蓝黑渐变近似, 3px #ffd766 描边, padding 14/16
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 0)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.086, 0.118, 0.188, 0.98)   # rgba(22,30,48,.98)
	csb.border_color = Color("#ffd766")
	csb.set_border_width_all(3)
	csb.set_corner_radius_all(10)
	csb.content_margin_left = 16; csb.content_margin_right = 16
	csb.content_margin_top = 14; csb.content_margin_bottom = 14
	csb.shadow_color = Color(0, 0, 0, 0.6); csb.shadow_size = 12
	card.add_theme_stylebox_override("panel", csb)
	center.add_child(card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)   # PoC gap 14
	card.add_child(hb)
	# 左: 图标盒 80×80 (img 72), 金调底 (1:1 PoC .edp-icon)
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(80, 80)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # align flex-start
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(1.0, 0.843, 0.0, 0.15)        # rgba(255,215,0,.15)
	isb.border_color = Color(1.0, 0.843, 0.0, 0.4)
	isb.set_border_width_all(2); isb.set_corner_radius_all(8)
	icon_box.add_theme_stylebox_override("panel", isb)
	var erel: String = str(edef.get("icon", ""))
	# 1:1 PoC: iconRaw.endsWith('.png')?<img 72>:<span .edp-icon-emoji 60px> (DetailPanel.ts:1897)
	if erel.ends_with(".png"):
		var efull := "res://assets/sprites/%s" % erel
		if ResourceLoader.exists(efull):
			var ic := TextureRect.new()
			ic.texture = load(efull)
			ic.custom_minimum_size = Vector2(72, 72)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_box.add_child(ic)
	elif erel != "":
		# emoji图标(海螺📯等), 1:1 PoC .edp-icon-emoji font-size:60 — 原只png→弹窗图标空
		var eml := Label.new()
		eml.text = erel
		eml.add_theme_font_size_override("font_size", 60)
		eml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_box.add_child(eml)
	hb.add_child(icon_box)
	# 右: 名 17px #ffd766 + 描述 13px #ddd (1:1 PoC .edp-title/.edp-body)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.custom_minimum_size = Vector2(290, 0)
	hb.add_child(rv)
	var nm := Label.new()
	nm.text = str(edef.get("name", eid))
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color("#ffd766"))
	rv.add_child(nm)
	if bool(edef.get("bbcode", false)):
		# 上了龟两区式: BBCode 高亮当前星 → RichTextLabel (Label 不支持 BBCode)
		var rich := RichTextLabel.new()
		rich.bbcode_enabled = true
		rich.fit_content = true
		rich.scroll_active = false
		rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rich.add_theme_font_size_override("normal_font_size", 13)
		rich.add_theme_font_size_override("bold_font_size", 13)
		rich.add_theme_font_override("normal_font", _get_panel_font(false))
		rich.add_theme_font_override("bold_font", _get_panel_font(true))
		rich.add_theme_color_override("default_color", Color("#dddddd"))
		rich.custom_minimum_size = Vector2(290, 0)
		rich.text = str(edef.get("desc", ""))
		rv.add_child(rich)
	else:
		var desc := Label.new()
		desc.text = _strip_html(str(edef.get("desc", "")))
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", Color("#dddddd"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(290, 0)
		rv.add_child(desc)


## 出招技能名横幅 (1:1 PoC showSkillAnnounce, BattleScene.ts:5004) — 出手前报技能名: [头像] 名 ▸ 技能名.
##   屏幕中心 440×40 黑底白边; 淡入→持续→淡出. 非阻塞 (与 600ms 蓄势并行).
func _show_skill_announce(actor: Dictionary, skill_name: String) -> void:
	if banner_layer == null:
		return
	var old := banner_layer.get_node_or_null("SkillAnnounce")
	if old != null:
		old.free()
	var rcol := _rarity_color(str(actor.get("rarity", "C")))
	var box := PanelContainer.new()
	box.name = "SkillAnnounce"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.75)                 # PoC scene.css:367 rgba(0,0,0,.75)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fid := str(actor.get("id", ""))
	var ipath := "res://assets/sprites/avatars/%s.png" % fid
	if ResourceLoader.exists(ipath):
		var ic := TextureRect.new()
		ic.texture = load(ipath)
		ic.custom_minimum_size = Vector2(28, 28)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hb.add_child(ic)
	var nm := Label.new()
	nm.text = str(actor.get("name", ""))
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", rcol)        # 名字稀有度色
	hb.add_child(nm)
	var arrow := Label.new()
	arrow.text = "▸"
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.add_theme_color_override("font_color", Color("#aaaaaa"))
	hb.add_child(arrow)
	var sk := Label.new()
	sk.text = skill_name
	sk.add_theme_font_size_override("font_size", 16)
	sk.add_theme_color_override("font_color", Color("#ffffff"))
	hb.add_child(sk)
	box.add_child(hb)
	box.modulate.a = 0.0
	banner_layer.add_child(box)
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.45)
	tw.tween_property(box, "modulate:a", 0.0, 0.28)
	tw.tween_callback(box.queue_free)


## 中央回合横幅 (1:1 PoC showCenterBanner): 滑入→停→滑出 + 渐隐. 非阻塞.
# ── 双路战中整备商店 (每4回合, 玩家暂停买装备/升星/买经验) ──
func _shop_lbl(size: int, color: Color, txt: String) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _get_panel_font(true))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.text = txt; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


var _battle_shop_layer: CanvasLayer = null
var _battle_shop_root: Control = null

## 常驻战中整备商店 (用户 2026-06-13: 不弹窗、一直在). 贴底常驻条, 不暗化全屏、不阻塞战斗;
##   买入/刷新/买经验即时生效并重建. 每回合 + 每 4 回合换货时刷新.
## 三合一合成【爆发演出】(装回龟身时, 替代平淡飘字): 龟身金脉冲 + 金星迸射 + 大字弹出 + 金环扩散 + 轻震屏。
func _play_merge_burst(idx: int, star: int, nm: String) -> void:
	if idx < 0 or idx >= slot_nodes.size():
		return
	var pos: Vector2 = slot_nodes[idx].get_meta("home_pos", slot_nodes[idx].position)
	_pulse_avatar(idx, 1.22, 0.28)
	_play_screen_shake(0.12, 3.0)
	# 金环扩散 (加到 slots_root 跟随相机)
	var ring := Control.new()
	ring.position = pos
	ring.z_index = 600   # 合成金环高过龟身(最深 ~497): 原 200 被龟立绘遮死
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rp := [0.0]
	ring.draw.connect(func() -> void:
		ring.draw_arc(Vector2.ZERO, 12.0 + rp[0] * 56.0, 0.0, TAU, 48, Color(1.0, 0.85, 0.3, (1.0 - rp[0]) * 0.85), 4.0, true))
	slots_root.add_child(ring)
	var trw := create_tween()
	trw.tween_method(func(v: float): rp[0] = v; if is_instance_valid(ring): ring.queue_redraw(), 0.0, 1.0, 0.45)
	trw.chain().tween_callback(ring.queue_free)
	# 金星迸射
	var ns: int = star * 2 + 4
	for si in range(ns):
		var sl := Label.new()
		sl.text = "⭐"
		sl.add_theme_font_size_override("font_size", 16)
		sl.z_index = 600   # 合成迸射金星高过龟身(最深 ~497): 原 200 被龟立绘遮死
		sl.position = pos
		slots_root.add_child(sl)
		var ang: float = TAU * float(si) / float(ns) - PI / 2.0
		var dist: float = 38.0 + float(si % 3) * 14.0
		var stw := create_tween()
		stw.set_parallel(true)
		stw.tween_property(sl, "position", pos + Vector2(cos(ang), sin(ang)) * dist, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		stw.tween_property(sl, "modulate:a", 0.0, 0.55)
		stw.chain().tween_callback(sl.queue_free)
	# 大字弹出 (scale 弹入 → 停留 → 上浮淡出)
	var big := Label.new()
	big.text = "%d★ %s!" % [star, nm]
	big.add_theme_font_size_override("font_size", 24)
	big.add_theme_color_override("font_color", Color("#ffe24d"))
	big.add_theme_color_override("font_outline_color", Color(0.28, 0.18, 0.0))
	big.add_theme_constant_override("outline_size", 6)
	big.z_index = 601   # 合成大字叠在金环/金星之上, 均高过龟身 (原 201 被遮)
	big.size = Vector2(220, 34)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.pivot_offset = Vector2(110, 17)
	big.position = pos + Vector2(-110, -82)
	big.scale = Vector2(0.2, 0.2)
	slots_root.add_child(big)
	var btw := create_tween()
	btw.tween_property(big, "scale", Vector2(1.12, 1.12), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	btw.tween_property(big, "scale", Vector2(1.0, 1.0), 0.1)
	btw.tween_interval(0.45)
	btw.tween_property(big, "modulate:a", 0.0, 0.4)
	btw.parallel().tween_property(big, "position:y", big.position.y - 24.0, 0.4)
	btw.chain().tween_callback(big.queue_free)


## 三合一合成反馈 (买入/装备后调): 读 GameState.last_merges → 爆发演出(装到的龟身上) + 战斗log。
##   修审计"星级三合一静默无反馈"。
func _show_merge_feedback() -> void:
	for m in GameState.last_merges:
		if not (m is Dictionary):
			continue
		var nm: String = str(DataRegistry.phase2_equipment_by_id.get(str(m.get("id", "")), {}).get("name", m.get("id", "")))
		var star: int = int(m.get("star", 2))
		var pet: String = str(m.get("pet", ""))
		if is_instance_valid(battle_log):
			battle_log.append_text("[color=#ffd93d]⭐ 三合一: %s 升 %d★%s[/color]\n" % [nm, star, ((" → " + pet) if pet != "" else "(留备战席)")])
		if pet != "":
			for fi in range(fighters.size()):
				if str(fighters[fi].get("id", "")) == pet and str(fighters[fi].get("side", "")) == "left":   # 修(审计A2#2): 限我方, 否则镜像局把合星演出放到敌方同名龟身上
					_play_merge_burst(fi, star, nm)
					break
	GameState.last_merges = []


## 战中 TFT 3合1(可见): 扫我方(左)单位 _p2_equips + 备战席(跳过单体增益), 同id同星≥3 → 合1高星,
##   优先装回参与的龟(超槽退席), 全在席留席。merge_restat 重算属性 + recalc + 飘字反馈。
##   [战中专属: 龟身装备存 _p2_equips ≠ 持久 equipped_p2; 大地图持久流用 GameState.try_merge_all]
##   反复直到无可合。
func _battle_merge_p2eq() -> void:
	var merges: Array = []
	var safety: int = 0
	while safety < 64:
		safety += 1
		var flat: Array = []   # {id, star, ofi(-1=备战席, else fighter idx)}
		for b in bench_inventory:
			if b is Dictionary and not _bench_buff_items.has(str(b.get("id", ""))):
				flat.append({"id": str(b.get("id", "")), "star": int(b.get("star", 1)), "ofi": -1})
		for fi in range(fighters.size()):
			if str(fighters[fi].get("side", "")) != "left":
				continue
			for it in fighters[fi].get("_p2_equips", []):
				if it is Dictionary:
					flat.append({"id": str(it.get("id", "")), "star": int(it.get("star", 1)), "ofi": fi})
		var groups: Dictionary = {}
		for idx in range(flat.size()):
			var it: Dictionary = flat[idx]
			if int(it["star"]) >= 3:
				continue
			var k: String = "%s|%d" % [str(it["id"]), int(it["star"])]
			if not groups.has(k):
				groups[k] = []
			(groups[k] as Array).append(idx)
		var pick: Array = []
		var mid: String = ""
		var mstar: int = 0
		for k in groups:
			if (groups[k] as Array).size() >= 3:
				pick = (groups[k] as Array).slice(0, 3)
				mid = str(k).split("|")[0]
				mstar = int(str(k).split("|")[1])
				break
		if pick.is_empty():
			break
		var dest_fi: int = -1
		for pi in pick:
			if int(flat[pi]["ofi"]) >= 0:
				dest_fi = int(flat[pi]["ofi"])
				break
		var rm: Dictionary = {}
		for pi in pick:
			rm[pi] = true
		var nb: Array = []
		var ne: Dictionary = {}
		for idx in range(flat.size()):
			if rm.has(idx):
				continue
			var it: Dictionary = flat[idx]
			if int(it["ofi"]) == -1:
				nb.append({"id": str(it["id"]), "star": int(it["star"])})
			else:
				var owf: int = int(it["ofi"])
				if not ne.has(owf):
					ne[owf] = []
				(ne[owf] as Array).append({"id": str(it["id"]), "star": int(it["star"])})
		var affected: Dictionary = {}
		for pi in pick:   # un-apply 被合的【装在龟身】件 (备战席件无属性)
			var owf2: int = int(flat[pi]["ofi"])
			if owf2 >= 0:
				Phase2EquipRuntime.merge_restat(fighters[owf2], str(flat[pi]["id"]), int(flat[pi]["star"]), -1.0)
				affected[owf2] = true
		var placed_pet: String = ""
		if dest_fi >= 0:
			var cap: int = Phase2Config.equip_slots_for_level(int(GameState.dual_level.get("left", 1)))
			if not ne.has(dest_fi):
				ne[dest_fi] = []
			if (ne[dest_fi] as Array).size() < cap or fighters[dest_fi].get("_isEgg", false):
				(ne[dest_fi] as Array).append({"id": mid, "star": mstar + 1})
				Phase2EquipRuntime.merge_restat(fighters[dest_fi], mid, mstar + 1, 1.0)
				affected[dest_fi] = true
				placed_pet = str(fighters[dest_fi].get("id", ""))
			else:
				nb.append({"id": mid, "star": mstar + 1})
		else:
			nb.append({"id": mid, "star": mstar + 1})
		bench_inventory.assign(nb)   # 修(审计A2#1): in-place 改, 别重新赋值=切断与 GameState.bench_inventory 共享引用 → 合星后买的装备进不了备战席
		for fi in range(fighters.size()):
			if str(fighters[fi].get("side", "")) == "left":
				fighters[fi]["_p2_equips"] = ne.get(fi, [])
		for fi in affected:
			var allies: Array = []
			for a in fighters:
				if str(a.get("side", "")) == "left" and a.get("alive", false):
					allies.append(a)
			StatsRecalc.recalc(fighters[fi], allies)
		merges.append({"id": mid, "star": mstar + 1, "pet": placed_pet})
	if not merges.is_empty():
		GameState.last_merges = merges
		_show_merge_feedback()
		_rebuild_bench_rail()
		for i in range(fighters.size()):
			if str(fighters[i].get("side", "")) == "left":
				_refresh_slot(i)


func _ensure_battle_shop() -> void:
	if _battle_shop_layer != null and is_instance_valid(_battle_shop_layer):
		_rebuild_battle_shop()
		return
	if (GameState.dual_shop_offer as Array).is_empty():
		GameState.roll_shop_offer("left")
	_battle_shop_layer = CanvasLayer.new(); _battle_shop_layer.layer = 40
	add_child(_battle_shop_layer)
	_battle_shop_root = Control.new()
	_battle_shop_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_battle_shop_root.offset_top = -float(HUD_BENCHROW_SHOP_H)   # 矮到 160 (原-200/更早-240): 为战场下方横排备战席腾出空间 (用户 2026-06-26 云顶式上下分层); 实际显隐由 _position_battle_shop 定
	_battle_shop_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 只商店条本身挡点击, 其余透传给战斗
	_battle_shop_layer.add_child(_battle_shop_root)
	_rebuild_battle_shop()
	var _abar = action_panel.get_node_or_null("SkillBar") if action_panel != null else null
	_position_battle_shop(_abar != null and _abar.visible)   # 初始按技能条当前显隐定位


## 整备商店避让技能条: 原设计技能条显示时商店上移到其上方, 隐藏时落回贴底 (防重合).
##   新出手流程已改"技能图标浮龟头顶"(_show_skill_icons), 底部 SkillBar 永远 visible=false
##   (2794/2814/3214 只设 false, 全文无一处设 true) → action_up 恒为 false, 上移避让分支永不执行。
##   保留 action_up 参数以兼容两处调用点, 但删死分支(上移 -360 那支), 商店始终贴底定位。
func _position_battle_shop(_action_up: bool) -> void:
	if _battle_shop_root == null or not is_instance_valid(_battle_shop_root):
		return
	# SkillBar 永不可见 → 始终贴底 (原 action_up=true 上移 -360/-184 分支为死代码, 已删)
	_battle_shop_root.offset_top = -float(HUD_BENCHROW_SHOP_H)   # 矮到 160: 给战场下方横排备战席腾位 (与 _ensure_battle_shop 单一来源)
	_battle_shop_root.offset_bottom = 0.0


func _rebuild_battle_shop() -> void:
	if _battle_shop_root == null or not is_instance_valid(_battle_shop_root):
		return
	for c in _battle_shop_root.get_children():
		c.queue_free()
	var lv := int(GameState.dual_level.get("left", 1))
	var coins := int(GameState.dual_coins.get("left", 0))
	if _deep_coin_val_l != null and is_instance_valid(_deep_coin_val_l):   # 双路: HUD 深海币 pill 同步局内币 (否则 pill 显 battle_coins=0 与商店不一致). 每回合/买/刷新都过这
		_set_deep_coin("left", coins, coins != _deep_coin_shown_l)
	var panel := Panel.new()
	var psb := StyleBoxFlat.new(); psb.bg_color = Color(0.047, 0.102, 0.149, 0.96); psb.set_corner_radius_all(12)
	psb.set_border_width_all(2); psb.border_color = Color("#5aa9ff")
	panel.add_theme_stylebox_override("panel", psb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 16; panel.offset_right = -16; panel.offset_top = 4; panel.offset_bottom = -8
	panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 商店条挡点击(不穿到龟)
	_battle_shop_root.add_child(panel)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 3)   # 缩小(F5): 行间距 4→3
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12; vb.offset_right = -12; vb.offset_top = 6; vb.offset_bottom = -6
	panel.add_child(vb)
	var bench_n := GameState.bench_inventory.size()
	var title := _shop_lbl(13, Color("#ffd93d"), "🛒 整备商店 · Lv%d · 备战席 %d/%d (同款3合1升星 · 装备拖到龟身上)" % [lv, bench_n, Phase2Config.BENCH_CAP])   # 缩小(F5): 15→13
	vb.add_child(title)
	# 顶部压一行 (F5 紧凑化): 经验条 + 出现概率 挤进同一行, 省两整行竖向 (原 xp_row / prob_row 分两行)。
	#   行内: [Lv经验] [xp条160] [x/n] │ [概率] 1费% 2费% ... — 中间竖隔线分两区。
	var _cur_xp: int = int(GameState.dual_xp.get("left", 0))
	var _need_xp: int = maxi(1, Phase2Config.xp_to_next(lv)) if lv < Phase2Config.MAX_LEVEL else 1
	var top_row := HBoxContainer.new(); top_row.add_theme_constant_override("separation", 6)   # 紧凑(F5): 间距 8→6 防 Lv7-9 多位百分比+CJK 撑过 1248 宽
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.clip_contents = true   # 极端超宽兜底: 宁可裁右端也不画出商店面板外 (F5 验)
	vb.add_child(top_row)
	top_row.add_child(_shop_lbl(12, Color("#a0e8ff"), "Lv%d 经验" % lv))
	var xp_bar := ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(160, 12)   # 紧凑(F5): 条宽 240→160 腾位放概率
	xp_bar.max_value = float(_need_xp)
	xp_bar.value = float(_cur_xp) if lv < Phase2Config.MAX_LEVEL else float(_need_xp)
	xp_bar.show_percentage = false
	var _xpfill := StyleBoxFlat.new(); _xpfill.bg_color = Color("#4fd1ff"); _xpfill.set_corner_radius_all(4)
	var _xpbg := StyleBoxFlat.new(); _xpbg.bg_color = Color("#0c1822"); _xpbg.set_corner_radius_all(4); _xpbg.set_border_width_all(1); _xpbg.border_color = Color("#33485a")
	xp_bar.add_theme_stylebox_override("fill", _xpfill)
	xp_bar.add_theme_stylebox_override("background", _xpbg)
	top_row.add_child(xp_bar)
	top_row.add_child(_shop_lbl(12, Color("#a0e8ff"), ("%d/%d" % [_cur_xp, _need_xp]) if lv < Phase2Config.MAX_LEVEL else "满级"))
	top_row.add_child(_shop_lbl(13, Color("#33485a"), "│"))   # 竖隔线: 经验区 │ 概率区
	# TFT 式费用概率 (用户要"参考云顶抽装备区, 概率也要显示"): 当前等级各费用出现概率 (1费灰/2绿/3蓝/4紫/5金)
	var odds: Array = Phase2Config.shop_cost_odds(lv)
	top_row.add_child(_shop_lbl(11, Color("#8aa0b0"), "概率"))
	var _cost_cols: Array = [Color("#c8d2da"), Color("#46c167"), Color("#4aa3e0"), Color("#b06fe0"), Color("#f0c020")]
	for ci in range(5):
		var pct: int = int(odds[ci]) if ci < odds.size() else 0
		var pl := _shop_lbl(11, _cost_cols[ci], "%d费%d%%" % [ci + 1, pct])   # 紧凑(F5): 字 12→11 + 去"费"后空格, 防高等级多位%撑宽
		if pct == 0:
			pl.modulate = Color(1, 1, 1, 0.35)   # 0% 暗显
		top_row.add_child(pl)
	# 货架 5 卡 (横排, 紧凑)
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 6); hb.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 缩小(F5): 卡间距 8→6
	vb.add_child(hb)
	var offer: Array = GameState.dual_shop_offer
	for i in range(offer.size()):
		var it = offer[i]
		# 紧凑卡 (F5 商店紧凑化): 158×64 (原 106) — 图标 + 名字 + 费用钮; 效果文字转 hover tooltip / 点图标看详情 popup。
		var card := Panel.new(); card.custom_minimum_size = Vector2(158, 64); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 纵向不撑: 否则被 hb 行高撑到 ~90-106 → 卡内绝对定位的买钮(y46)浮中间/点不中
		var csb := StyleBoxFlat.new(); csb.bg_color = Color("#10202c"); csb.set_corner_radius_all(8)
		var _bc_cost := int(it.get("cost", 1)) if it is Dictionary else 1   # TFT式: 边框按费用上色(费用=档次, 不用rarity)
		var _bcol: String = {1: "#94a3b8", 2: "#4cc9f0", 3: "#06d6a0", 4: "#c77dff", 5: "#ffd93d"}.get(_bc_cost, "#33485a")
		csb.set_border_width_all(2); csb.border_color = Color(_bcol)
		card.add_theme_stylebox_override("panel", csb)
		hb.add_child(card)
		if not (it is Dictionary):
			var sold := _shop_lbl(15, Color("#5a6b7a"), "已售"); sold.set_anchors_preset(Control.PRESET_FULL_RECT)
			sold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			card.add_child(sold); continue
		# hover tooltip = 类型/学派(羁绊) + 效果文字(effectDesc1, 1★); 替代原卡上印的效果/学派行, 卡身留图标+名字+费用。
		var _schs: Array = Phase2Schools.schools_of(str(it.get("id", "")))
		var _typ: String = Phase2Types.type_of(str(it.get("id", "")))
		var _schtxt: String = "·".join(PackedStringArray(_schs)) if not _schs.is_empty() else ""
		var _stxt: String = _typ + ((" · " + _schtxt) if _schtxt != "" else "")
		var _eff: String = str(it.get("effectDesc1", ""))
		card.tooltip_text = "%s\n%s%s" % [str(it.get("name", "")), (_stxt + "\n") if _stxt != "" else "", _eff]
		# 图标: PoC 有贴图(img .png)用图(28×28居中), 无图回退 emoji。点图标 → 详情 popup (effectDesc 全档)。
		var _eid_pop := str(it.get("id", ""))
		var _shop_img_rel := str(it.get("img", ""))
		var _shop_img_full := "res://assets/sprites/%s" % _shop_img_rel if _shop_img_rel != "" else ""
		if _shop_img_full != "" and ResourceLoader.exists(_shop_img_full):
			var pic := TextureRect.new()
			pic.texture = load(_shop_img_full)
			pic.custom_minimum_size = Vector2(28, 28)   # 卡内约束: PoC 装备图原生很大, 必约束否则爆
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(pic)
			# Panel 父非容器: .size/.position 必在 add_child 后设 (否则被 add 布局 pass 覆盖→取纹理原生大小)
			pic.position = Vector2((158 - 28) / 2.0, 3); pic.size = Vector2(28, 28)
		else:
			var emo := _shop_lbl(24, Color.WHITE, str(it.get("emoji", "📦")))
			emo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; card.add_child(emo)
			emo.position = Vector2(0, 3); emo.size = Vector2(158, 28)   # Panel 父非容器: .size/.position 必在 add_child 后设 (与 pic 同根因)
		var nm := _shop_lbl(12, Color.WHITE, str(it.get("name", "")))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; card.add_child(nm)
		nm.position = Vector2(3, 30); nm.size = Vector2(152, 15)   # 同上: add_child 后定位
		# 点卡(图标/名字区) → 弹详情 popup; 买入靠下方费用钮 (不破坏现有买逻辑)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_show_equip_popup(_eid_pop))
		var cost := int(it.get("cost", 1))
		var buy := Button.new(); buy.add_theme_font_override("font", _get_panel_font(true)); buy.add_theme_font_size_override("font_size", 13)
		buy.text = "%d" % cost   # 紧凑(F5): 费用钮锚卡底, 命中区加高到24 (原 y46 h16 仅16高+被行高撑偏→点不中16px), 详见下行 add_child 后定位
		var _dc := "res://assets/sprites/battle/deep-coin.png"   # 深海币图标(=顶部货币同款), 替 🪙 emoji
		if ResourceLoader.exists(_dc):
			buy.icon = load(_dc); buy.add_theme_constant_override("icon_max_width", 14); buy.expand_icon = true
		# 满席默认禁用买; 但若【买进这张(1星)会立刻凑成三合一】(本侧龟身+席已有≥2件同id+1星), 净占用-1 → 放行 (1:1 GameState.buy_shop_item / 云顶满席仍能买能合的牌)
		var _cap_block := bench_n >= Phase2Config.BENCH_CAP and not GameState._buy_would_merge(str(it.get("id", "")), 1, "left")
		buy.disabled = coins < cost or _cap_block
		var bi := i
		buy.pressed.connect(func(): GameState.buy_shop_item(bi, "left"); _battle_merge_p2eq(); _rebuild_battle_shop(); _rebuild_bench_rail())   # 买入后: 战中3合1(扫龟身+席,含飘字反馈) + 刷备战席
		card.add_child(buy)
		# Panel 父非容器: .size/.position 必在 add_child 后设 (与 pic/emo/nm 同根因). 命中区加高到24并锚卡底(64) → 点得中.
		buy.position = Vector2(12, 40); buy.size = Vector2(134, 24)
	# 控制行: 买经验 + 刷新
	var ctl := HBoxContainer.new(); ctl.add_theme_constant_override("separation", 10)
	vb.add_child(ctl)
	var xp_btn := Button.new(); xp_btn.add_theme_font_override("font", _get_panel_font(true)); xp_btn.add_theme_font_size_override("font_size", 14)
	xp_btn.text = "买经验 +%d (%d币)" % [Phase2Config.BUY_XP_AMOUNT, Phase2Config.BUY_XP_COST]
	xp_btn.disabled = coins < Phase2Config.BUY_XP_COST or lv >= Phase2Config.MAX_LEVEL
	xp_btn.pressed.connect(func(): GameState.buy_xp("left"); _resync_spawned_egg_hp(); _rebuild_battle_shop())   # 买经验升级 → 同步已登场蛋 maxHp/hp
	ctl.add_child(xp_btn)
	var rf := Button.new(); rf.add_theme_font_override("font", _get_panel_font(true)); rf.add_theme_font_size_override("font_size", 14)
	var _rcost: int = Phase2Config.shop_refresh_cost(0)   # 云顶式 flat 2, 不递增 (= refresh_shop 扣费, 单一来源)
	rf.text = "🔄 刷新 (%d币)" % _rcost
	rf.disabled = coins < _rcost
	rf.pressed.connect(func(): GameState.refresh_shop("left"); _rebuild_battle_shop())
	ctl.add_child(rf)
	# TFT 式锁店钮: 锁定后每回合不免费换货, 保住看中的货 (用户审计: 商店缺锁定钮, 没买的被冲掉)
	var lk := Button.new(); lk.add_theme_font_override("font", _get_panel_font(true)); lk.add_theme_font_size_override("font_size", 14)
	lk.text = "🔒 已锁定" if GameState.dual_shop_locked else "🔓 锁定货架"
	lk.tooltip_text = "锁定后每回合不免费换货, 保住看中的货 (TFT 式)"
	if GameState.dual_shop_locked:
		lk.add_theme_color_override("font_color", Color("#ffd93d"))
	lk.pressed.connect(func(): GameState.dual_shop_locked = not GameState.dual_shop_locked; _rebuild_battle_shop())
	ctl.add_child(lk)


func _show_center_banner(text: String, sub: String = "", color: String = "#ffd93d", duration: float = 1.1) -> void:
	if banner_layer == null:
		return
	# box 包背景带+文字; 手动按视口居中 (容器+anchor 在 CanvasLayer 居中不稳, 实测偏左)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	# 背景带: 暗蓝带 rgba(20,30,60,.92) + 金上下边 2px + padding 18/64
	var band := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.078, 0.118, 0.235, 0.92)
	bsb.border_width_top = 2; bsb.border_width_bottom = 2
	bsb.border_color = Color(1.0, 0.843, 0.239, 0.5)   # rgba(255,215,61,.5) 金
	bsb.content_margin_left = 64; bsb.content_margin_right = 64
	bsb.content_margin_top = 18; bsb.content_margin_bottom = 18
	band.add_theme_stylebox_override("panel", bsb)
	box.add_child(band)
	var textbox := VBoxContainer.new()
	textbox.alignment = BoxContainer.ALIGNMENT_CENTER
	band.add_child(textbox)
	var ls_main := FontVariation.new()   # letter-spacing 6px (Label 无原生字间距 → FontVariation.spacing_glyph)
	ls_main.base_font = _get_panel_font(true)
	ls_main.spacing_glyph = 6
	var main := Label.new()
	main.text = text
	main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_theme_font_override("font", ls_main)
	main.add_theme_font_size_override("font_size", 36)
	main.add_theme_color_override("font_color", Color(color))
	main.add_theme_constant_override("outline_size", 6)
	main.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	textbox.add_child(main)
	if sub != "":
		var ls_sub := FontVariation.new()
		ls_sub.base_font = _get_panel_font(false)
		ls_sub.spacing_glyph = 3
		var subl := Label.new()
		subl.text = sub
		subl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subl.add_theme_font_override("font", ls_sub)
		subl.add_theme_font_size_override("font_size", 14)
		subl.add_theme_color_override("font_color", Color("#cccccc"))
		textbox.add_child(subl)
	banner_layer.add_child(box)
	box.modulate.a = 0.0
	await get_tree().process_frame   # 等一帧算出 box.size 再居中 (banner 非阻塞, 延一帧无感)
	if not is_instance_valid(box):
		return
	var vp := get_viewport().get_visible_rect().size
	var cx := (vp.x - box.size.x) / 2.0
	var cy := (vp.y - box.size.y) / 2.0 - 40.0   # 略偏上 (PoC top:42%)
	box.position = Vector2(cx - 120.0, cy)
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.27)
	tw.parallel().tween_property(box, "position:x", cx, 0.27)
	tw.tween_interval(duration * 0.5)
	tw.tween_property(box, "position:x", cx + 120.0, 0.26)
	tw.parallel().tween_property(box, "modulate:a", 0.0, 0.26)
	tw.tween_callback(box.queue_free)


## 侧回合横幅 (PoC showSideTurnBanner): 左队🐢我方/右队👹敌方, 从对应侧滑入. 非阻塞.
func _show_side_banner(side: String) -> void:
	if banner_layer == null:
		return
	var is_left := side == "left"
	var lbl := Label.new()
	lbl.text = "🐢 我方回合" if is_left else "👹 敌方回合"
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.09, 0.82)
	sb.set_border_width_all(3)
	sb.border_color = Color("#06d6a0") if is_left else Color("#ff6b6b")
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(lbl)
	banner_layer.add_child(pc)
	pc.position = Vector2(-280 if is_left else 1280, 216)
	var target_x := VIEW_W * 0.30 - 80 if is_left else VIEW_W * 0.70 - 80
	var tw := create_tween()
	tw.tween_property(pc, "position:x", target_x, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(pc, "position:x", -280.0 if is_left else 1280.0, 0.24).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pc, "modulate:a", 0.0, 0.24)
	tw.tween_callback(pc.queue_free)


## 开场日志 (1:1 PoC BattleScene.ts:1642-1644): 战斗开始! + 双方协同激活.
##   PoC 无 开场头/阵容roster/装备列表 → 删自创verbose, 严格对齐.
func _log_init() -> void:
	battle_log.bbcode_enabled = true
	battle_log.append_text("战斗开始!\n")
	if GameState.mode != "duallane":   # 老 pet-tag 协同日志仅老模式/教程; 双路无 pet-tag 羁绊 (V2 阶段0)
		var left_tagged: Array = []
		var right_tagged: Array = []
		for f in fighters:
			var tags: Array = DataRegistry.pet_synergy_tags.get(str(f.get("id", "")), [])
			if f.get("side", "") == "left":
				left_tagged.append({"tags": tags})
			else:
				right_tagged.append({"tags": tags})
		for s in Synergies.calc_active(left_tagged):
			var nm: String = DataRegistry.synergies.get(s["tag"], {}).get("name", s["tag"])
			battle_log.append_text("协同激活: %s ×%d\n" % [nm, int(s["tier"])])
		for s in Synergies.calc_active(right_tagged):
			var nm: String = DataRegistry.synergies.get(s["tag"], {}).get("name", s["tag"])
			battle_log.append_text("敌方协同: %s ×%d\n" % [nm, int(s["tier"])])
	status_bar.text = "✓ DataRegistry 已加载. 6 龟入场, 战斗开始..."


# ─── 二阶段双路: 攻蛋阶段 (一方全灭 → 蛋登场前排中间, 胜方攻 N 回合, 跨场累计) ───
const EGG_SLOT := "front-1"   # 蛋登场槽位: 前排中间

## 哪一方被全灭了 ("left"/"right"/""=没有一方全灭). 只数真单位(龟/召唤), 不数蛋.
func _wiped_side() -> String:
	var alive := {"left": 0, "right": 0}
	for f in fighters:
		if f.get("_isEgg", false):
			continue
		if not _is_combatant(f):
			continue
		alive[f.get("side", "left")] = int(alive.get(f.get("side", "left"), 0)) + 1
	if int(alive["left"]) == 0 and int(alive["right"]) > 0:
		return "left"
	if int(alive["right"]) == 0 and int(alive["left"]) > 0:
		return "right"
	return ""

## 某方是否还有存活统领 (非小将/蛋) — 平局兜底判路胜方用.
func _side_has_alive_turtle(side: String) -> bool:
	for f in fighters:
		if str(f.get("side", "")) == side and f.get("alive", false) \
				and not f.get("_isMinion", false) and not f.get("_isEgg", false):
			return true
	return false

## 龟蛋是否已作为单位登场 (每方每场一次; 跨路重新 spawn).
func _egg_spawned(side: String) -> bool:
	for f in fighters:
		if f.get("_isEgg", false) and str(f.get("side", "")) == side:
			return true
	return false


## 局内升级后同步【已登场】龟蛋单位的 maxHp/hp: egg_hp_max 随级涨, 但蛋 spawn 时已定格
##   → 升级时蛋已在场则 maxHp 不刷(用户报"龟蛋最大生命升级没变"), 强化回血也到不了蛋。
##   蛋 fighter.hp 是权威账本(_sync_egg_hp 回写 egg_hp), 调用点(回合首/买经验)非战斗中已同步 → 安全覆写。
func _resync_spawned_egg_hp() -> void:
	if GameState.mode != "duallane":
		return
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("_isEgg", false):
			continue
		var side: String = str(f.get("side", ""))
		var nm: int = maxi(1, int(GameState.egg_hp_max.get(side, int(f.get("maxHp", 1)))))
		nm += int(f.get("_ancientEggBonus", 0))   # 远古蛋HP加成持续 (升级 resync 不丢)
		f["maxHp"] = nm
		f["hp"] = clampi(int(GameState.egg_hp.get(side, int(f.get("hp", 0)))), 0, nm)
		_refresh_slot(i)


## 上/下路: 场上有蛋且【已挨打满 EGG_ATTACK_ROUNDS 回合】→ 本路收尾 (蛋剩血写回 egg_hp 带入下路).
##   蛋登场当回合算第0轮 (登场后接着的回合开始检查); 终极战场不调此 (凿穿为止).
func _egg_attack_rounds_done() -> bool:
	for f in fighters:
		if f.get("_isEgg", false) and f.get("alive", false):
			if turn - int(f.get("_eggSpawnTurn", turn)) >= Phase2Config.EGG_ATTACK_ROUNDS:
				return true
	return false


## 034 玩偶小熊 / e_doll: 满层 → 召唤【大熊】fighter (250HP/50攻 物理近战) 进空位, 复用 _spawn_combatant 管线.
##   有空位才召唤 → 销毁玩偶装备 (从携带者 _p2_equips 移除 + _equipped_ids 移除 + 标 _p2DollSpawned/_equipDollSpawned).
##   无空位 → 不召唤不销毁 (装备继续每回合小熊攻, 直到有空位; 1:1 PoC 规格).
## 返回大熊的 fighters[] 索引 (-1 = 没空位/没召唤).
func _spawn_big_bear(owner: Dictionary) -> int:
	if not is_instance_valid(self):
		return -1
	var slot: String = _find_summon_slot(owner)
	if slot == "":
		return -1   # 阵地满, 继续攒/小熊攻 (不销毁装备)
	var side: String = str(owner.get("side", "left"))
	var is_front: bool = slot.begins_with("front")
	var bear: Dictionary = {
		"id": "doll_bear",
		"name": "大熊",
		"emoji": "🧸",
		"rarity": "C",
		"side": side,
		"img": "pets/doll-bear.png", "sprite": null,   # doll-bear.png 已存在 → 立绘; 缺则 emoji 兜底
		"_level": int(owner.get("_level", 1)),
		"_maxEnergy": 0, "_energy": 0,
		"maxHp": 250, "hp": 250, "shield": 0,           # e_doll 大熊: 250HP / 50攻 (规格确认)
		"baseAtk": 50, "baseDef": 0, "baseMr": 0,
		"atk": 50, "def": 0, "mr": 0,
		"crit": 0.0,
		"armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
		"passive": null, "passiveUsedThisTurn": false,
		"skills": [{
			"name": "熊掌", "type": "physical", "hits": 1, "power": 0, "pierce": 0,
			"atkScale": 1.0, "cd": 0, "cdLeft": 0, "energyCost": 0,
			"icon": "🧸", "brief": "", "detail": "",
		}],
		"_passiveSkills": [],
		"alive": true, "buffs": [], "tags": [],
		"_position": "front" if is_front else "back",
		"_slotKey": slot,
		"_statsDirty": false,
		"equipment": [],
		"_isSummon": true,   # 召唤单位: side-end 自动行动 + 主人阵亡不级联(无 _owner → 独立存活)
		"_isBigBear": true,
	}
	var idx := _spawn_combatant(bear)
	var node: Node2D = slot_nodes[idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	if av != null and is_instance_valid(av):
		var hs: Vector2 = av.get_meta("home_scale", av.scale)
		av.scale = hs * 0.3
		var tw: Tween = av.create_tween()
		tw.tween_property(av, "scale", hs * 1.12, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(av, "scale", hs, 0.12)
	_play_summon_burst(idx, Color(1.0, 0.82, 0.4))   # 034玩偶小熊: 大熊入场琥珀色召唤光环 (需F5)
	_spawn_passive_text(idx, "🧸 大熊登场!")
	battle_log.append_text("[color=#ffd166]🧸 %s 召唤【大熊】(250HP/50攻)![/color]\n" % str(owner.get("name", "?")))
	return idx


# ════════════════════════════════════════════════════════════════
# 灵物[召唤] 无敌触手 (规格 #553 / docs/specs/类型效果-实装规格.md:128): 激活 3/5 → 该侧 1/2 个【场边】触手登场.
#   触手 = _untargetable 无敌单位(免伤/不可选/胜负排除), 每回合朝一目标拍击, 对【沿途敌人】(触手→目标
#   拍击线穿过的敌人) 每人 (4%目标maxHP + 55) × dmg_mult 物理.
#   dmg_mult = 1 + 5%×Σ每件独特灵物星级 (Phase2Types.tentacle_setup).
#   己方每成功闪避 → 触手立即追加 1 次拍击(25%原伤害), 每回合最多 3 次 (_tentacleDodgeChase 累计, 拍击时消费).
# 【位置=场边】(规格"场边"): 触手不占 6 格 slot 网格、不挤真单位 — 站在己方那一侧的【屏幕边缘】(左队
#   左边缘 / 右队右边缘), 竖向中段错开排布. _slotKey 留空(非网格), 视图走 _build_tentacle_view 程序画.
# ════════════════════════════════════════════════════════════════

# 触手在场边的几何 (非 slot 网格): 离屏幕侧边 EDGE_INSET 像素, 竖向以画面中线为基准, 多个触手按 _edgeOrder 错开.
const TENTACLE_EDGE_INSET: float = 46.0     # 触手根部离屏幕侧边的像素 (己方一侧边缘, 不占阵地)
const TENTACLE_EDGE_GAP: float = 150.0      # 1/2 个触手竖向错开间距
const TENTACLE_HIT_BAND: float = 78.0       # "沿途"判定: 敌中心到拍击线段的垂直距离阈值 (穿过即命中)

## 触手根部世界坐标 (场边): 左队→屏幕左边缘内 INSET, 右队→右边缘内 INSET; 竖向中线 ± 按 order 错开.
func _tentacle_base_pos(side: String, order: int, total: int) -> Vector2:
	var x: float = TENTACLE_EDGE_INSET if side == "left" else (float(VIEW_W) - TENTACLE_EDGE_INSET)
	# 竖向: 以画面中线为中心, total 个触手均匀错开 (1 个居中, 2 个上下分)
	var span: float = TENTACLE_EDGE_GAP * float(maxi(0, total - 1))
	var y: float = (float(VIEW_H) * 0.52) - span * 0.5 + TENTACLE_EDGE_GAP * float(order)
	return Vector2(x, y)


## 战斗开始(_build_teams 内, _build_slot_views 之前): 某侧灵物激活 → 登场 count 个【场边】无敌触手.
##   ⚠ 只 fighters.append (不 _spawn_combatant) — 视图由后续 _build_slot_views 统一建 (镜 _spawn_crystal_balls),
##   否则会双建视图 + slot_nodes/fighters 索引错位. 触手【不占 slot 格】(_slotKey="", 不调 _find_summon_slot),
##   记 dmg_mult + _edgeOrder/_edgeTotal 供 _build_tentacle_view 摆到场边.
func _spawn_tentacles(side: String, team: Array) -> void:
	var setup: Dictionary = Phase2Types.tentacle_setup(team)
	var count: int = int(setup.get("count", 0))
	if count <= 0:
		return
	var dmg_mult: float = float(setup.get("dmg_mult", 1.0))
	for i in range(count):
		var tent: Dictionary = {
			"id": "spirit_tentacle", "name": "触手", "emoji": "🐙", "rarity": "C", "side": side,
			"img": "", "sprite": null,
			"_level": 1, "_maxEnergy": 0, "_energy": 0,
			"maxHp": 1, "hp": 1, "shield": 0,
			"baseAtk": 0, "baseDef": 0, "baseMr": 0, "atk": 0, "def": 0, "mr": 0,
			"crit": 0.0, "armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
			"passive": null, "passiveUsedThisTurn": false, "skills": [], "_passiveSkills": [],
			"alive": true, "buffs": [], "tags": [],
			# 场边单位: 不占 6 格网格 → _slotKey 留空, _find_summon_slot 永远跳过它 (used[""] 无意义不阻塞真单位).
			"_position": "front", "_slotKey": "", "_statsDirty": false,
			"equipment": [],
			"_isSummon": true, "_untargetable": true, "_isTentacle": true,
			"_tentacleDmgMult": dmg_mult,
			"_edgeOrder": i, "_edgeTotal": count,
		}
		fighters.append(tent)


## 某侧回合末: 该侧每个触手朝一目标拍击【沿途敌人】(规格#553) + 消费本回合闪避追击次数.
func _process_tentacles(side: String) -> void:
	for i in range(fighters.size()):
		var tent: Dictionary = fighters[i]
		if str(tent.get("side", "")) != side or not tent.get("_isTentacle", false) or not tent.get("alive", false):
			continue
		var dmg_mult: float = float(tent.get("_tentacleDmgMult", 1.0))
		var chases: int = mini(3, int(tent.get("_tentacleDodgeChase", 0)))
		tent["_tentacleDodgeChase"] = 0
		await _tentacle_slap(i, dmg_mult, 1.0)
		for _c in range(chases):
			await _tentacle_slap(i, dmg_mult, 0.25)


## slot 视图世界中心 (home_pos + avatar 偏移, 与 _play_vfx_at_slot 同口径). 缺 avatar → 退回 home_pos 上方.
func _slot_center_world(idx: int) -> Vector2:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return Vector2.ZERO
	var node: Node2D = slot_nodes[idx]
	var home: Vector2 = node.get_meta("home_pos", node.position)
	var av = node.get_meta("avatar", null)
	return home + ((av as Node2D).position if av is Node2D else Vector2(0, -50))


## 单次触手拍击 (规格#553): 朝最前敌瞄准, 对【沿途敌人】= 触手根→目标 拍击线段穿过的每个活敌
##   (含目标自己) (4%maxHP+55)×dmg_mult×ratio 物理. "沿途"= 敌中心到该线段垂距 ≤ HIT_BAND 且投影落在线段范围内.
func _tentacle_slap(tent_idx: int, dmg_mult: float, ratio: float) -> void:
	if tent_idx < 0 or tent_idx >= fighters.size():
		return
	var tent: Dictionary = fighters[tent_idx]
	if not tent.get("alive", false):
		return
	var enemies: Array = _alive_enemies_of(tent).filter(func(e): return not e.get("_untargetable", false))
	if enemies.is_empty():
		return
	# 瞄准最前敌 (前排 + 列号最小) 当拍击落点
	var anchor: Dictionary = enemies[0]
	var best: float = 1.0e9
	for e in enemies:
		var fr: float = 0.0 if str(e.get("_slotKey", "")).begins_with("front") else 100.0
		var parts: PackedStringArray = str(e.get("_slotKey", "front-0")).split("-")
		var col: float = float(int(parts[parts.size() - 1])) if parts.size() > 1 and parts[parts.size() - 1].is_valid_int() else 0.0
		if fr + col < best:
			best = fr + col
			anchor = e
	var anchor_idx: int = fighters.find(anchor)
	# 拍击线段: 触手根 (场边) → 目标中心. "沿途敌人" = 这条线穿过的敌人.
	var origin: Vector2 = _slot_center_world(tent_idx)
	var aim: Vector2 = _slot_center_world(anchor_idx)
	var seg: Vector2 = aim - origin
	var seg_len: float = seg.length()
	var path: Array = []
	if seg_len < 0.5:
		path = [anchor]   # 退化 (重叠) → 只打目标
	else:
		var dir: Vector2 = seg / seg_len
		for e in enemies:
			if e == anchor:
				path.append(e)   # 目标本人恒命中
				continue
			var ei: int = fighters.find(e)
			var c: Vector2 = _slot_center_world(ei)
			var t: float = (c - origin).dot(dir)               # 沿拍击线的投影长度
			if t < -20.0 or t > seg_len + 36.0:
				continue   # 投影落在线段(略放宽到目标稍后)之外 → 不在拍击路径上
			var perp: float = absf((c - origin).dot(Vector2(-dir.y, dir.x)))   # 到线段的垂直距离
			if perp <= TENTACLE_HIT_BAND:
				path.append(e)   # 沿途: 拍击线扫过它
	# 视觉: 触手伸出拍向目标 (与伤害并行, 不阻塞结算节奏)
	_animate_tentacle_slap(tent_idx, aim)
	var died: Array = []
	for tgt in path:
		var raw: int = roundi(float(Phase2Types.tentacle_slap_damage(int(tgt.get("maxHp", 0)), dmg_mult)) * ratio)
		if raw <= 0:
			continue
		var r: Dictionary = Damage.apply_raw_damage(tgt, raw, "physical")
		var shown: int = int(r["hpLoss"]) + int(r["shieldAbs"])
		var ti: int = fighters.find(tgt)
		if ti >= 0:
			_spawn_float_text(ti, shown, "damage", "physical", false)
			_flash_hit(ti)
			_play_tentacle_impact(ti)
			battle_stats.record_damage(tent, tgt, shown, _stat_type("physical"))
			_refresh_slot(ti)
			if not tgt.get("alive", false):
				died.append(ti)
	_play_screen_shake(0.14, 7.0)
	await get_tree().create_timer(0.28).timeout
	for di in died:
		await _play_death(di)


## 触手拍击落点冲击 (沿途每个被打的敌人处): 紫色冲击环 + 通用砸击爆点, 显出"被触手拍中".
func _play_tentacle_impact(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[target_idx]):
		return
	_play_vfx_at_slot("basic-slam-impact", target_idx, 1.0)
	_play_aoe_ring(target_idx, Color(0.62, 0.40, 0.86, 0.55))   # 幽紫触手冲击环


## 触手挥击动画 (程序, 规格#553视觉): 根在场边的触手身 伸出 → 拍向目标点 → 缩回待机.
##   重画 Line2D points 做一条从根弯向目标的弧线 (whip), 到位后弹一下再回卷.
func _animate_tentacle_slap(tent_idx: int, aim_world: Vector2) -> void:
	if tent_idx < 0 or tent_idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[tent_idx]):
		return
	var node: Node2D = slot_nodes[tent_idx]
	var line = node.get_meta("tentacle_line", null)
	if not (line is Line2D):
		return
	var inward: float = float(node.get_meta("tentacle_inward", 1.0))
	# 目标点换到触手 root 局部坐标 (root 在场边).
	var aim_local: Vector2 = aim_world - node.position
	var idle: PackedVector2Array = _tentacle_idle_points(inward)
	# 伸出姿态: 5 点沿 根→目标 的弧线分布 (中段抬高一点显挥击弧).
	var reach := PackedVector2Array()
	var perp := Vector2(-1.0, 0.0) if absf(aim_local.x) < 1.0 else Vector2(aim_local.y, -aim_local.x).normalized()
	for k in range(5):
		var u: float = float(k) / 4.0
		var p: Vector2 = aim_local * u
		var arc: float = sin(u * PI) * 30.0   # 中段鼓起的挥击弧
		reach.append(p + perp * arc)
	var tip = node.get_meta("avatar", null)
	# 三段: 伸出(快)→ 拍击到位停顿 → 缩回待机. 用 tween_method 插值 Line2D.points.
	var tw := create_tween()
	# ① 伸出: 待机姿态 → 拍击弧线 (快, 带回弹手感)
	tw.tween_method(
		func(t: float): line.points = _lerp_points(idle, reach, t),
		0.0, 1.0, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	# ② 拍到位: 把梢端(avatar 占位)落到目标处 + 短暂停顿
	tw.tween_callback(func():
		if tip is Node2D: (tip as Node2D).position = reach[reach.size() - 1])
	tw.tween_interval(0.10)
	# ③ 缩回: 拍击弧线 → 待机姿态
	tw.tween_method(
		func(t: float): line.points = _lerp_points(reach, idle, t),
		0.0, 1.0, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if tip is Node2D and idle.size() > 0: (tip as Node2D).position = idle[idle.size() - 1])


## 逐点线性插值两条等长点列 (触手伸出/缩回插值用).
func _lerp_points(a: PackedVector2Array, b: PackedVector2Array, t: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = mini(a.size(), b.size())
	for k in range(n):
		out.append(a[k].lerp(b[k], t))
	return out


## 复活海螺 3★ 每回合分裂: 存活的会分裂小虫(_conchWormSplit)每回合在空位生成 1 只新虫.
##   新虫【不带】_conchWormSplit → 不再分裂 (防指数爆炸); 阵地满则本回合不裂. 每虫每回合(turn)至多裂 1 次.
func _split_conch_worms() -> void:
	for ci in range(fighters.size()):
		var cw: Dictionary = fighters[ci]
		if not cw.get("alive", false) or not cw.get("_isConchWorm", false) or not cw.get("_conchWormSplit", false):
			continue
		if int(cw.get("_conchSplitTurn", -1)) == turn:
			continue   # 本回合该虫已分裂
		var slot: String = _find_summon_slot(cw)
		if slot == "":
			continue   # 阵地满, 本回合不裂
		cw["_conchSplitTurn"] = turn
		var side: String = str(cw.get("side", "left"))
		var whp: int = maxi(1, int(cw.get("maxHp", 300)))
		var watk: int = int(cw.get("baseAtk", 40))
		var worm: Dictionary = {
			"id": "conch_worm", "name": "海螺小虫", "emoji": "🐛", "rarity": "C", "side": side,
			"img": "", "sprite": null,
			"_level": int(cw.get("_level", 1)),
			"_maxEnergy": 0, "_energy": 0,
			"maxHp": whp, "hp": whp, "shield": 0,
			"baseAtk": watk, "baseDef": 0, "baseMr": 0,
			"atk": watk, "def": 0, "mr": 0,
			"crit": 0.0,
			"armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
			"passive": null, "passiveUsedThisTurn": false,
			"skills": [{
				"name": "啃咬", "type": "physical", "hits": 1, "power": 0, "pierce": 0,
				"atkScale": 1.0, "cd": 0, "cdLeft": 0, "energyCost": 0,
				"icon": "🐛", "brief": "", "detail": "",
			}],
			"_passiveSkills": [],
			"alive": true, "buffs": [], "tags": [],
			"_position": "front" if slot.begins_with("front") else "back",
			"_slotKey": slot,
			"_statsDirty": false,
			"equipment": [],
			"_isSummon": true,
			"_isConchWorm": true,   # 是虫但【无 _conchWormSplit】→ 分裂出的不再分裂
		}
		var widx := _spawn_combatant(worm)
		if widx >= 0:
			var wnode: Node2D = slot_nodes[widx]
			var wav: Sprite2D = wnode.get_meta("avatar", null)
			if wav != null and is_instance_valid(wav):
				var whs: Vector2 = wav.get_meta("home_scale", wav.scale)
				wav.scale = whs * 0.3
				var wtw: Tween = wav.create_tween()
				wtw.tween_property(wav, "scale", whs * 1.12, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				wtw.tween_property(wav, "scale", whs, 0.12)
			_play_summon_burst(widx, Color(0.3, 0.79, 0.94))   # 033复活海螺3★分裂虫: 青色召唤光环 (需F5)
			_spawn_passive_text(widx, "🐛 分裂!")


## 召唤系装备满层 → 召唤大熊 + 销毁装备 (034玩偶 _p2_equips / phase1 e_doll _equipped_ids). 每侧回合末调.
##   有空位才召唤+销毁; 无空位保留装备继续攒.
func _consume_doll_summons(side: String) -> void:
	for f in fighters:
		if str(f.get("side", "")) != side or not f.get("alive", false):
			continue
		# 034 玩偶小熊 (二阶段): _p2DollReadyToSpawn → 召唤大熊, 成功则销毁该装备
		if f.get("_p2DollReadyToSpawn", false) and not f.get("_p2DollSpawned", false):
			if _spawn_big_bear(f) >= 0:
				f["_p2DollSpawned"] = true
				f["_p2DollReadyToSpawn"] = false
				# 销毁玩偶装备: 从 _p2_equips 移除 (装备销毁=不再每回合小熊攻)
				var p2arr: Array = f.get("_p2_equips", [])
				for i in range(p2arr.size() - 1, -1, -1):
					if p2arr[i] is Dictionary and str(p2arr[i].get("id", "")) == "p2eq_034":
						p2arr.remove_at(i)
		# phase1 e_doll: _equipDollReadyToSpawn → 召唤大熊, 成功则销毁该装备 (此前 BattleScene 从不消费此标记)
		if f.get("_equipDollReadyToSpawn", false) and not f.get("_equipDollSpawned", false):
			if _spawn_big_bear(f) >= 0:
				f["_equipDollSpawned"] = true
				f["_equipDollReadyToSpawn"] = false
				var eq_arr: Array = f.get("_equipped_ids", [])
				for i in range(eq_arr.size() - 1, -1, -1):
					if str(eq_arr[i]) == "e_doll":
						eq_arr.remove_at(i)


# ════════════════════════════════════════════════════════════════
# 训龟大师的口哨 (e_master_whistle) — 吹响召唤训龟大师, 登场 4 回合, 每回合随机放 1 种能力
#   1:1 PoC BattleScene.ts:6926-7177。训龟大师 = _untargetable(免伤/不可选/胜负排除) 占 1 空位。
# ════════════════════════════════════════════════════════════════

## 一侧真龟 (排除召唤物/中立/大师等非真龟实体, 给能力 4/5/7 选目标) — 1:1 PoC realTurtlesOnSide:6943
func _real_turtles_on_side(side: String) -> Array:
	var out: Array = []
	for f in fighters:
		if f.get("side", "") != side or not f.get("alive", false):
			continue
		if f.get("_isSummon", false) or f.get("_isNeutral", false) or f.get("_isMasterTrainer", false) \
				or f.get("_isPirateShip", false) or f.get("_isMech", false) or f.get("_isDummy", false) \
				or f.get("_isCandyBomb", false) or f.get("_isTentacle", false):
			continue
		out.append(f)
	return out


## 加 1 件装备进我方席 (满 10 → 全员 +10%HP 补偿, 装备遗失) — 1:1 PoC addToBench(left)
func _bench_add(eid: String) -> void:
	if bench_inventory.size() < 10:
		bench_inventory.append(eid)
		_rebuild_bench_rail()
	else:
		_bench_full_heal("left")


## chance 概率给我方席补 1 个口哨, 返回是否掉落 — 1:1 PoC maybeDropWhistle:7170
func _maybe_drop_whistle(chance: float) -> bool:
	if randf() >= chance:
		return false
	_bench_add("e_master_whistle")
	battle_log.append_text("[color=#ffd86b]📯 掉落: 训龟大师的口哨 (装备席「吹响」使用)[/color]\n")
	return true


## 掉落装备进我方席 (战利品); 5% 概率改掉口哨 — 1:1 PoC dropLootEquip:8230
func _drop_loot_equip() -> void:
	if _maybe_drop_whistle(0.05):
		return
	_bench_add(EquipmentRuntime.random_loot())


## 吹响口哨: 校验空位 → 消耗口哨 → 召唤训龟大师 (口哨只进我方席, 仅玩家可吹) — 1:1 PoC blowMasterWhistle:6963
func _blow_master_whistle(side: String) -> void:
	if side != "left":
		return
	if _find_summon_slot({"side": side}) == "":
		_show_center_banner("⚠ 己方场上无空位, 无法吹响", "", "#ff9090", 1.2)
		return
	var idx: int = _bench_idx_of("e_master_whistle")
	if idx < 0:
		return
	bench_inventory.remove_at(idx)
	_rebuild_bench_rail()
	_spawn_master_trainer(side)


## 召唤训龟大师 (占 1 空位, 4 回合, 不可选/不受伤/不造成伤害) — 1:1 PoC spawnMasterTrainer:7009
func _spawn_master_trainer(side: String) -> void:
	var slot: String = _find_summon_slot({"side": side})
	if slot == "":
		return
	var is_front: bool = slot.begins_with("front")
	var trainer: Dictionary = {
		"id": "master_trainer", "name": "训龟大师", "emoji": "📯", "rarity": "C", "side": side,
		"img": "", "sprite": null,
		"_level": 1, "_maxEnergy": 0, "_energy": 0,
		"maxHp": 100, "hp": 100, "shield": 0,
		"baseAtk": 0, "baseDef": 0, "baseMr": 0, "atk": 0, "def": 0, "mr": 0,
		"crit": 0.0, "armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
		"passive": null, "passiveUsedThisTurn": false, "skills": [], "_passiveSkills": [],
		"alive": true, "buffs": [], "tags": [],
		"_position": "front" if is_front else "back", "_slotKey": slot, "_statsDirty": false,
		"equipment": [],
		"_isSummon": true, "_untargetable": true, "_isMasterTrainer": true, "_masterTrainerTurns": 4,
	}
	var idx: int = _spawn_combatant(trainer)
	var node: Node2D = slot_nodes[idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	if av != null and is_instance_valid(av):
		var hs: Vector2 = av.get_meta("home_scale", av.scale)
		av.scale = hs * 0.3
		var tw: Tween = av.create_tween()
		tw.tween_property(av, "scale", hs * 1.12, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(av, "scale", hs, 0.12)
	_show_center_banner("📯 训龟大师登场!", "", "#ffd86b", 1.5)
	battle_log.append_text("[color=#ffd86b]📯 吹响口哨 — 训龟大师登场 4 回合[/color]\n")


## round-end: 本侧每个活着的训龟大师释放 1 能力, 倒计时, 到 0 离场 — 1:1 PoC processMasterTrainer:7042
func _process_master_trainer(side: String) -> void:
	for i in range(fighters.size()):
		var t: Dictionary = fighters[i]
		if not t.get("_isMasterTrainer", false) or not t.get("alive", false) or t.get("side", "") != side:
			continue
		await _fire_master_ability(i)
		t["_masterTrainerTurns"] = int(t.get("_masterTrainerTurns", 1)) - 1
		if int(t.get("_masterTrainerTurns", 0)) <= 0:
			battle_log.append_text("[color=#ffd86b]📯 训龟大师离场[/color]\n")
			t["alive"] = false
			t["hp"] = 0
			_despawn_unit(i)


## 轻量移除一个单位的视图 (召唤物/大师离场: 淡出, 不发死亡补偿币/不触发死亡被动, 区别于 _play_death)
func _despawn_unit(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size():
		return
	Audio.play_sfx("defeat", 0.5, 1.0, 0.06)
	var node: Node2D = slot_nodes[idx]
	var avatar: Sprite2D = node.get_meta("avatar", null)
	var hud_d = node.get_meta("hud", null)
	var shadow_d = node.get_meta("shadow", null)
	var fade := create_tween().set_parallel(true)
	if avatar != null and is_instance_valid(avatar):
		fade.tween_property(avatar, "modulate:a", 0.0, 0.4)
	if shadow_d != null and is_instance_valid(shadow_d):
		fade.tween_property(shadow_d, "modulate:a", 0.0, 0.4)
	if hud_d != null:
		fade.tween_property(hud_d, "modulate:a", 0.0, 0.4)


## 随机释放 7 能力之一 (能力 4/5/7 无真龟目标则不入选) — 1:1 PoC fireMasterAbility:7059
func _fire_master_ability(idx: int) -> void:
	var trainer: Dictionary = fighters[idx]
	var side: String = str(trainer.get("side", "left"))
	var reals: Array = _real_turtles_on_side(side)
	var candidates: Array = []
	for ab in [1, 2, 3, 4, 5, 6, 7]:
		if (ab == 4 or ab == 5 or ab == 7) and reals.is_empty():
			continue
		candidates.append(ab)
	if candidates.is_empty():
		return
	var pick: int = candidates[randi() % candidates.size()]
	match pick:
		1:
			await _master_chi_wave(idx)
		2:
			var cons_ids: Array = []
			for ceid in DataRegistry.equipment_by_id:
				if str(DataRegistry.equipment_by_id[ceid].get("category", "")) == "consumable":
					cons_ids.append(ceid)
			var cname := "消耗品"
			if not cons_ids.is_empty():
				var cid: String = str(cons_ids[randi() % cons_ids.size()])
				_bench_add(cid)
				cname = str(DataRegistry.equipment_by_id[cid].get("name", "消耗品"))
			GameState.battle_coins += 2   # 口哨仅玩家(左)吹 → 直进玩家钱包
			battle_log.append_text("[color=#ffd86b]📯 训龟大师: 赠 %s + 2 深海币[/color]\n" % cname)
		3:
			_drop_loot_equip()
			battle_log.append_text("[color=#ffd86b]📯 训龟大师: 赠 1 件装备[/color]\n")
		4:
			var t4: Dictionary = reals[0]
			for r in reals:
				if int(r.get("maxHp", 0)) > int(t4.get("maxHp", 0)):
					t4 = r
			t4["maxHp"] = int(t4.get("maxHp", 0)) + 50
			t4["hp"] = int(t4.get("hp", 0)) + 50
			t4["baseDef"] = int(t4.get("baseDef", 0)) + 5
			t4["def"] = t4["baseDef"]
			t4["baseMr"] = int(t4.get("baseMr", t4.get("baseDef", 0))) + 5
			t4["mr"] = t4["baseMr"]
			var ti4: int = fighters.find(t4)
			_refresh_slot(ti4)
			_spawn_passive_text(ti4, "+50❤ +5🛡", "#06d6a0")
			battle_log.append_text("[color=#06d6a0]📯 训龟大师: %s +50最大生命/+5护甲/+5魔抗[/color]\n" % str(t4.get("name", "?")))
		5:
			var t5: Dictionary = reals[0]
			for r in reals:
				if int(r.get("_dmgDealt", 0)) > int(t5.get("_dmgDealt", 0)):
					t5 = r
			t5["baseAtk"] = int(t5.get("baseAtk", 0)) + 15
			t5["atk"] = t5["baseAtk"]
			t5["armorPen"] = int(t5.get("armorPen", 0)) + 5
			t5["magicPen"] = int(t5.get("magicPen", 0)) + 5
			var ti5: int = fighters.find(t5)
			_refresh_slot(ti5)
			_spawn_passive_text(ti5, "+15⚔ +5穿", "#ffd86b")
			battle_log.append_text("[color=#ffd86b]📯 训龟大师: %s +15攻击/+5护甲穿透/+5魔法穿透[/color]\n" % str(t5.get("name", "?")))
		6:
			var team6: Array = []
			for f in fighters:
				if f.get("side", "") == side and f.get("alive", false) and not f.get("_isMasterTrainer", false):
					team6.append(f)
			if not team6.is_empty():
				var per: int = int(150.0 / team6.size())
				for f in team6:
					f["shield"] = int(f.get("shield", 0)) + per
					var ti6: int = fighters.find(f)
					_refresh_slot(ti6)
					_spawn_float_text(ti6, per, "shield")
				battle_log.append_text("[color=#48cae4]📯 训龟大师: 全场 %d 只均分 150 永久护盾 (各 +%d)[/color]\n" % [team6.size(), per])
		7:
			var t7: Dictionary = reals[randi() % reals.size()]
			var atk_b: int = roundi(float(t7.get("baseAtk", 0)) * 0.05)
			var def_b: int = roundi(float(t7.get("baseDef", 0)) * 0.05)
			var mr_b: int = roundi(float(t7.get("baseMr", t7.get("baseDef", 0))) * 0.05)
			var hp_b: int = roundi(float(t7.get("maxHp", 0)) * 0.05)
			t7["baseAtk"] = int(t7.get("baseAtk", 0)) + atk_b; t7["atk"] = t7["baseAtk"]
			t7["baseDef"] = int(t7.get("baseDef", 0)) + def_b; t7["def"] = t7["baseDef"]
			t7["baseMr"] = int(t7.get("baseMr", t7.get("baseDef", 0))) + mr_b; t7["mr"] = t7["baseMr"]
			t7["maxHp"] = int(t7.get("maxHp", 0)) + hp_b; t7["hp"] = int(t7.get("hp", 0)) + hp_b
			t7["_masterTempLevel"] = int(t7.get("_masterTempLevel", 0)) + 1
			var ti7: int = fighters.find(t7)
			_refresh_slot(ti7)
			_spawn_passive_text(ti7, "Lv+%d" % int(t7["_masterTempLevel"]), "#ffd86b")
			battle_log.append_text("[color=#ffd86b]📯 训龟大师: %s +1 临时等级[/color]\n" % str(t7.get("name", "?")))


## 能力 1: 灵体小龟龟派气波 — 随机一行敌人, 三段共 90 物理 (击飞=flavor) — 1:1 PoC masterChiWave:7138
func _master_chi_wave(idx: int) -> void:
	var trainer: Dictionary = fighters[idx]
	var side: String = str(trainer.get("side", "left"))
	var enemy_side: String = "right" if side == "left" else "left"
	var enemies: Array = []
	for f in fighters:
		if f.get("side", "") == enemy_side and f.get("alive", false) and not f.get("_untargetable", false):
			enemies.append(f)
	if enemies.is_empty():
		battle_log.append_text("[color=#ffd86b]📯 训龟大师: 龟派气波 (无敌人)[/color]\n")
		return
	var rows: Array = []
	for r in ["front", "back"]:
		for f in enemies:
			if str(f.get("_slotKey", "")).begins_with(r + "-"):
				rows.append(r)
				break
	var row: String = rows[randi() % rows.size()] if not rows.is_empty() else "front"
	var targets: Array = []
	for f in enemies:
		if str(f.get("_slotKey", "")).begins_with(row + "-"):
			targets.append(f)
	battle_log.append_text("[color=#ffd86b]📯 训龟大师: 灵体小龟龟派气波 → %s排 %d 敌 (三段共 90 物理, 击飞)[/color]\n" % ["前" if row == "front" else "后", targets.size()])
	for tgt in targets:
		var total: int = 0
		for _seg in range(3):
			if not tgt.get("alive", false):
				break
			var dmg: int = maxi(1, roundi(30.0 * Damage.calc_dmg_mult(Damage.calc_eff_armor(trainer, tgt))))
			var r: Dictionary = Damage.apply_raw_damage(tgt, dmg, "physical")
			total += int(r.get("hpLoss", 0)) + int(r.get("shieldAbs", 0))
		var ti: int = fighters.find(tgt)
		if total > 0:
			battle_stats.record_damage(trainer, tgt, total, "phy")
			_spawn_float_text(ti, total, "damage", "physical", false)
			_refresh_slot(ti)
		if not tgt.get("alive", false):
			battle_stats.record_kill(trainer, tgt)
			await _play_death(ti)


## 把败方龟蛋作为【真 fighter 单位】推进战场 (front-1 槽). 进 fighters[]/有 slot 视图/正常被技能打.
##   - hp/maxHp = GameState.egg_hp[side]/egg_hp_max[side] (跨上/下/终极累计, 别破坏)
##   - def=0 mr=0 atk=0 不行动; _isEgg + _eggImmune (免处决/控制/嘲讽, 各判定点守卫读 _eggImmune)
##   - 终极战场 (current_lane=="final"): 挂 markedDmg=400 buff → 受伤 ×5; 设 _eggSelfLoss → 每回合自损25%maxHP
## 返回新蛋的 fighters[] 索引 (-1 = 没 spawn, e.g. 蛋已死/已登场).
## 远古遗迹: 本侧龟蛋 maxHp 加成 (+500/750/1500 按档位; 0=未激活)。
func _ancient_egg_bonus(side: String) -> int:
	var team: Array = []
	for f in fighters:
		if str(f.get("side", "")) == side and not f.get("_isEgg", false):
			team.append(f)
	for a in Phase2Schools.calc_active(team):
		if str(a.get("school", "")) == "远古遗迹":
			return [500, 750, 1500][clampi(int(a.get("tier", 1)) - 1, 0, 2)]
	return 0


func _spawn_egg_fighter(side: String) -> int:
	if _egg_spawned(side) or not GameState.egg_alive(side):
		return -1
	var ehp: int = maxi(1, int(GameState.egg_hp.get(side, 0)))
	var emax: int = maxi(ehp, int(GameState.egg_hp_max.get(side, ehp)))
	# 远古遗迹: 龟蛋 +500/750/1500 maxHp (大器晚成流的蛋肉盾)。存 _ancientEggBonus 让升级 resync 不丢。
	var anc_egg: int = _ancient_egg_bonus(side)
	if anc_egg > 0:
		emax += anc_egg
		ehp += anc_egg
	var is_final: bool = GameState.mode == "duallane" and GameState.current_lane == "final"
	var egg: Dictionary = {
		"id": "egg",
		"name": "龟蛋基地" if side == "left" else "敌方龟蛋",
		"emoji": "🥚",
		"rarity": "C",
		"side": side,
		"img": "pets/egg.png",   # 龟蛋待机动画 (用户配) 237×80, 3帧 79×80
		"sprite": {"frames": 3, "frameW": 79, "frameH": 80, "duration": 900},   # _make_slot_view → 3帧 idle 循环 (300ms/帧)
		"_level": 1,
		"_maxEnergy": 0, "_energy": 0,
		"maxHp": emax, "hp": ehp, "shield": 0,
		"baseAtk": 0, "baseDef": 0, "baseMr": 0,
		"atk": 0, "def": 0, "mr": 0,    # 用户定: def=0 mr=0 纯血包
		"crit": 0.0,
		"armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
		"passive": null, "passiveUsedThisTurn": false,
		"skills": [], "_passiveSkills": [],
		"alive": true, "buffs": [], "tags": [],
		"_position": "front", "_slotKey": EGG_SLOT,
		"_statsDirty": false,
		"equipment": [],
		"_isEgg": true,        # 不行动 / 不进幸存者快照 / 攻蛋累计归对面 / 不吃永恒buff
		"_eggImmune": true,    # 免处决(斩杀)/控制(眩晕·冻结·击飞)/嘲讽 — 各判定点守卫读此 flag
		"_eggSpawnTurn": turn, # 登场回合 (上/下路: 蛋登场后只给 EGG_ATTACK_ROUNDS 回合攻蛋, 之后本路结束; 终极=凿穿为止)
	}
	if is_final:
		# 终极战场: ×5 增伤用 markedDmg buff 实现 (value=400 → 受伤×(1+400%)=×5); 自损用 _eggSelfLoss flag.
		#   markedDmg 是已有"受伤+value%"机制 (damage.gd:162), 复用; 配置常量 Phase2Config.FINAL_LOSER_EGG_DMG_MULT.
		var marked_val: int = int(round((Phase2Config.FINAL_LOSER_EGG_DMG_MULT - 1.0) * 100.0))
		Buffs.add(egg, "markedDmg", marked_val, 999, "overwrite")
		egg["_eggSelfLoss"] = true
	egg["_ancientEggBonus"] = anc_egg   # 远古蛋HP加成 (resync 重应用用)
	var idx := _spawn_combatant(egg)
	# 登场弹跳 + 横幅 (演出, headless 跳过停顿)
	var node: Node2D = slot_nodes[idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	if av != null and is_instance_valid(av):
		var hs: Vector2 = av.get_meta("home_scale", av.scale)
		av.scale = hs * 0.2
		var tw: Tween = av.create_tween()
		tw.tween_property(av, "scale", hs * 1.15, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(av, "scale", hs, 0.12)
	var who := "我方" if side == "left" else "敌方"
	_show_center_banner("龟蛋登场!" + (" ×5" if is_final else ""), who + " 龟蛋暴露" + ("(增伤×5·每回合自损25%)" if is_final else ""), "#ff6b6b", 1.2)
	battle_log.append_text("\n[color=#ff6b6b][b]🥚 %s 龟蛋登场! (HP %d/%d%s)[/b][/color]\n" % [who, ehp, emax, " ·终极×5+自损" if is_final else ""])
	if OS.has_environment("DUALLANE_SMOKE"):
		print("[SMOKE] 🥚蛋登场%s side=%s HP=%d/%d" % [" 终极×5" if is_final else "", side, ehp, emax])
	return idx


## 终极战场 蛋每回合自损 25% maxHP (round-begin 调; _eggSelfLoss flag 标的蛋才扣).
##   走真实扣血管线 (apply_raw_damage true 真伤) → 命中动画 + 飘字 + 摧毁判定一致.
func _egg_self_loss_tick() -> void:
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		if not f.get("_isEgg", false) or not f.get("_eggSelfLoss", false) or not f.get("alive", false):
			continue
		var sl: int = Phase2Config.egg_self_loss(int(f.get("maxHp", 0)))
		if sl <= 0:
			continue
		var r: Dictionary = Damage.apply_raw_damage(f, sl, "true")
		var shown: int = int(r.get("hpLoss", 0)) + int(r.get("shieldAbs", 0))
		_sync_egg_hp(f)
		if shown > 0:
			_spawn_float_text(i, shown, "damage", "true", false)
		_play_egg_hit(i)
		_refresh_slot(i)
		if not f.get("alive", false):
			await _play_egg_destroy(i)


## 蛋受击/自损时把蛋 fighter 的 hp 写回 GameState.egg_hp[side] (跨上/下/终极累计的权威账本).
func _sync_egg_hp(egg: Dictionary) -> void:
	if not egg.get("_isEgg", false):
		return
	var side := str(egg.get("side", ""))
	if side == "left" or side == "right":
		GameState.egg_hp[side] = maxi(0, int(egg.get("hp", 0)))


## 蛋被打中的命中演出: 震动 + 短暂裂纹色闪 (1:1 风格于普通受击, 但蛋是静物 → 抖更明显).
##   动画逻辑实现; headless 验不了视觉, 需 F5 眼验抖动/色闪幅度.
func _play_egg_hit(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var node: Node2D = slot_nodes[idx]
	var av: Sprite2D = node.get_meta("avatar", null)
	if av == null or not is_instance_valid(av):
		return
	var home: Vector2 = av.get_meta("home", av.position)
	var tw: Tween = av.create_tween()
	tw.tween_property(av, "position:x", home.x + 7.0, 0.04)
	tw.tween_property(av, "position:x", home.x - 7.0, 0.04)
	tw.tween_property(av, "position:x", home.x + 4.0, 0.04)
	tw.tween_property(av, "position:x", home.x, 0.04)
	# 裂纹色闪 (白→红→还原), 表现"蛋壳受创"
	var ct: Tween = av.create_tween()
	ct.tween_property(av, "modulate", Color(1.6, 1.0, 1.0, av.modulate.a), 0.05)
	ct.tween_property(av, "modulate", Color(1, 1, 1, av.modulate.a), 0.12)


## 蛋血归零的摧毁演出: 放大碎裂 + 淡出 + 摧毁横幅 (蛋=基地, 摧毁=该方判负).
##   动画逻辑实现; headless 验不了视觉, 需 F5 眼验碎裂/横幅.
func _play_egg_destroy(idx: int) -> void:
	if idx < 0 or idx >= slot_nodes.size() or not is_instance_valid(slot_nodes[idx]):
		return
	var node: Node2D = slot_nodes[idx]
	var f: Dictionary = fighters[idx] if idx < fighters.size() else {}
	var who := "我方" if str(f.get("side", "")) == "left" else "敌方"
	_play_hit_stop(140)
	var av: Sprite2D = node.get_meta("avatar", null)
	if av != null and is_instance_valid(av):
		var hs: Vector2 = av.get_meta("home_scale", av.scale)
		var tw: Tween = av.create_tween()
		tw.tween_property(av, "scale", hs * 1.4, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(av, "rotation", deg_to_rad(12.0), 0.12)
		tw.tween_property(av, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD)
	var hud_d = node.get_meta("hud", null)
	if hud_d != null and is_instance_valid(hud_d):
		var ft: Tween = create_tween()
		ft.tween_property(hud_d, "modulate:a", 0.0, 0.42)
	_show_center_banner("龟蛋摧毁!", who + " 龟蛋被击碎", "#ffd93d", 1.3)
	battle_log.append_text("[color=#ffd93d][b]💥 %s 龟蛋被击碎![/b][/color]\n" % who)
	if not auto_play_debug:
		await get_tree().create_timer(0.9).timeout


func _show_result(tie: bool = false) -> void:
	if _result_shown:   # 多入口(_check_end 6处)守卫: 只切一次场景
		return
	_result_shown = true
	# 二阶段双路: 龟蛋已作为真单位正常挨打 (登场→3回合凿蛋/终极凿穿; hp 实时写回 egg_hp 跨场累计) →
	#   快照幸存者(待命回复30%) → 回大地图(枢纽). 终极: current_lane=="final" 蛋凿穿; 上下路: 记录路胜负.
	#   (取代旧 _egg_attack_phase 假阶段; 蛋摧毁演出/账本扣血都在战斗主循环里随单位死亡发生过了.)
	if GameState.mode == "duallane":
		var dl_loser := _wiped_side()
		var is_terminal: bool = GameState.current_lane == "final"
		if is_terminal:
			GameState.current_lane = "done"
		else:
			GameState.snapshot_lane_survivors(fighters)   # 存活带血进终极(已回复30%已损)
			var lane_winner: String
			if dl_loser != "":
				lane_winner = "left" if dl_loser == "right" else "right"
			else:
				# 双方都团灭(真平局) → 按蛋血多的判赢, 平则归玩家 (原双方0存活恒判右=偏袒敌方)
				lane_winner = "left" if int(GameState.egg_hp.get("left", 0)) >= int(GameState.egg_hp.get("right", 0)) else "right"
			GameState.record_lane_result(lane_winner)
		_hide_action_panel()
		if is_instance_valid(_battle_shop_layer):
			_battle_shop_layer.visible = false   # 结算隐藏整备商店条 (否则 layer40 盖住"龟蛋摧毁"横幅+1s转场)
		Audio.stop_bgm(0.9)
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://scenes/DualLaneMap.tscn")
		return

	var left_alive: int = 0
	var right_alive: int = 0
	for f in fighters:
		if not _is_combatant(f):
			continue
		if f["side"] == "left":
			left_alive += 1
		else:
			right_alive += 1
	var player_won := left_alive > 0 and not tie

	# 闯关 HP 快照 + 装备席跨关 (必须在离开 BattleScene 前, 读 fighters)
	if player_won and GameState.mode == "dungeon":
		GameState.snapshot_left_hp(fighters)
		# 只跨关装备 id (单体 buff 是战内消耗品, buff 数据不序列化 → 不跨关, 避免下关孤儿 id)
		var carry: Array = []
		for bid in bench_inventory:
			if not _bench_buff_items.has(bid):
				carry.append(bid)
		GameState.dungeon_carry_bench = carry   # 装备席库存跨关 (1:1 PoC benchInventoryIds)

	# 收集左队 playerStats (供结算表) + total_dmg (龟币公式)
	var player_stats: Array = []
	var player_lineup: Array = []   # 实际上阵玩家阵容 id (战绩头像用; 比 GameState.left_team 可靠, 覆盖默认/教程/野生场 has_team()=false 时)
	var total_dmg: int = 0
	for f in fighters:
		if f.get("side", "") != "left" or f.get("_isSummon", false) or f.get("_isNeutral", false):
			continue
		player_lineup.append(str(f.get("id", "")))
		var s: Dictionary = battle_stats.for_fighter(f)
		total_dmg += int(s.get("dmgDealt", 0))
		player_stats.append({
			"name": f.get("name", "?"), "rarity": f.get("rarity", "C"),
			"alive": f.get("alive", false), "hp": int(f.get("hp", 0)), "maxHp": int(f.get("maxHp", 0)),
			"dmgDealt": int(s.get("dmgDealt", 0)), "dmgTaken": int(s.get("dmgTaken", 0)),
			"healDone": int(s.get("healDone", 0)), "kills": int(s.get("kills", 0)), "crits": int(s.get("crits", 0)),
		})

	# 存结果 → BattleEndScene 读取
	GameState.last_battle_result = {
		"result": "tie" if tie else ("win" if player_won else "lose"),
		"player_won": player_won, "tie": tie,
		"turn": turn, "mode": GameState.mode,
		"dungeon_stage": GameState.dungeon_stage,
		"is_boss": GameState.mode == "dungeon" and GameState.is_dungeon_boss_stage(),
		"left_alive": left_alive, "right_alive": right_alive,
		"player_stats": player_stats, "total_dmg": total_dmg,
		"lineup": player_lineup,
		"rule": rule, "crits": _battle_crits,
	}
	# 1:1 PoC endBattle(BattleScene.ts:8650-8698): 隐操作面板 + BGM 600ms 淡出 + 等 600ms 再切场景
	#   (给最后一击的技能/死亡/飘字演出一个收尾停顿; 原 Godot 立即切=演出被砍, "感觉压根没对过")
	_hide_action_panel()
	Audio.stop_bgm(0.9)
	# 最后一击的技能VFX/弹道是 fire-and-forget(_play_skill_vfx 不 await), 400ms TURN_DELAY+0.6s 不够长技能 →
	#   出手出到一半就切场景(用户报). 收尾停顿拉到 1.3s 让弹道/死亡演出基本播完再切.
	await get_tree().create_timer(1.3).timeout
	get_tree().change_scene_to_file("res://scenes/BattleEnd.tscn")


## 局内伤害统计: 战斗结束在日志列每龟 造成/承受/治疗/护盾/击杀 (按造成降序). PoC DmgStatsPanel 的文本版.
## (完整 tabbed Control 面板留待 UI 批次; 数据层 battleStats 已全埋点)
func _log_battle_stats() -> void:
	battle_log.append_text("\n[color=#ffd166][b]== 伤害统计 ==[/b][/color]\n")
	for side_key in ["left", "right"]:
		var rows: Array = []
		for s in battle_stats.by_side(side_key):
			if s.get("isNeutral", false):
				continue
			rows.append(s)
		rows.sort_custom(func(a, b): return int(a.get("dmgDealt", 0)) > int(b.get("dmgDealt", 0)))
		var side_color := "#9af6ff" if side_key == "left" else "#ff9ec4"
		var side_name := "左队" if side_key == "left" else "右队"
		battle_log.append_text("[color=%s][b]%s[/b][/color]\n" % [side_color, side_name])
		for s in rows:
			var alive: bool = (s.get("_fighter", {}) as Dictionary).get("alive", false)
			var tag := "" if alive else " [color=#888](阵亡)[/color]"
			battle_log.append_text("  %s%s — [color=#ff8c8c]造成 %d[/color] · 承受 %d · [color=#3cd97a]治疗 %d[/color] · [color=#5cb8ff]盾 %d[/color] · KO%d\n" % [
				s.get("name", "?"), tag,
				int(s.get("dmgDealt", 0)), int(s.get("dmgTaken", 0)),
				int(s.get("healDone", 0)), int(s.get("shieldGained", 0)), int(s.get("kills", 0)),
			])
