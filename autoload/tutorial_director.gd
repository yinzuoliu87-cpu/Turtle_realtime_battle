extends Node
## TutorialDirector — 新手教程的跨场景导演。Autoload 单例。
##
## ══════════════════════════════════════════════════════════════════════
##  2026-10-07 重做(方案书 docs/plans/20261007-新手教程重做.md)
## ══════════════════════════════════════════════════════════════════════
## 用户原话(逐字钉住):
##   「教程里的商店怎么能够和账号的商店互通呢，你懂什么叫教程吗，整个教程都不应该有当前存档的东西啊」
##   「缩」(一把战斗、删图鉴站) /「打三路」/「是点击啊」
##   「教程里就不应该有返回键啊，要一直跟着教程走啊」
##
## ★v5(2026-10-21, 分镜 docs/plans/20261021-教程分镜v5.md): 开始教程 ⇒ **选龟屏**(教程固定池 3 只依次发光, 选第一只后
##   教 3 选 1 技能, 「出战」前讲阵容锁到下周一) ⇒ 战斗(6 句不阻塞提示, 各挂在一个战斗事件上, 事件没发生就不出)
##   ⇒ 结算 ⇒ 商店(先讲 1 级不能装备, 再买经验) ⇒ 背包(装上 → 合成 → 站位 → 完成教程)。
##   合成那一步靠**教程开局配置**: 沙盒背包预放 2 件 TUT_MERGE_ITEM, 商店货架第 1 格就是它 ⇒ 买下凑满 3 件自动合成(规则不变)。
## 流程(v4, 2026-10-21 方案书 docs/plans/20261020-教程重写.md §v4; v3 见同篇 §1):
##   首启流程(介绍 → 选择框, scripts/scenes/FirstLaunchScene.gd) →(开始教程)→ **直接进战斗**(阵容预配 FIXED_TEAM,
##   不再经过选龟屏: 实机参考同类第一战前最多一个动作) → 战斗(三路; 开打后两句不阻塞提示) → 结算
##   → 商店(买经验升 2 级 → 点一件装备 → 点购买 → 点背包)
##   → 背包(点装备 → 点龟装上 → 点站位 → 拖一只龟 → 点完成 → 完成教程) → 起名(首启那一屏) → 主菜单。
##   首启点「跳过」(或教程中途「跳过教程」): 起名 → 主菜单。起名只在「第一次走首启」且没起过名时出现。
##
## ★★教程 = 完全隔离的沙盒(`enter()` / `end_tutorial()`):
##   进教程时把 GameState 的**全部**脚本变量深拷贝进内存(不挑字段), 再把 GameState 换成一份
##   **全新**的状态(= 新建一个 GameState 实例读出的默认值) + 教学币 —— 与账号存档无关。
##   教程期间 `GameState.save()` 一律不写盘(`tutorial_active` 闸, 见 GameState.save)。
##   结束(完成 / 跳过 / 中途离开)把那份拷贝原样换回, 只写上「看过教程」这几个标记再存档。
##   ⇒ 进程在教程中被杀: 账号存档从没被写过, 下次启动 `onboarded=false` ⇒ 再弹选择框。
##   (原做法「快照几个字段 → 在真存档上教 → 结束还原」漏一个字段就污染, X4 就是这么来的。)

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const TEAM_SELECT := "res://scenes/TeamSelect.tscn"
const FIRST_LAUNCH := "res://scenes/FirstLaunch.tscn"
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const SHOP := "res://scenes/Shop.tscn"
const INVENTORY := "res://scenes/Inventory.tscn"

## 教学固定阵容(用户 2026-07-23 拍板: 固定阵容 + 弱对手必赢)。v5: 选龟屏的教程固定池 = 这 3 只(选龟屏只显示这 3 只,
##   见 team_select/pet_grid.gd), 按候选格里的先后依次发光。顺序不动: 教学战斗按它取左队(RealtimeBattle3DScene._resolve_left)。
const FIXED_TEAM := ["basic", "stone", "bamboo"]
## 弱对手阵容(必赢)。
const WEAK_FOE := ["basic"]
## 教学沙盒里的深海币: 买一次经验(4) 升到 2 级 + 买一件低费装备。沙盒丢弃时一起丢弃。
const TUT_COINS := 20
## ★v5 合成那一步(分镜 F3)的教程开局配置: 沙盒背包预放 2 件 1 星, 商店货架第 1 格是同一件 ⇒ 买下 = 3 件同名同星 ⇒ 正式规则自动合成。
##   1 费(教学币 20 − 买经验 4 = 16 买得起), 会升星(不在 EquipPool.NO_STAR)。
const TUT_MERGE_ITEM := "p2eq_001"
const TUT_MERGE_PRESET := 2

## ★教程加成(用户 2026-10-20「你可以在新手教程里给我方单位50%增伤和30减伤啊，最为教程模式的特殊机制啊」):
##   教学战斗里我方所有单位 增伤 / 减伤, 明示在战斗里(「教程加成」签 + 详情状态)。施加与显示见
##   scripts/systems/onboarding/tutorial_buff.gd。对局规则(对手、补小将、分路结算)一律不变。
const TUTORIAL_DMG_AMP := 0.5
const TUTORIAL_DR := 0.3

## ★沙盒不碰的键 —— 「你是谁」「这台设备」, 不是「这局游戏」。
##   教程期间它们照常活着(例: 首启时异步登录拿到 account_id), 结束时**保留现值**, 不被拷贝盖回去。
##   其余所有脚本变量一律进沙盒(进时换成全新值, 出时换回原值)。
const PASSTHROUGH := ["install_uid", "account_id", "account_email", "auth_refresh", "cloud_rev",
	"nickname", "nickname_default", "bgm_volume", "sfx_volume", "fullscreen",
	"replay_upload_pending", "ghost_upload_pending", "test_mode", "skill_text_detail", "onboarded",
	"tutorial", "tutorial_active", "tutorial_stage"]
