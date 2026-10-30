class_name Spar
extends RefCounted
## 好友切磋 —— 我当前的背包阵容 vs 好友最新的背包阵容, **不在常规赛里**。
## 方案书: docs/plans/20261023-好友切磋.md §4.3。
## 用户 2026-10-23「切记不会去叠比如香火石，宝箱龟被动的层数，因为是不在常规赛里的」
##   ⇒ 范围按「一切常规赛累积」算(§2.3 穷举: 香火 / 宝箱 / 赌神 / 斧头击杀经验 / 生命 / 场次 / 战绩 / 录像 / 上传 …)。
##
## ══════════════════════════════════════════════════════════════════════
##  两层隔离
## ══════════════════════════════════════════════════════════════════════
## 第一层(切磋标志 `active`): 读它的地方 ——
##   `_settle_season` 第二行提前返回(在决赛上报之前) / `ReplayRecorder.should_record()` / `_is_scored_match()`
##   ⇒ 不录像、不直播、不上传、没有待结算单、宝箱龟不写存档、R 键可重开。
## 第二层(兜底): 开局 `ReplayRecorder.capture_all()` 整份备份 + `test_mode = true`, 离场还原 ——
##   香火石 / 赌神 / 小木斧击杀这些**局内实时写、没有闸**的, 以及**以后新加的**写入点,
##   都不落盘(save 空转)、不上云(推送空转)、离场后内存也回到切磋之前那一份。
##   与回放(`ReplayRecorder.begin_play / end_play`)、教程沙盒是同一招。
## 门禁: tests/verify_spar_isolation.gd(切磋前后 `_save_dict()` 逐键相同; 去掉任一层 ⇒ 红)。
##
## 左方 = 我当前的阵容: 战斗场照常读 `season_leaders` / `dual_lineup` / 装备 / 等级 / 香火起点……(只读)。
##   ★不走选龟页: 「出战」会写 `week_phase` / `lastLineup.json` 并 `save()`(方案书 §2.3)。
## 右方 = 好友的快照: 照教程 `arm_battle_sandbox()` 直接塞 `GameState.dual_ghost`。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
const FRIENDS_SCENE := "res://scenes/Friends.tscn"
## 2026-10-30 排行榜上也能切磋(方案书 docs/plans/20261030-排行榜切磋.md): 对方信息带 `back` ⇒ 结算屏回那一页。
const LEADERBOARD_SCENE := "res://scenes/Leaderboard.tscn"
const SUBTITLE := "切磋 · 不计入赛季进度"

## 正在切磋(从 `begin` 到离开战斗场)。
static var active := false
## 对方: {"account", "name", "tag", "avatar", "back"(可省, 默认好友页)}(结算屏 / 再来一局用)。
static var friend: Dictionary = {}
static var _ghost: Dictionary = {}
static var _backup: Dictionary = {}
static var _backup_test_mode := false
## 「再来一局」: 旧战斗场离树(`end`)时先还原, 再按同一份快照重新挂上(与回放「再看一遍」同一个时序)。
static var _again := false
## 切磋期间云端拉回来的存档: 属于账号, 不属于这一局 ⇒ 还原之后再落(照教程 `defer_cloud_payload`)。
static var _pending_cloud: Array = []


static func is_active() -> bool:
	return active


## 结算屏那颗「返回」回哪一页 / 叫什么(从哪儿发起的切磋就回哪儿)。
static func back_scene() -> String:
	return LEADERBOARD_SCENE if str(friend.get("back", "")) == LEADERBOARD_SCENE else FRIENDS_SCENE


static func back_label() -> String:
	return "返回排行榜" if back_scene() == LEADERBOARD_SCENE else "返回好友"


## 我这边能不能开打: "" = 能; 否则是屏上那句原因。
static func my_side_check() -> String:
	if GameState == null:
		return "存档未就绪"
	if bool(GameState.get("tutorial_active")):
		return "教程中无法切磋"
	## 2026-10-29 周六闯关赛排队中(阵容已锁定)不开切磋: 切磋会换上另一局的沙盒, 配上时还要把人带进对局(判据 MenuQueue.locked())。
	if MenuQueue.locked():
		return MenuQueue.TXT_SPAR
	var ldr = GameState.get("season_leaders")
	if not (ldr is Array) or (ldr as Array).size() < 3:
		return "请先在选龟页选定本大轮的三只统领"
	return ""


## 备份 → 只读开关 → 挂上对手。不换场景(门禁直接实例化战斗场用)。返回 false = 没开(原因见 `my_side_check`)。
static func begin(ghost: Dictionary, info: Dictionary) -> bool:
	if ghost.is_empty() or my_side_check() != "":
		return false
	if not active:
		## 设备身份 / 默认昵称都是「第一次用到才生成并落盘」的身份值 ⇒ 先生成好再备份,
		##   免得第一次生成发生在切磋里、离场时被还原抹掉(反向验证 L2 照出来的)。
		GameState.get_install_uid()
		GameState.default_nickname()
		_backup = ReplayRecorder.capture_all()
		_backup_test_mode = bool(GameState.test_mode)
	active = true
	_ghost = ghost.duplicate(true)
	friend = info.duplicate(true)
	GameState.test_mode = true          # 第二层: 任何 save() / 云推送 / 待结算单都空转
	GameState.dual_active = true
	GameState.dual_ghost = ghost.duplicate(true)
	var prof: Dictionary = ghost.get("profile", {}) if ghost.get("profile") is Dictionary else {}
	GameState.dual_opponent = {
		"name": str(info.get("name", prof.get("name", ""))),
		"avatar": str(info.get("avatar", prof.get("avatar", ""))),
		"id": str(info.get("tag", prof.get("id", ""))),
	}
	return true


## 开打: 挂上 + 进战斗场。返回 "" = 已进; 否则是原因。
static func start(tree: SceneTree, ghost: Dictionary, info: Dictionary) -> String:
	var why := my_side_check()
	if why != "":
		return why
	if not begin(ghost, info):
		return "对方阵容读取失败"
	SceneNav.go(tree, BATTLE_SCENE)
	return ""


## 结算屏「再来一局」。
static func again(tree: SceneTree) -> void:
	if not active:
		return
	_again = true
	SceneNav.go(tree, BATTLE_SCENE)


## 离开战斗场(`_exit_tree` 一定会调; 不在切磋里是空转): GameState 还原成切磋之前那一份。
static func end() -> void:
	if not active:
		return
	for n in _backup:
		var v = _backup[n]
		GameState.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	GameState.test_mode = _backup_test_mode
	_backup = {}
	active = false
	if _again:
		_again = false
		begin(_ghost, friend)
		return
	_ghost = {}
	friend = {}
	if not _pending_cloud.is_empty():
		var pc: Array = _pending_cloud
		_pending_cloud = []
		GameState.apply_cloud_payload(pc[0], int(pc[1]))


static func defer_cloud_payload(p: Dictionary, rev: int) -> void:
	_pending_cloud = [p.duplicate(true), rev]
