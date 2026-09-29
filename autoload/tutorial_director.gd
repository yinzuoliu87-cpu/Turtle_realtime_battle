extends Node
## TutorialDirector — 新手教学的跨场景导演 (用户 2026-07-23)。Autoload 单例。
##
## 用户流程: 战斗1(选龟站位) → 商店买 → 背包装+调位置 → 图鉴 → 战斗2 → 回菜单不给奖励。
##
## 只在 GameState.tutorial_active 为真时起作用。每个场景在"该离开去下一站"时问 director:
##   next_scene_after(here) → 返回下一个场景路径, director 内部把 tutorial_stage 推进。
##
## ★为什么用 autoload 而不是散在各场景: 跨 4 个场景的顺序状态机, 挂在任一场景都会随场景销毁丢失,
##   而 GameState.tutorial_stage 记"走到哪"、director 记"下一步是什么", 组合起来跨场景稳定。

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const SHOP := "res://scenes/Shop.tscn"
const INVENTORY := "res://scenes/Inventory.tscn"
const CODEX := "res://scenes/Codex.tscn"

## 教学固定阵容(用户拍板: 固定阵容+弱对手必赢)。3 只上手简单的龟。
const FIXED_TEAM := ["basic", "stone", "bamboo"]
## 弱对手阵容(必赢): 低配, 让新手两把都稳赢。
const WEAK_FOE := ["basic"]
## 教学发的沙盒币(够买 1~2 件低费装备教"买→装")。结束时连同背包一起还原, 不留存。
const TUT_COINS := 20

## 教学开始时的真经济快照(币+背包+三统领)。离开教学(**任何方式**)时还原 → 落实"不获得任何奖励"。
## ★为空 = 未武装沙盒经济。
var _econ_snapshot: Dictionary = {}

## ★★SANDBOX_ABANDON —— 快照的【落盘副本】。进沙盒就写、还原后删。
## 由来(2026-09-29 实测 · tests/_probe_sandbox_abandon.gd): 原来还原**只在 `_finish()`**,
##   而教学里商店/背包每装一件就 `GameState.save()` ⇒ **盘上那份当场就是 20 币了**
##   (探针: 进教学前盘上 292 → 教学中 save() 后盘上 20; leaders 也被教学那三只覆盖)。
##   中途退出 = 永久丢。
## ★为什么光有下面的看门狗不够: 进程被杀 / 崩溃 / 手机后台被回收时, 看门狗与 `_finish()`
##   一行都跑不到 —— 只有盘上留了东西, 下次启动才有得还。
## ★为什么"下次启动发现残留"就一定是放弃: `tutorial_active` **不进存档**(GameState.gd:106),
##   重开之后不可能还在教学里 ⇒ 盘上有残留 = 上一条命没还回来。
const SANDBOX_RESIDUE := "user://tutorial_sandbox.dat"

## 残留文件的真实路径。★可注入 —— 门禁把它指到临时文件, 绝不碰玩家 user:// 里那一份
##   (测试留下的残留会在玩家下次启动时被当真, 那是比原 bug 更狠的存档污染)。
var _residue_path: String = SANDBOX_RESIDUE

## 看门狗: 上一次观测到的"当前场景"路径。用来认出【从别处回到主菜单】这个跃迁。
var _last_scene_path: String = ""
## 武装沙盒之后, 是否真的离开过主菜单。★这是"回来"与"还没走"的分界线 ——
##   begin_sandbox() 是在主菜单上调的, 没有这个位就会当场把自己当成"已经回来了"。
var _sandbox_left_menu: bool = false


func _ready() -> void:
	## ★延后一帧再查残留: GameState 自己的 `_ready` 里读档 + `ensure_season()` 还会动钱包,
	##   等这一帧的活干完再还, 免得被随后那几步盖掉。
	## ⚠ 主场景的 `_ready` 可能比这个 deferred 更早跑到 `begin_sandbox()` ——
	##   所以 `begin_sandbox()` 自己【也】先查一遍残留。两处都查 ⇒ 顺序不再承重。
	call_deferred("restore_residue_if_any")