## 全新状态里沿用账号的「赛程时钟」: 否则选龟屏/结算按周相位判断时会把沙盒当成另一周。
const CLOCK_KEYS := ["season_id", "season_start_ts", "week_anchor_ts", "week_phase"]

## 进教程前的账号状态(全部脚本变量)。★为空 = 不在沙盒里。
var _sandbox: Dictionary = {}
## 教程期间云端拉回来的存档(要落到账号上, 不是落到沙盒上) —— 结束时再应用。
var _pending_cloud: Array = []
## 最近一次 `end_tutorial` 的理由(completed / skipped / abandoned)。只给日志与门禁区分, 不影响状态。
var last_end_reason: String = ""
## 回到主菜单后要飘的那一句(只有走完才有: 「教程完成」)。主菜单 _ready 读完即清。
var pending_toast: String = ""
## 首启那一屏下次 `_ready` 时进哪种模式("name" = 直接起名)。那一屏读完即清。
var first_launch_mode: String = ""

## ★★旧版残留文件(v0.19.559 及更早, 进沙盒时把真币/背包/统领落盘一份)。
##   新版**不再写**它; 只在启动时把旧版留下的那份还回去, 免得老测试机上的真币永远丢在里面。
const SANDBOX_RESIDUE := "user://tutorial_sandbox.dat"
var _residue_path: String = SANDBOX_RESIDUE

## 看门狗: 上一次观测到的当前场景路径 / 进沙盒后是否真的离开过主菜单。
var _last_scene_path: String = ""
var _sandbox_left_menu: bool = false
## 本场景实例已挂过教程外壳(跳过钮 + 吞返回键)。
var _chrome_scene_id: int = 0
## 当前这一屏的引导条(TutorialGuide)。`notify()` 转给它 —— 各屏不必自己留引用。
var _guide: Node = null
## 教学战斗里的不阻塞提示(v5 C1~C6)。与 `_guide` 分开: 结算引导挂上来时它要先收掉。
##   `_battle_tips` = 此刻挂着的那一句(一次只挂一句); 其余排队。每句挂在一个战斗事件(`trigger`)上, 事件第一次发生才排进队。
var _battle_tips: Node = null
var _battle_tips_scene_id: int = 0
var _btips_bt: Node = null
var _btips_steps: Array = []
var _btips_fired: Dictionary = {}     # 步骤下标 → true(已排过队)
var _btips_queue: Array = []          # 待显示的步骤(已填好字)
var _btips_ctx: Dictionary = {}       # trigger → 触发它的单位(锚点要用)
var _btips_cur_ctx: Dictionary = {}   # 此刻那一句的单位
var _btips_wait: float = 0.0          # 此刻那一句从挂上到第一次显示等了多久(游戏没给机会显示就丢掉, 不卡后面的)
var _btips_cur_shown: bool = false
var _btips_log: Array = []            # 显示过的步骤 _id(门禁 / 录屏读)
var _btips_cur_step: Dictionary = {}  # 此刻那一句的步骤
## ★首场正式对战模式(不在沙盒里, FirstTips 的 FIRST_LANES / FIRST_EGG / FIRST_FINAL): 同一套事件队列, 只挂还没看过的那几句,
##   真显示出来那一刻记成看过。为假 = 教程模式(或什么都没挂)。
var _btips_first: bool = false
## 教程战斗里真显示过的步骤 _id(→ true)。教程结束时把其中属于 FirstTips.BATTLE_TIP_KEYS 的记成看过。
var _btips_tut_shown: Dictionary = {}
## 一句挂上后这么久还没机会显示(锚点那只龟死了 / 战场换了)⇒ 丢掉, 让后面的上。
const TIP_STALE_SEC := 8.0


func _ready() -> void:
	call_deferred("restore_residue_if_any")


## ★★看门狗 + 外壳。**任何**离开教程的方式最后都落在主菜单 ⇒ 在一个地方收口:
##   进沙盒之后走出过主菜单、又回到主菜单 ⇒ `end_tutorial("abandoned")`。
##   (教程里已经没有返回入口了; 这条是给下一个人新写一条退出路径时兜底的。)
func _process(_dt: float) -> void:
	if _sandbox.is_empty():
		_tick_first_battle(_dt)
		return
	var tr := get_tree()
	var cs: Node = tr.current_scene if tr != null else null
	var now: String = str(cs.scene_file_path) if cs != null else ""
	if cs != null and cs.get_instance_id() != _chrome_scene_id and now != MAIN_MENU and now != "":
		_chrome_scene_id = cs.get_instance_id()
		_attach_chrome(cs)
	if cs != null and now == BATTLE and cs.get_instance_id() != _battle_tips_scene_id:
		_battle_tips_scene_id = cs.get_instance_id()
		_attach_battle_tips(cs)
	if _btips_bt != null:
		_tick_battle_tips(_dt)
	## ★空路径不记也不判 —— 换场那一瞬间 current_scene 是 null(2026-09-29 实测踩过)。
	if now == "" or now == _last_scene_path:
		return
	_last_scene_path = now
	if now != MAIN_MENU:
		_sandbox_left_menu = true
		return
	if _sandbox_left_menu:
		end_tutorial("abandoned")


func _notification(what: int) -> void:
	## 桌面关窗: 账号存档从没被写过 ⇒ 只把内存换回去(不落盘, 也不置 onboarded —— 下次启动再问一次)。
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _sandbox.is_empty():
		_restore_account()
		GameState.tutorial_active = false
		GameState.tutorial = false
		GameState.tutorial_stage = ""


