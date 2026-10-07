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
## 流程: 首启选择框 →(开始教程)→ 选龟 → 战斗(三路) → 结算 → 商店(买经验升 2 级 + 买 1 件装备)
##       → 背包(点装备 → 点龟装上) → 完成教程 → 主菜单。
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
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const SHOP := "res://scenes/Shop.tscn"
const INVENTORY := "res://scenes/Inventory.tscn"

## 教学固定阵容(用户 2026-07-23 拍板: 固定阵容 + 弱对手必赢)。
const FIXED_TEAM := ["basic", "stone", "bamboo"]
## 弱对手阵容(必赢)。
const WEAK_FOE := ["basic"]
## 教学沙盒里的深海币: 买一次经验(4) 升到 2 级 + 买一件低费装备。沙盒丢弃时一起丢弃。
const TUT_COINS := 20

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


func _ready() -> void:
	call_deferred("restore_residue_if_any")


## ★★看门狗 + 外壳。**任何**离开教程的方式最后都落在主菜单 ⇒ 在一个地方收口:
##   进沙盒之后走出过主菜单、又回到主菜单 ⇒ `end_tutorial("abandoned")`。
##   (教程里已经没有返回入口了; 这条是给下一个人新写一条退出路径时兜底的。)
func _process(_dt: float) -> void:
	if _sandbox.is_empty():
		return
	var tr := get_tree()
	var cs: Node = tr.current_scene if tr != null else null
	var now: String = str(cs.scene_file_path) if cs != null else ""
	if cs != null and cs.get_instance_id() != _chrome_scene_id and now != MAIN_MENU and now != "":
		_chrome_scene_id = cs.get_instance_id()
		_attach_chrome(cs)
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

## 开始教程: 隔离账号状态 → 全新教学状态 → 进选龟。`host` 用来换场景(主菜单)。
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
	GameState.tutorial_stage = "match1_pick"
	GameState.dual_active = true
	GameState.meta_deepsea_coins = TUT_COINS
	if host != null and host.is_inside_tree():
		host.get_tree().change_scene_to_file(TEAM_SELECT)


## ★★唯一的出口。完成 / 跳过 / 中途离开 三种做同一件事(需求 2「跳过 = 走完拿到的东西完全相同」):
##   丢弃沙盒、换回账号原状态、只写上教程标记、存档、回主菜单。★幂等: 连调两次结果不变。
func end_tutorial(reason: String) -> void:
	if GameState == null:
		return
	last_end_reason = reason
	pending_toast = "教程完成" if reason == "completed" else ""
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
	print("[Tutorial] end reason=", reason)
	var tr := get_tree()
	if tr != null and tr.current_scene != null and str(tr.current_scene.scene_file_path) != MAIN_MENU:
		tr.change_scene_to_file(MAIN_MENU)


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
	var TG = load("res://scripts/scenes/TutorialGuide.gd")
	_guide = TG.attach(host, key, Callable(), anchor_fn, ready_fn)
	return _guide


## 某个动作发生了 ⇒ 转给当前引导条(它自己比对 advanceOn)。非教程 / 没有引导 ⇒ 什么都不做。
func notify(event: String) -> void:
	if _guide != null and is_instance_valid(_guide) and not _guide.is_queued_for_deletion():
		_guide.notify(event)


## 当前阶段该挂哪套引导步骤。空 = 这一屏本阶段没有引导。
func steps_key_for(scene: String) -> String:
	if not is_active():
		return ""
	var st := stage()
	if scene == "team_select" and st == "match1_pick":
		return "team_select"
	if scene == "battle" and st == "match1":
		return "place"
	if scene == "settle" and st == "match1":
		return "settle"
	if scene == "shop" and st == "shop":
		return "shop"
	if scene == "inventory" and st == "inventory":
		return "inventory"
	return ""


# ═══════════════════════════════ 外壳(跳过钮 + 吞返回键) ═══════════════════════════════

func _attach_chrome(scene: Node) -> void:
	var TC = load("res://scripts/scenes/tutorial_chrome.gd")
	var c: Node = TC.new()
	c.name = "TutorialChrome"
	scene.add_child(c)