## ★★SANDBOX_ABANDON 看门狗。**任何**离开教学的方式最后都落在主菜单:
##   背包 ESC / 背包返回键 / 图鉴 ESC / 图鉴返回键 / 选龟返回 / 战斗退出 / 导演回落 ——
##   全都是 `change_scene_to_file("res://scenes/MainMenu.tscn")`。
## ⇒ 在**一个**地方收口, 比去六个场景各加一行可靠: 下一个人新写一条退出路径也照样被收住
##   (用户 2026-09-29:「我看重的是任何离开方式都还得回来」)。
func _process(_dt: float) -> void:
	if _econ_snapshot.is_empty():
		return                      # 没武装沙盒 = 没东西要还(绝大多数帧到此结束)
	var now: String = _current_scene_path()
	## ★★空路径【不记也不判】—— `change_scene_to_file` 换场的那一瞬间 `current_scene` 是 null。
	##   第一版这里用的是"上一屏非空"当"来过别处"的证据, 而换场必然插进来一次空 ⇒
	##   紧接着的主菜单看起来像"从没地方来的" ⇒ **真按 ESC 回主菜单, 币没还**。
	##   实测抓到它的是 tests/_probe_real_abandon.gd(真 change_scene + 真 ESC);
	##   只拿"直接改 current_scene"测是**测不出来的**(那条路径不会经过空)。
	if now == "" or now == _last_scene_path:
		return
	_last_scene_path = now
	if now != MAIN_MENU:
		_sandbox_left_menu = true   # 武装之后真的走出去过了
		return
	if _sandbox_left_menu:
		on_abandon()


func _notification(what: int) -> void:
	## 桌面关窗 = 这个进程真的要没了 ⇒ 当场还原并落盘。
	## ⚠ **不**收 `NOTIFICATION_APPLICATION_PAUSED`(手机切后台): 切后台多半是切回来接着玩,
	##   那时把真币还回去 = 教学中途花的是真钱, 比原 bug 更糟。后台被杀由残留兜住。
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _econ_snapshot.is_empty():
		restore_sandbox(true)


func _current_scene_path() -> String:
	var tr := get_tree()
	if tr == null:
		return ""
	var cs := tr.current_scene
	return str(cs.scene_file_path) if cs != null else ""


## 【放弃教学】没走完就离开。还原真经济**并落盘** —— 只改内存等于没修(盘上早就是 20 了)。
## ★不动 `tutorial_active` / `onboarded` / `tutorial_mandatory`: 那是"教学要不要重来"的问题,
##   与"钱得还回来"是两件事。再点一次「?」会重新 `begin_sandbox()`(那时快照已空 ⇒ 拿到的是真值)。
func on_abandon() -> bool:
	if not restore_sandbox(true):
		return false
	if GameState != null:
		GameState.dual_active = false
		GameState.dual_ghost = {}      # 教学那只弱 ghost 不留给下一场真对局(与 _finish 同口径)
	return true


## 把快照里的真【币 + 背包 + 三统领】还回去, 清快照与残留。also_save = 顺手落盘。
## 返回 false = 没东西要还(没武装沙盒 / 已经还过了)。
## ★★这是【唯一】一处还原 —— `_finish()` / 看门狗 / 关窗 / 残留兜底 四条路都调它。
##   各写一份的话, 下一个加字段的人只会加一边 —— 这个 bug 的第二层就是这么来的
##   (加 season_leaders 快照的人只改了 `_finish()`)。
func restore_sandbox(also_save: bool) -> bool:
	if GameState == null or _econ_snapshot.is_empty():
		return false               # ⚠ 这里【不】删残留: 内存空而盘上有 = 还没还, 删了就真丢了
	GameState.meta_deepsea_coins = int(_econ_snapshot.get("coins", 0))
	GameState.persistent_bench = _econ_snapshot.get("bench", [])
	GameState.season_leaders = _econ_snapshot.get("leaders", [])
	_econ_snapshot = {}
	_clear_residue()
	if also_save:
		GameState.save()
	return true


## 【崩溃 / 强杀 兜底】盘上有沙盒残留 ⇒ 上次教学没走完就没了, 把真经济还回去。
## 返回 true = 真还了东西。★幂等: 还完就把残留删掉。
func restore_residue_if_any() -> bool:
	if GameState == null:
		return false
	if not FileAccess.file_exists(_residue_path):
		return false
	if not _econ_snapshot.is_empty():
		return false               # 本进程正在沙盒里 → 内存那份更新, 别让盘上的旧账盖它
	var snap: Dictionary = _read_residue()
	if snap.is_empty():
		_clear_residue()           # 残留坏了/读不出来 → 删掉, 免得每次启动都试一遍
		return false
	_econ_snapshot = snap
	return restore_sandbox(true)