func is_active() -> bool:
	return GameState != null and bool(GameState.get("tutorial_active"))


## 沙盒在不在(= 是否正隔离着账号状态)。
func in_sandbox() -> bool:
	return not _sandbox.is_empty()


func stage() -> String:
	return str(GameState.get("tutorial_stage")) if GameState != null else ""


# ═══════════════════════════════ 进 / 出 ═══════════════════════════════

## 开始教程: 隔离账号状态 → 全新教学状态 + 教程开局配置 → 选龟屏。`host` 用来换场景(首启那一屏 / 主菜单「?」)。
## ★v5(2026-10-21 分镜 B): 又经过选龟屏了 —— 分镜「第一个决定就是选龟」「锁定是后果最大的规则, 必须在按下前说」。
##   (v4 曾直接进战斗、阵容预配; 那一版的 preset_team 留着给门禁 / 模拟直接武装战斗用。)
##   阵容由选龟屏「出战」那一下写(TeamSelectScene._on_start 教程分支) ⇒ next_scene_after("team_select") 武装教学战斗。
func enter(host: Node) -> void:
	if GameState == null:
		return
	restore_residue_if_any()
	if _sandbox.is_empty():
		_sandbox = _snapshot_account()
		_reset_to_fresh()
	_sandbox_left_menu = false
	_last_scene_path = ""
	_chrome_scene_id = 0
	last_end_reason = ""
	GameState.tutorial = true
	GameState.tutorial_active = true
	GameState.dual_active = true
	GameState.meta_deepsea_coins = TUT_COINS
	preset_merge_bench()
	GameState.tutorial_stage = "team_select"
	if host != null and host.is_inside_tree():
		SceneNav.go(host.get_tree(), TEAM_SELECT)


## 教程开局配置(分镜 F3): 沙盒背包里预放 TUT_MERGE_PRESET 件 TUT_MERGE_ITEM(1 星)。★只在沙盒里(进教程时已换成全新状态)。
##   张数照正式规则从私人池里扣(商店成交也扣), 池账与「手里有几件」一致。★幂等: 已经放过就不再放。
func preset_merge_bench() -> void:
	var have := 0
	for it in GameState.persistent_bench:
		if it is Dictionary and str((it as Dictionary).get("id", "")) == TUT_MERGE_ITEM:
			have += 1
	if have >= TUT_MERGE_PRESET:
		return
	GameState.ensure_equip_pool()
	for _i in range(TUT_MERGE_PRESET - have):
		GameState.pool_take(TUT_MERGE_ITEM, 1)
		GameState.persistent_bench.append({"id": TUT_MERGE_ITEM, "star": 1})


## 教程商店的货架(分镜 E3「货架上 1 件发光」): 第 1 格 = TUT_MERGE_ITEM, 其余 9 格按数据顺序取其它 1 费件(不含不升星的)。
##   写成「本场次的货架」(meta_shop_battles = 当前场次) ⇒ 商店 `_restore_offer` 原样恢复, 不掷货。
func preset_shop_offer() -> void:
	var out: Array = [{"id": TUT_MERGE_ITEM}]
	for e in DataRegistry.phase2_equipment:
		if out.size() >= 10:
			break
		var eid := str((e as Dictionary).get("id", ""))
		if eid == TUT_MERGE_ITEM or eid == "p2eq_096" or int((e as Dictionary).get("cost", 0)) != 1:
			continue
		out.append({"id": eid})
	GameState.meta_shop_offer = out
	GameState.meta_shop_battles = int(GameState.season_total_battles)
	GameState.meta_shop_locked = false


## 教学阵容(沙盒里): 与选龟屏「出战」写的同三项。v5 起正式流程由选龟屏写; 这里留给门禁 / 模拟直接武装战斗。
func preset_team() -> void:
	var tut_team: Array[String] = []
	var tut_slots: Array[String] = []
	for i in range(FIXED_TEAM.size()):
		tut_team.append(str(FIXED_TEAM[i]))
		tut_slots.append("pos-%d" % i)
	GameState.left_team = tut_team
	GameState.left_slots = tut_slots
	GameState.season_leaders = tut_team.duplicate()


## ★★唯一的出口。完成 / 跳过 / 中途离开 三种做同一件事(需求 2「跳过 = 走完拿到的东西完全相同」):
##   丢弃沙盒、换回账号原状态、只写上教程标记、存档、回主菜单。★幂等: 连调两次结果不变。
func end_tutorial(reason: String) -> void:
	if GameState == null:
		return
	last_end_reason = reason
	pending_toast = "教程完成" if reason == "completed" else ""
	## ★首启那一轮(账号还没 onboarded)= 新玩家: 结束后先起名再进主菜单(v4)。`onboarded` 在 PASSTHROUGH 里 ⇒ 这里读到的是账号的真值。
	var first_run := not bool(GameState.onboarded)
	_restore_account()
	GameState.dual_active = false
	GameState.dual_ghost = {}
	GameState.onboarded = true
	GameState.tutorial_active = false
	GameState.tutorial = false
	GameState.tutorial_stage = "done"
	_guide = null
	if not _pending_cloud.is_empty():
		var pc: Array = _pending_cloud
		_pending_cloud = []
		GameState.apply_cloud_payload(pc[0], int(pc[1]))   # 它自己会 save()
	GameState.save()
	## 首场三句记成看过: 走完教程 ⇒ 全记(正式对战一条不出); 中途离开 ⇒ 只记教程里真显示过的(FirstTips.keys_seen_on_tutorial_end)。
	##   同上: save() 之后、只改内存。
	var FT = load("res://scripts/systems/onboarding/first_tips.gd")
	for k in FT.keys_seen_on_tutorial_end(reason, _btips_tut_shown):
		FT.mark_seen(str(k))
	_btips_tut_shown = {}
	print("[Tutorial] end reason=", reason)
	var tr := get_tree()
	var cur: String = str(tr.current_scene.scene_file_path) if tr != null and tr.current_scene != null else ""
	## 起名: 首启那一轮、不是中途离开、还没起过名(云存档带回来的名字 / 模拟号自己起的名 ⇒ 不再问)。
	##   已经在主菜单上(只有门禁的主菜单替身会这样调)⇒ 不起名、不换场, 与 v3 一样。
	if first_run and reason != "abandoned" and str(GameState.nickname).strip_edges() == "" and tr != null and tr.current_scene != null and cur != MAIN_MENU:
		if cur == FIRST_LAUNCH and tr.current_scene.has_method("open_naming"):
			tr.current_scene.call("open_naming")
		else:
			first_launch_mode = "name"
			SceneNav.go(tr, FIRST_LAUNCH)
		return
	if tr != null and tr.current_scene != null and cur != MAIN_MENU:
		SceneNav.go(tr, MAIN_MENU)


