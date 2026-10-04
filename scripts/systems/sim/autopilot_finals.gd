class_name SimFinalsPilot
extends Node
## autopilot_finals.gd — 周日决赛日的「自动驾驶」: 只在 `SIM_AUTOPILOT` 开着时生效(与 autopilot.gd 同一个开关)。
##
## ★为什么要它(用户 2026-10-03):「整个右屏现在都是你的，我在用左屏」。
##   周日要打就得点「看对阵图 → 自己那一场 → 返回主菜单」, 点按钮要动鼠标, 会干扰用户。
##   ⇒ 模拟窗口自己走完周日流程, 不碰鼠标。只代替**纯机械**的那几下, 不做任何判断(不买东西、不改阵)。
## ★默认彻底关掉: 不带开关时三个 attach 第一行就 return, 不建节点。
## ★每一步都调产品自己的函数(`_open_bracket_map` / `_on_match_opened` / 结算屏同一条换场景),
##   不另写一份流程。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _BR := preload("res://scripts/gamedata/bracket.gd")

static var menu_opens: int = 0      ## 账: 从主菜单进了几次对阵图
static var match_opens: int = 0     ## 账: 在对阵图里点开了几场
static var result_leaves: int = 0   ## 账: 结算屏自动返回了几次

var _host: Node = null
var _mode := ""


static func _spawn(host: Node, mode: String) -> Node:
	if not SimAutopilot.enabled() or host == null:
		return null
	var d := SimFinalsPilot.new()
	d.name = "SimFinalsPilot_" + mode
	d._host = host
	d._mode = mode
	host.add_child.call_deferred(d)
	return d


## 主菜单: 今天是决赛日且已上线 ⇒ 停 3 秒后进对阵图。
static func attach_menu(menu: Node) -> Node:
	var now: int = int(_P2.now_utc())
	if _P2.phase_at_utc(now) != _P2.PHASE_FINALS or not _P2.phase_mode_live(_P2.PHASE_FINALS):
		return null
	return _spawn(menu, "menu")


## 对阵图: 每 2 秒看一次「我自己的、当前轮的、对手已定的那一场」, 有就点开(产品自己判定能不能问)。
static func attach_bracket(map: Node) -> Node:
	return _spawn(map, "bracket")


## 结算屏(决赛日那一局): 停 4 秒后回主菜单 —— 主菜单再自动进对阵图, 形成闭环。
static func attach_result(battle: Node) -> Node:
	if str(battle.get("_last_settle_kind")) != _P2.SETTLE_FINALS:
		return null
	return _spawn(battle, "result")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	match _mode:
		"menu":
			if await _wait(180) and _host.has_method("_open_bracket_map"):
				menu_opens += 1
				print("[AUTOPILOT] finals: 主菜单 → 对阵图")
				_host._open_bracket_map()
		"bracket":
			while await _wait(120):
				_poke_bracket()
		"result":
			if await _wait(240):
				result_leaves += 1
				print("[AUTOPILOT] finals: 结算屏 → 主菜单")
				get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _poke_bracket() -> void:
	var aw = _host.get("_await_match")
	if aw is Vector2i and (aw as Vector2i).x >= 0:
		return                                  # 已经在等这一场的对手了
	var c: Dictionary = _host.cur()
	var n := int(c.get("size", 0))      # parse_finals 的键是 size(不是 n)
	var r := int(c.get("round", 0))
	if n <= 1 or r <= 0:
		return
	for m in range(_BR.matches_in_round(n, r)):
		if _host.should_fetch_opponent(r, m):
			match_opens += 1
			print("[AUTOPILOT] finals: 点开第 %d 轮第 %d 场" % [r, m])
			_host._on_match_opened(r, m)
			return


func _wait(n: int) -> bool:
	for _i in range(maxi(1, n)):
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return is_inside_tree() and is_instance_valid(_host) and _host.is_inside_tree()