func _write_residue(snap: Dictionary) -> void:
	var f := FileAccess.open(_residue_path, FileAccess.WRITE)
	if f == null:
		push_warning("[TutorialDirector] 沙盒残留写不出来: " + _residue_path)
		return
	## ★用 var_to_str 不用 JSON: JSON 回来时 int 全变 float(装备的 star 之类),
	##   而这份东西是要【原样】还进玩家存档的。
	f.store_string(var_to_str(snap))
	f.close()


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


func is_active() -> bool:
	return GameState != null and bool(GameState.get("tutorial_active"))


## 武装教学沙盒经济: 快照真【币+背包】, 发教学币。结束(_finish)会还原 → 不留存(用户「不获得任何奖励」)。
## ★幂等: 已武装(快照非空)就不再快照(否则第二次快照会把"发的教学币"当真余额存下来)。
func begin_sandbox() -> void:
	if GameState == null or not _econ_snapshot.is_empty():
		return
	## ★★先把上一条命的残留吃掉, 再快照 —— 否则会把【上次没还回来的沙盒币】当成真余额
	##   存进新快照, 结束时"还原"成 20 ⇒ 那才真成永久的了。
	##   (这也让 `_ready()` 里那次 deferred 检查的先后顺序不再承重。)
	restore_residue_if_any()
	_sandbox_left_menu = false     # 刚在主菜单上武装 ⇒ "还没走出去过"
	_econ_snapshot = {
		"coins": int(GameState.meta_deepsea_coins),
		"bench": GameState.persistent_bench.duplicate(true),
		## ★★SANDBOX_RESTORE: season_leaders 也要快照。
		##   GameState.gd:105 的合约写着「tutorial_active 为真时**不设 season_leaders**」,
		##   但 TeamSelectScene.gd:1346 那行一个教学判断都没有, 教学确认阵容时照写不误
		##   ⇒ 走完教学的人被 _roster_locked 锁死在教学那三只龟上, **换不掉**。
		##   (2026-09-29 实测: 十个全新账号会是同一套阵容。)
		##   不去改 1346 —— 教学局的战斗左队还读它; 按这里既有的**快照-还原**设计收口才对路。
		"leaders": (GameState.season_leaders.duplicate() if GameState.season_leaders is Array else []),
	}
	## ★★残留落盘: 只在【存档真会被写】的时候写。
	##   `test_mode` 开着时 `GameState.save()` 是空转 ⇒ 盘上从来没被沙盒污染过 ⇒ 无可修。
	##   反过来更要紧: 门禁 / VFXLAB / 调试台都开着这道闸, 照写的话它们留下的残留
	##   会在玩家下次启动时被当真 —— 那是比原 bug 更狠的存档污染。
	if not bool(GameState.test_mode):
		_write_residue(_econ_snapshot)
	GameState.meta_deepsea_coins = TUT_COINS   # 发教学币, 供商店课买装备


func stage() -> String:
	return str(GameState.get("tutorial_stage")) if GameState != null else ""


## 从某个场景"完成"后, 该去哪。同时把 tutorial_stage 推进到下一阶段。
## here ∈ battle / shop / inventory / codex
func next_scene_after(here: String) -> String:
	if not is_active():
		return MAIN_MENU
	var st := stage()
	match here:
		"team_select":
			# 选龟界面确认 → 进第一把战斗(双路含摆位)
			GameState.tutorial_stage = "match1"
			arm_battle_sandbox()      # 写弱 ghost(跳过 Matchmaking, 不联网)
			return BATTLE
		"battle":
			if st == "match1":
				GameState.tutorial_stage = "shop"
				return SHOP
			elif st == "match2":
				return _finish()          # 第二把打完 → 教学结束
			return MAIN_MENU
		"shop":
			GameState.tutorial_stage = "inventory"
			return INVENTORY
		"inventory":
			GameState.tutorial_stage = "codex"
			return CODEX
		"codex":
			GameState.tutorial_stage = "match2"
			arm_battle_sandbox()      # 第二把也写弱 ghost
			return BATTLE
	return MAIN_MENU


## 教学战斗沙盒: 教学跳过 Matchmaking(不联网), 这里手写一个【弱对手 ghost】,
## 让双路 spawn(_dual_foe_lane 读 dual_ghost) 有合法且必输的对手。
## ★结构照抄 backend.gd make_bot 的 ghost(lane_assign/minions/equipped), 但:
##   每路只 1 只 basic 统领、无小将、无装备、等级 1 → 明显弱于玩家 FIXED_TEAM(必赢)。
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
		# 每路 1 只弱统领, 无小将 → 玩家 3 龟+小将稳赢。
		"lane_assign": {"top": [foe], "bottom": [foe]},
		"minions": {"top": [], "bottom": []},
		"loadouts": {},
		"equipped": {},                       # 对手无装备
		"pet_levels": {foe: 1},               # 等级 1(最低)
		"season_total_battles": 0,
		"season_eggs_killed": 0,
	}