## 教程期间云端拉回来的存档: 属于账号, 不属于沙盒 ⇒ 结束后再落(见 GameState.apply_cloud_payload)。
func defer_cloud_payload(p: Dictionary, rev: int) -> void:
	_pending_cloud = [p.duplicate(true), rev]


## GameState 的全部脚本变量(PASSTHROUGH 之外)深拷贝。
func _snapshot_account() -> Dictionary:
	var snap := {}
	for pr in GameState.get_property_list():
		if not (int(pr["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var k := str(pr["name"])
		if k in PASSTHROUGH:
			continue
		snap[k] = _dup(GameState.get(k))
	return snap


## 换成一份全新状态: 新建一个 GameState 实例, 读它的默认值(= 刚注册的新号)。
func _reset_to_fresh() -> void:
	var fresh: Object = (GameState.get_script() as Script).new()
	for k in _sandbox.keys():
		if k in CLOCK_KEYS:
			continue
		GameState.set(k, _dup(fresh.get(k)))
	if fresh is Node:
		(fresh as Node).free()


## 把账号原状态换回去, 清空沙盒。没有沙盒 ⇒ 什么都不做。
func _restore_account() -> void:
	if _sandbox.is_empty():
		return
	for k in _sandbox.keys():
		GameState.set(k, _sandbox[k])
	_sandbox = {}


static func _dup(v):
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v


# ═══════════════════════════════ 旧版残留 ═══════════════════════════════

## 旧版(≤0.19.559)教程中途被杀时留在盘上的真币/背包/统领 ⇒ 启动时还回去并删掉。★幂等。
func restore_residue_if_any() -> bool:
	if GameState == null or not FileAccess.file_exists(_residue_path):
		return false
	if not _sandbox.is_empty():
		return false
	var snap: Dictionary = _read_residue()
	_clear_residue()
	if snap.is_empty():
		return false
	GameState.meta_deepsea_coins = int(snap.get("coins", GameState.meta_deepsea_coins))
	GameState.persistent_bench = snap.get("bench", GameState.persistent_bench)
	GameState.season_leaders = snap.get("leaders", GameState.season_leaders)
	GameState.save()
	return true


func _read_residue() -> Dictionary:
	var f := FileAccess.open(_residue_path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var v = str_to_var(txt)
	return v if v is Dictionary else {}


func _clear_residue() -> void:
	if not FileAccess.file_exists(_residue_path):
		return
	var da := DirAccess.open("user://")
	if da != null:
		da.remove(_residue_path)


# ═══════════════════════════════ 站间推进 ═══════════════════════════════

## 从某个场景"完成"后去哪, 同时推进 tutorial_stage。here ∈ team_select / battle / shop / inventory
func next_scene_after(here: String) -> String:
	if not is_active():
		return MAIN_MENU
	match here:
		"team_select":
			GameState.tutorial_stage = "match1"
			arm_battle_sandbox()      # 写弱 ghost(跳过 Matchmaking, 不联网)
			return BATTLE
		"battle":
			GameState.tutorial_stage = "shop"
			preset_shop_offer()
			return SHOP
		"shop":
			GameState.tutorial_stage = "inventory"
			return INVENTORY
	return MAIN_MENU


## 教学战斗: 跳过 Matchmaking, 手写一个弱对手 ghost(结构照抄 backend.gd make_bot)。
func arm_battle_sandbox() -> void:
	if GameState == null:
		return
	GameState.dual_active = true
	GameState.dual_ghost = make_weak_ghost()


func make_weak_ghost() -> Dictionary:
	var foe: String = WEAK_FOE[0] if not WEAK_FOE.is_empty() else "basic"
	return {
		"schema_ver": 1,
		"ghost_id": "tutorial_weak",
		"is_bot": true,
		"bracket": 0,
		"profile": {"name": "练习木桩", "avatar": foe, "id": "TUT"},
		"leaders": [foe, foe],
		"lane_assign": {"top": [foe], "bottom": [foe]},
		"minions": {"top": [], "bottom": []},
		"loadouts": {},
		"equipped": {},
		"pet_levels": {foe: 1},
		"season_total_battles": 0,
		"season_eggs_killed": 0,
	}


# ═══════════════════════════════ 引导条 ═══════════════════════════════

## 一行接入某屏的分步引导。非教程 / 本阶段无引导 → null。
## anchor_fn: 锚点名 → 屏幕 Rect2(缺省用 host._tutorial_anchor)。
## ready_fn: 宿主「可以引导了吗」(缺省: 第一步目标矩形连续几帧不动)。
func attach_guide(host: Node, scene_id: String, anchor_fn: Callable = Callable(),
		ready_fn: Callable = Callable()) -> Node:
	if not is_active():
		return null
	var key := steps_key_for(scene_id)
	if key == "":
		return null
	## 结算引导上来 ⇒ 战斗里还没放完的不阻塞提示一并收掉(不与结算屏叠在一起), 队里没轮到的也不再出。
	_stop_battle_tips()
	var TG = load("res://scripts/scenes/TutorialGuide.gd")
	var af := anchor_fn
	## 商店多一个导演补的锚点 merge_cell(E4b「集齐 3 件……自动合成」挪到买下那一刻讲; 商店场景本身不改)。
	if not af.is_valid() and key == "shop":
		af = _shop_anchor.bind(host)
	_guide = TG.attach(host, key, Callable(), af, ready_fn)
	return _guide


## 商店锚点: merge_cell = 刚合成升星的那一件(ShopScene.merge_tip_target, 首次提示 FIRST_MERGE 圈的同一格; 没摆出来 ⇒ 顶栏「背包」);
##   其余交给商店自己的 _tutorial_anchor。
func _shop_anchor(nm: String, host: Node) -> Rect2:
	var TG = load("res://scripts/scenes/TutorialGuide.gd")
	if nm == "merge_cell":
		if host != null and is_instance_valid(host) and host.has_method("merge_tip_target"):
			return TG.vis_rect(host.call("merge_tip_target", TUT_MERGE_ITEM, 2))
		return Rect2()
	if host != null and is_instance_valid(host) and host.has_method("_tutorial_anchor"):
		return host.call("_tutorial_anchor", nm)
	return Rect2()


## 买下之后没合成出 2 星(本不该发生: 教程开局配置保证凑满 3 件)⇒ 「自动合成」那一句不讲, 直接下一步。
func _skip_merge_tip_if_none() -> void:
	for it in GameState.persistent_bench:
		if it is Dictionary and str((it as Dictionary).get("id", "")) == TUT_MERGE_ITEM and int((it as Dictionary).get("star", 1)) >= 2:
			return
	if _guide != null and is_instance_valid(_guide) and not _guide.is_queued_for_deletion():
		_guide.notify("tip_merge_seen")


## 某个动作发生了 ⇒ 转给当前引导条(它自己比对 advanceOn)。非教程 / 没有引导 ⇒ 什么都不做。
func notify(event: String) -> void:
	if _guide != null and is_instance_valid(_guide) and not _guide.is_queued_for_deletion():
		_guide.notify(event)
		if event == "item_bought" and is_active():
			_skip_merge_tip_if_none.call_deferred()


## 当前阶段该挂哪套引导步骤。空 = 这一屏本阶段没有引导。
func steps_key_for(scene: String) -> String:
	if not is_active():
		return ""
	var st := stage()
	## v5: 进教程先到选龟屏(分镜 B1~B4)。
	if scene == "team_select" and st == "team_select":
		return "team_select"
	## ★2026-10-19 起对局里没有摆位屏(站位在背包里摆): 开场演出完直接开打。
	## ★v3: 开打后两句**不阻塞**提示(三路规则 / 碎蛋), 不暂停、不挡点击、自己淡出(方案书 D7)。
	if scene == "battle" and st == "match1":
		return "battle"
	if scene == "settle" and st == "match1":
		return "settle"
	if scene == "shop" and st == "shop":
		return "shop"
	if scene == "inventory" and st == "inventory":
		return "inventory"
	return ""


# ═══════════════════════════════ 战斗里的不阻塞提示 ═══════════════════════════════

## 教学战斗一进场就挂上(导演 `_process` 看到战斗场景时调)。提示要等开场演出(三路总览 / 对阵卡)
##   完全淡出、真正开打之后才出现(`_battle_ready`) —— 10-07 B1 那条: 演出卡上不许压提示。
## ★战斗场景一行都不用改: 事件、锚点与就绪判据都在这里读战斗的只读状态(每帧轮询, 判据都是「发生过就一直成立」的量,
##   一帧跑几步 sim 也漏不掉 —— memory fb-measure-events-not-samples)。
## ★v5: 6 句各挂一个事件(`trigger`), 事件第一次发生才排队; 一次显示一句; 某句挂上 TIP_STALE_SEC 秒还没机会显示就丢掉。
func _attach_battle_tips(bt: Node) -> void:
	_stop_battle_tips()
	var key := steps_key_for("battle")
	if key == "":
		return
	_btips_bt = bt
	_btips_steps = load("res://scripts/scenes/TutorialGuide.gd").steps_for(key)
	_btips_log = []
	_btips_tut_shown = {}
	load("res://scripts/systems/onboarding/tutorial_buff.gd").attach_badge(bt)   # 「教程加成」签(用 load: 那边 preload 了本文件)


func _stop_battle_tips() -> void:
	if _battle_tips != null and is_instance_valid(_battle_tips):
		_battle_tips.queue_free()
	_battle_tips = null
	_btips_bt = null
	_btips_steps = []
	_btips_fired = {}
	_btips_queue = []
	_btips_ctx = {}
	_btips_cur_ctx = {}
	_btips_wait = 0.0
	_btips_cur_shown = false
	_btips_cur_step = {}
	_btips_first = false


## 每帧: 看哪个事件第一次发生了 ⇒ 排队; 当前那一句放完 / 过期 ⇒ 挂下一句。
func _tick_battle_tips(dt: float) -> void:
	var bt := _btips_bt
	if bt == null or not is_instance_valid(bt) or not bt.is_inside_tree():
		_stop_battle_tips()
		return
	for i in range(_btips_steps.size()):
		if _btips_fired.has(i):
			continue
		var st: Dictionary = _btips_steps[i]
		if _trigger_hit(bt, st):
			_btips_fired[i] = true
			var q: Dictionary = st.duplicate()
			q["_ctx"] = _btips_ctx.get(str(st.get("trigger", "")), {})
			q["text"] = _fill_battle_text(str(st.get("text", "")), q["_ctx"])
			q["_idx"] = i
			## 队按步骤表顺序排(同时发生的几件事, 按分镜顺序讲)
			var at := _btips_queue.size()
			for j in range(_btips_queue.size()):
				if int((_btips_queue[j] as Dictionary).get("_idx", 0)) > i:
					at = j
					break
			_btips_queue.insert(at, q)
	if _battle_tips != null and is_instance_valid(_battle_tips) and not _battle_tips.is_queued_for_deletion():
		if _battle_tips.is_showing():
			if not _btips_cur_shown:
				_on_battle_tip_shown(_btips_cur_step)
			_btips_cur_shown = true
		elif not _btips_cur_shown and _battle_ready(bt):
			## ★只在「开打着、本可以显示」时计过期(战场之间的演出不算): 等到下一个战场开打照样能出
			_btips_wait += dt
			if _btips_wait >= TIP_STALE_SEC:
				_battle_tips.queue_free()
				_battle_tips = null
		return
	_battle_tips = null
	if _btips_queue.is_empty():
		return
	## 开场那几句(trigger=fight, C1 / C2)先讲: 它们没排进队之前, 别的事件先等着(开场大师立刻出钩, 不许抢在 C1 前面)
	for i2 in range(_btips_steps.size()):
		if str((_btips_steps[i2] as Dictionary).get("trigger", "")) == "fight" and not _btips_fired.has(i2):
			return
	var nx: Dictionary = _btips_queue.pop_front()
	## C3 点名哪只: 挂上这一刻, 在放过技能的我方龟里挑身上没有别的单位叠着的那只(文案与圈都跟着它; 都挤着就用原来那只)
	if str(nx.get("trigger", "")) == "ally_skill":
		var pick = _clear_caster(bt, nx.get("_ctx", {}))
		if not is_same(pick, nx.get("_ctx", {})):
			nx["_ctx"] = pick
			nx["text"] = _fill_battle_text(str((_btips_steps[int(nx.get("_idx", 0))] as Dictionary).get("text", "")), pick)
	_btips_cur_ctx = nx.get("_ctx", {})
	_btips_cur_step = nx
	_btips_wait = 0.0
	_btips_cur_shown = false
	_btips_log.append(str(nx.get("_id", nx.get("advanceOn", ""))))
	var TG = load("res://scripts/scenes/TutorialGuide.gd")
	_battle_tips = TG.attach_steps(bt, [nx], Callable(), _battle_anchor.bind(bt), _battle_ready.bind(bt))


## 一句第一次真显示在屏上: 教程模式记下 _id(结束时记成看过); 首场正式对战模式当场记成看过(FirstTips 账号键)。
func _on_battle_tip_shown(st: Dictionary) -> void:
	if _btips_first:
		var k := str(st.get("_ft_key", ""))
		if k != "":
			load("res://scripts/systems/onboarding/first_tips.gd").mark_seen(k)
	else:
		_btips_tut_shown[str(st.get("_id", ""))] = true


# ═══════════════════════════════ 首场正式对战的三句(跳过教程的玩家) ═══════════════════════════════

## 不在沙盒里时每帧调: 新的战斗场景成了当前场景 ⇒ 看要不要挂首场正式对战那三句。
##   ★只在自己挂上的时候推队列(`_btips_first`): 门禁手动喂队列(不在沙盒里)时不重复推。
func _tick_first_battle(dt: float) -> void:
	var tr := get_tree()
	var cs: Node = tr.current_scene if tr != null else null
	if cs != null and str(cs.scene_file_path) == BATTLE and cs.get_instance_id() != _battle_tips_scene_id:
		_battle_tips_scene_id = cs.get_instance_id()
		_attach_first_battle_tips(cs)
	if _btips_first and _btips_bt != null:
		_tick_battle_tips(dt)


## 跳过(或中途离开)教程的玩家, 第一场正式对战: 两路 / 龟蛋 / 终极战场各一句(我的提议, 用户未明确要过; 走完教程的玩家不出, 2026-10-23)。
##   句子 = 教程战斗 C2 / C5 / C6 原句(步骤表同一份), 挂在同一个战斗事件上, 同一种不阻塞提示条。
##   ★只在自己的正式对局里出(本局在录 = 积分赛 / 闯关 / 决赛自己那一场; 或看自己那一场周六服务器局):
##     回放 / 观赛别人 / 调试场 / 评审台一律不出。教程中 / 没 onboarded ⇒ FirstTips.can_show 挡住。
func _attach_first_battle_tips(bt: Node) -> void:
	_stop_battle_tips()
	if not is_own_match(bt):
		return
	var FT = load("res://scripts/systems/onboarding/first_tips.gd")
	var steps: Array = FT.battle_tip_steps(true)
	if steps.is_empty():
		return
	_btips_bt = bt
	_btips_steps = steps
	_btips_log = []
	_btips_first = true


## 这一场是不是玩家自己的正式对局。
func is_own_match(bt: Node) -> bool:
	if bt == null or GameState == null or bool(GameState.get("tutorial_active")):
		return false
	var rp = bt.get("_replay")
	if rp != null and str(rp.get("mode")) == "rec":
		return true
	return load("res://scripts/systems/onboarding/first_tips.gd").is_server_match(bt)


## 战斗里显示过 / 挂过的提示(按顺序, 分镜编号)。门禁读。
func battle_tips_log() -> Array:
	return _btips_log.duplicate()


## 某句的事件发生过没有。★都是「一旦发生就一直成立」的量(不靠抓某一帧的跃迁):
##   fight         开打了(演出幕布全收) 且本战场开打后过了 delay 秒
##   ally_skill    我方某只龟放过技能(skill_gcd_until 只在真放出技能时写, 之后不回 0)
##   trainer_skill 场边我方训龟大师放过技能(文案说「你的训龟大师」; 敌方大师开场就出钩, 不算)(主动冷却 _active_cd > 0, 冷却好几秒, 每帧都看得到)
##   foe_egg_hit   敌方龟蛋掉过血
##   final_lane    进了终极战场(上下两路 1 : 1)
func _trigger_hit(bt: Node, st: Dictionary) -> bool:
	var tg := str(st.get("trigger", ""))
	var units = bt.get("_units")
	match tg:
		"fight":
			return _battle_ready(bt) and float(bt.get("_t")) - float(bt.get("_sd_t0")) >= float(st.get("delay", 0.0))
		"ally_skill":
			if units is Array:
				for u in units:
					if str(u.get("side", "")) == "left" and not bool(u.get("is_trainer", false)) and not bool(u.get("is_summon", false)) \
							and not bool(u.get("_isMinion", false)) and not bool(u.get("_isEgg", false)) \
							and float(u.get("skill_gcd_until", 0.0)) > 0.0 and bool(u.get("alive", false)):
						_btips_ctx[tg] = u
						return true
		"trainer_skill":
			if units is Array:
				for u in units:
					if bool(u.get("is_trainer", false)) and str(u.get("side", "")) == "left" 							and float(u.get("_active_cd", 0.0)) > 0.0 and bool(u.get("alive", false)):
						_btips_ctx[tg] = u
						return true
		"foe_egg_hit":
			if units is Array:
				for u in units:
					if bool(u.get("_isEgg", false)) and str(u.get("side", "")) == "right" \
							and float(u.get("hp", 0.0)) < float(u.get("maxHp", 0.0)) - 0.01:
						return true
		"final_lane":
			return str(GameState.current_lane) == "final" and _battle_ready(bt)
	return false


## 战斗提示里的 {pet}: 触发那只龟的名字。
func _fill_battle_text(t: String, u) -> String:
	if not t.contains("{pet}"):
		return t
	var nm := ""
	if u is Dictionary and not (u as Dictionary).is_empty():
		var pid := str((u as Dictionary).get("id", ""))
		var pd = DataRegistry.pet_by_id.get(pid, {})
		nm = str((pd as Dictionary).get("name", pid)) if pd is Dictionary else pid
	return t.replace("{pet}", nm)


## 开打了、演出幕布全淡出、还没结束。
func _battle_ready(bt: Node) -> bool:
	if bt == null or not is_instance_valid(bt) or bool(bt.get("_over")):
		return false
	## v5: 破蛋窗口(一方团灭后打蛋那 10 秒)也算开打 —— C5「击碎敌方的【龟蛋】」恰恰发生在这里, 不放行就要拖到下一个战场才讲。
	if not (str(bt.get("_dl_state")) in ["fight", "eggwindow"]):
		return false
	var pr = bt.get("_dl_present_root")
	if pr != null and is_instance_valid(pr):
		return false
	var dl = bt.get("_dl_sys")
	if dl != null and dl.present_fading != null and is_instance_valid(dl.present_fading):
		return false
	## 开打那一下的演出(定格 + 闪屏 +「开 战」大字)放完再出, 不和它叠在一起。按本战场自己的钟(`_sd_t0`, CLAUDE.md §3.4)。
	return float(bt.get("_t")) - float(bt.get("_sd_t0")) >= TIP_AFTER_FIGHT_SEC


## 开打后多少游戏秒才出第一句(「开 战」大字约 1 秒)。
const TIP_AFTER_FIGHT_SEC := 1.5


## 战斗里的锚点: lane_plate = 顶部那块当前战场计时牌; foe_egg = 顶部 PK 条下方敌方那一段**蛋血副条**(带蛋图标)。
## v5: buff_badge =「教程加成」签; cast_unit = 第一次放技能那只龟头顶的血条 + 龟能槽; trainer = 第一次放技能的训龟大师(脚底到头顶)。
## ★不圈场上的蛋本体: 实拍(10-20)蛋在战场右沿、被右侧队伍卡压住一半, 环圈出来像在指「小将」那张卡。
func _battle_anchor(nm: String, bt: Node) -> Rect2:
	if bt == null or not is_instance_valid(bt):
		return Rect2()
	match nm:
		"buff_badge":
			var bn: Node = bt.get_node_or_null("TutorialBuffBadge")
			if bn == null:
				return Rect2()
			return load("res://scripts/scenes/TutorialGuide.gd").vis_rect(bn.get("badge"))
		"cast_unit":
			## ★v5 修(10-21 录屏自评): 原来只圈头顶那组小条(等级牌 + 龟能细条, 82×14), 旁边敌方小将的血条叠在上沿,
			##   看起来圈的是那只小将。⇒ 圈【{pet} 那一只】的身体 + 它头顶整组条(血条 + 龟能槽), 与文案点名的是同一个单位(_btips_cur_ctx)。
			var rr := _cast_rect(bt, _btips_cur_ctx)
			if rr.size.x <= 0.0:
				return Rect2()
			## ★别的单位叠在它身上(近战扎堆: 10-21 录屏里一只敌方小将正站在石头龟身上, 圈里看见的是小将)⇒ 先不显示,
			##   等它们分开; 等了 CAST_CROWD_WAIT 秒还挤着就照常显示(不让这一句卡住队列)。
			if not _btips_cur_shown and _btips_wait < CAST_CROWD_WAIT and _crowded(bt, _btips_cur_ctx, rr):
				return Rect2()
			return rr
		"trainer":
			return _unit_body_rect(bt, _btips_cur_ctx)
		"lane_plate":
			var TG = load("res://scripts/scenes/TutorialGuide.gd")
			return TG.vis_rect(bt.get("_dl_hud"))
		"foe_egg":
			var hud = bt.get("_hud")
			if hud == null:
				return Rect2()
			var TG2 = load("res://scripts/scenes/TutorialGuide.gd")
			var r: Rect2 = TG2.vis_rect(hud.get("_pk_egg_r"))
			if r.size.x <= 0.0:
				return Rect2()
			## 连同那一端的蛋图标一起圈(图标在副条外沿)
			for ic in hud.get("_pk_egg_icons"):
				var ir: Rect2 = TG2.vis_rect(ic)
				if ir.size.x > 0.0 and ir.get_center().x > r.get_center().x:
					r = r.merge(ir)
			return r
	return Rect2()


## C3 圈点名那只时, 别的单位挤在圈里最多等这么久(游戏秒, 与过期同一个钟 _btips_wait; 过期是 TIP_STALE_SEC)。
const CAST_CROWD_WAIT := 6.0


## 放过技能的我方龟里, 身上没有别的单位叠着的那只; 都挤着(或只有一只)⇒ 原来那只。
func _clear_caster(bt: Node, cur):
	var units = bt.get("_units")
	if not (units is Array):
		return cur
	if cur is Dictionary and not (cur as Dictionary).is_empty() and not _crowded(bt, cur, _cast_rect(bt, cur)):
		return cur
	for u in units:
		if str(u.get("side", "")) == "left" and not bool(u.get("is_trainer", false)) and not bool(u.get("is_summon", false)) 				and not bool(u.get("_isMinion", false)) and not bool(u.get("_isEgg", false)) 				and float(u.get("skill_gcd_until", 0.0)) > 0.0 and bool(u.get("alive", false)):
			var r := _cast_rect(bt, u)
			if r.size.x > 0.0 and not _crowded(bt, u, r):
				return u
	return cur


## 一只龟的「身体 + 头顶整组条」屏幕框(C3 圈的就是它)。
func _cast_rect(bt: Node, u) -> Rect2:
	var br := _unit_bar_rect(u)
	if br.size.x <= 0.0:
		return Rect2()
	var bb := _unit_body_rect(bt, u)
	return br.merge(bb) if bb.size.x > 0.0 else br


## 圈 rr(点名那只的身体 + 头顶条)里有没有别的活单位的头顶条(= 有别的单位叠在它身上)。
func _crowded(bt: Node, u, rr: Rect2) -> bool:
	var units = bt.get("_units")
	if not (units is Array):
		return false
	for o in units:
		if is_same(o, u) or not bool(o.get("alive", false)) or bool(o.get("is_trainer", false)):
			continue
		var ob = o.get("bar_root", null)
		if ob == null or not is_instance_valid(ob) or not (ob is Control) or not (ob as Control).is_visible_in_tree():
			continue
		if rr.intersects((ob as Control).get_global_rect()):
			return true
	return false


## 一只龟头顶那组条(血条 + 龟能槽)的屏幕矩形。龟死了 / 条没显示 ⇒ 空。
func _unit_bar_rect(u) -> Rect2:
	if not (u is Dictionary) or not bool((u as Dictionary).get("alive", false)):
		return Rect2()
	var root = (u as Dictionary).get("bar_root", null)
	if root == null or not is_instance_valid(root) or not (root is Control) or not (root as Control).is_visible_in_tree():
		return Rect2()
	## 整组条的底框(血条画在它自己的 _draw 里, 不是子控件) + 各子控件(等级牌 / 龟能槽)
	var r := (root as Control).get_global_rect()
	var first := r.size.x <= 0.0
	for c in (root as Control).find_children("*", "Control", true, false):
		var cc := c as Control
		if not cc.is_visible_in_tree():
			continue
		var gr := cc.get_global_rect()
		if gr.size.x <= 0.0 or gr.size.y <= 0.0:
			continue
		if first:
			r = gr
			first = false
		else:
			r = r.merge(gr)
	return r


## 一个单位(训龟大师)在屏上的身体框: 脚底到头顶的投影, 宽 90。
func _unit_body_rect(bt: Node, u) -> Rect2:
	if not (u is Dictionary) or not bool((u as Dictionary).get("alive", false)):
		return Rect2()
	var cam = bt.get("_cam")
	if cam == null or not is_instance_valid(cam) or not bt.has_method("_world_pos"):
		return Rect2()
	var pos: Vector2 = (u as Dictionary).get("pos", Vector2.ZERO)
	var h: float = float((u as Dictionary).get("height", 0.0))
	var head: Vector3 = bt.call("_world_pos", pos, h + 2.4)
	var feet: Vector3 = bt.call("_world_pos", pos, 0.0)
	if (cam as Camera3D).is_position_behind(head) or (cam as Camera3D).is_position_behind(feet):
		return Rect2()
	var sh: Vector2 = (cam as Camera3D).unproject_position(head)
	var sf: Vector2 = (cam as Camera3D).unproject_position(feet)
	var top: float = minf(sh.y, sf.y)
	var hgt: float = maxf(40.0, absf(sf.y - sh.y))
	return Rect2(Vector2(sf.x - 45.0, top), Vector2(90.0, hgt))


# ═══════════════════════════════ 外壳(跳过钮 + 吞返回键) ═══════════════════════════════

func _attach_chrome(scene: Node) -> void:
	var TC = load("res://scripts/scenes/tutorial_chrome.gd")
	var c: Node = TC.new()
	c.name = "TutorialChrome"
	scene.add_child(c)