## 教学结束: 关沙盒、置 onboarded、存档、回菜单、不给奖励(奖励在 _settle_season 已被沙盒拦)。
func _finish() -> String:
	if GameState != null:
		# ★还原沙盒经济(币+背包+三统领) → 教学买的装备/花的币全不留存(用户「不获得任何奖励」)。
		#   ★走共用的 `restore_sandbox()`: 放弃路径与残留兜底也调它, **只有一处**知道要还哪几样。
		#   also_save=false —— 下面本来就要 save() 一次。
		restore_sandbox(false)
		GameState.dual_active = false
		GameState.dual_ghost = {}
		GameState.onboarded = true
		GameState.tutorial_active = false
		GameState.tutorial = false
		GameState.tutorial_stage = "done"
		GameState.tutorial_mandatory = false
		GameState.save()
	return MAIN_MENU


## 教学模式下给商店/背包/图鉴挂一个醒目的"下一站"按钮(右上角), 走导演推进。
## 非教学模式什么都不做。here ∈ shop / inventory / codex。
func attach_next_button(host: CanvasItem, here: String) -> void:
	if not is_active():
		return
	# ★只读 _peek_next(不推进 stage) —— 建按钮不能有副作用。
	#   2026-07-23 bug: 第一版这里调了 next_scene_after(会推进 stage), 导致战斗1→MainMenu、
	#   收尾 tutorial_active 没关。建按钮时【绝不改状态】, 只有点了才推进。
	var dest: String = _peek_next(here)
	var label: String = {
		"shop": "装备买好了 → 去背包",
		"inventory": "装好了 → 看看图鉴",
		"codex": "看完了 → 打第二把 ▶",
	}.get(here, "继续 ▶")
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color("#3a1f00"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ffc23c"); sb.set_corner_radius_all(9)
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 9; sb.content_margin_bottom = 9
	btn.add_theme_stylebox_override("normal", sb)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.position = Vector2(-btn.get_minimum_size().x - 220.0, 24.0)
	btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn.pressed.connect(func() -> void:
		var d: String = next_scene_after(here)   # 点了才真推进 + 跳转
		host.get_tree().change_scene_to_file(d))
	var layer := CanvasLayer.new()
	layer.layer = 7000
	layer.add_child(btn)
	host.add_child(layer)
	layer.add_to_group("tut_overlay")   # ★场景 _rebuild 要跳过本组, 否则"下一站"按钮被销毁(买装备后就没了)


## 只读: 从 here 出发下一站是哪(不改 stage)。给 attach_next_button 显示用。
func _peek_next(here: String) -> String:
	var st := stage()
	match here:
		"team_select": return BATTLE
		"shop": return INVENTORY
		"inventory": return CODEX
		"codex": return BATTLE
		"battle": return SHOP if st == "match1" else MAIN_MENU
	return MAIN_MENU


## 一行接入某场景的分步引导: 取当前阶段该用的 key + 是否 mandatory, 挂 TutorialGuide。
## 非教学 / 本阶段无引导 → 返回 null(什么都不挂)。host 需实现 _tutorial_anchor(name)->Rect2 才有高亮。
func attach_guide(host: Node, scene_id: String) -> Node:
	if not is_active():
		return null
	var key := steps_key_for(scene_id)
	if key == "":
		return null
	var mandatory: bool = bool(GameState.get("tutorial_mandatory"))
	var TG = load("res://scripts/scenes/TutorialGuide.gd")
	return TG.attach(host, key, Callable(), mandatory)


## 当前阶段该挂哪套引导步骤(TutorialGuide 的 key)。空=这场景本阶段没有引导。
func steps_key_for(scene: String) -> String:
	if not is_active():
		return ""
	var st := stage()
	if scene == "team_select" and st == "match1_pick":
		return "team_select"      # 选龟界面: 教选龟
	if scene == "battle" and st == "match1":
		return "place"            # 战斗1(双路): 教摆位站位
	if scene == "battle" and st == "match2":
		return "battle"           # 战斗2: 战斗操作引导
	if scene == "shop":
		return "shop"
	if scene == "inventory":
		return "inventory"
	if scene == "codex":
		return "codex"
	return ""
