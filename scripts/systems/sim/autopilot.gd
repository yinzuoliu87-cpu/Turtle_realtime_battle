class_name SimAutopilot
extends Node
## autopilot.gd — `SIM_AUTOPILOT=1` 只干**一件**事:
##
##   **进了摆位屏, 停一会儿, 然后替玩家按那颗「▶ 开 打」按钮。**
##
## 别的一概不做: 不进商店、不买装备、不选技能、不选阵容、不开下一场。
## 那些是**判断**, 用户点名要人亲自看(2026-09-29:「每次打完你自己看窗口觉得买哪件好就买」)。
## 这里代掉的只是**纯机械**的那一下 —— 一路一次 × 3 路 × 24 场 × 10 窗 = 720 次点击,
## 而那 720 次里没有任何判断。
##
## ══════════════════════════════════════════════════════════════════════
##  ★为什么不直接用 `DL_AUTOFIGHT`(先读了它, 不够用)
## ══════════════════════════════════════════════════════════════════════
## `DL_AUTOFIGHT` 有**两个**落点, 第二个不是我们要的:
##   ① `dual_lane_flow._dl_enter_place()` 开头 —— 直接 `_dl_start_fight()`,
##      **连那颗按钮都不建** ⇒ 玩家从此再也看不到摆位屏、也摆不了位。
##   ② `battle_spawn._spawn_dual_lane()`(:234) —— **跳掉「3 路总览 → 对阵预览」整段演出**,
##      直接加载战场。那是玩家看得见的画面变化, 不是"少按一下键"。
## ⇒ 它是**测试开关**(头注就写着"测试: 跳呈现直接加载战场"), 拿它当自动驾驶
##   等于顺手改掉两处玩家体验。本文件走的是另一条: 摆位屏**照常出现**, 停
##   `DWELL_PLACE` 帧让人看清双方站位, 然后**按产品自己那颗按钮**
##   (`battle._dl_go_btn.pressed` → `_dl_start_fight`)。
##   ★走产品自己的入口(而不是另起一条旁路)才测得到「摆位阶段真的结束了吗」。
##
## ══════════════════════════════════════════════════════════════════════
##  ★不许变成第二个 demo 劫持
## ══════════════════════════════════════════════════════════════════════
## `SHIP=1` 这个开关存在就是因为 demo 劫持让假人永不死、战斗永不结束(CLAUDE.md §4)。
## 本文件的动作清单只有一条: `Button.emit_signal("pressed")`。
## **没有**一处写 `GameState` 的经济字段、**没有**一处碰 `battle._units` / `_battle_rng` /
## 伤害 / 结算。门禁 `verify_autopilot` 逐条量这件事, 不是靠这段注释。
##
## ★在摆位屏停多久**不影响战斗结果**: `_dl_state == "place"` 时 `_fight_on` 恒假
##   (`RealtimeBattle3DScene.gd:2219`) ⇒ `_t` 不涨、单位不 tick。
##   所以「晚 100 帧按」与「立刻按」跑出来是同一场 ——
##   `tests/_probe_autopilot_nochange.gd` 拿逐步指纹逐字比过(588 步 × 8 段, 0 分叉)。
##
## ══════════════════════════════════════════════════════════════════════
##  ★默认必须彻底关掉
## ══════════════════════════════════════════════════════════════════════
## 不带 `SIM_AUTOPILOT` 时 `attach()` 在第二行就 `return null`: 不建节点、不跑协程。
## 判据不是「变量是 false」, 而是**真走一遍摆位屏**, 数 `drive_calls == 0`,
## 再配一条**产品自己的账**: 等够帧数之后 `_dl_state` 仍然是 `"place"`
## (= 摆位阶段没结束, 它还在等人点) —— 只数自己插的计数器等于插一行数一行必绿
## (memory `fb-gate-must-measure-requirement-not-my-hook`)。

const ENV := "SIM_AUTOPILOT"

## 摆位屏停留帧数。纯粹为了**让人看得见**(60 帧 ≈ 1 秒, 够看清双方站位), 与战斗结果无关。
## ★别调大: 一场 3 路 × 24 场 × 10 窗 = 720 次, 每次多停 1 秒就是全场多等 12 分钟。
const DWELL_PLACE := 60

## ─── 账 ───
## ★前两个是**我自己插的计数器**, 单独不成判据; 门禁总要配一条产品自己的账才算数。
##   留着的真实用途: 十个窗口并排跑时, 日志里一眼看得出哪个窗口按了几次。
static var hook_calls: int = 0     ## 产品调过几次钩子(分母: 钩子真的接在流程上)
static var drive_calls: int = 0    ## 真正开车几次(不带开关时必须恰好 0)
static var press_go: int = 0       ## 按过几次「开打」


static func enabled() -> bool:
	## 空白串 = 停用(与 `TURTLE_SUPABASE=" "` 同一个约定) ⇒ 门禁能跑"正常流程"那一半。
	return OS.get_environment(ENV).strip_edges() != ""


## 唯一入口。`dual_lane_flow._dl_enter_place()` 末尾一行接入。
static func attach(host: Node) -> Node:
	hook_calls += 1
	if not enabled():
		return null
	if host == null or not host.is_inside_tree():
		return null   # 门禁/实拍把战斗当子节点挂起来量东西时, 那不是玩家流程
	drive_calls += 1
	var d := SimAutopilot.new()
	d.name = "SimAutopilot_%d" % drive_calls
	d._host = host
	host.add_child(d)
	return d


## 门禁重复跑用: 把账清零。
## ★**测试专用接口**—— 产品侧走不到它。名字带 `_for_test` 是本仓惯例
##   (参 `supabase.gd:_reset_upload_for_test`), 让 `zero_caller_audit` 一眼看出它不是死代码。
##   两个测试用它在用例之间把计数器归零。
# zero-caller-ok: 测试专用重置接口(verify_autopilot / _probe_autopilot_nochange 在用例间归零)
static func reset_ledger_for_test() -> void:
	hook_calls = 0
	drive_calls = 0
	press_go = 0


var _host: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _drive_place()


func _drive_place() -> void:
	## 分母: 「开打」钮真的建起来了吗。(`DL_AUTOFIGHT` 那条路**根本不建它**,
	##   两条路不会互相顶。)
	if not _go_btn_ready():
		_note("place_no_go_btn")
		return
	if not await _wait(DWELL_PLACE):
		return
	if str(_host.get("_dl_state")) != "place":
		_note("place_left_early")   # 人自己先按了, 或者换路了
		return
	if not _go_btn_ready():
		_note("place_go_btn_gone")
		return
	## ★教程摆位第一步「拖动龟调整站位」: 像人一样真拖一下(真输入事件, 走引导暗幕 → 战斗 _unhandled_input
	##   → dual_lane_flow._dl_handle_place_input), 引导条从产品代码收到 unit_dragged 才翻到下一步。
	var td = get_node_or_null("/root/TutorialDirector")
	if td != null and td.is_active() and td.get("_guide") != null and is_instance_valid(td.get("_guide")):
		await _tut_drag()
		if not await _wait(30):
			return
		if str(_host.get("_dl_state")) != "place" or not _go_btn_ready():
			return
	press_go += 1
	_note("press_go")
	(_host._dl_go_btn as Button).emit_signal("pressed")


## 教程: 把第一只能拖的我方龟往右上拖一段(屏幕坐标 → 窗口坐标, 走 Input.parse_input_event 真输入)。
func _tut_drag() -> void:
	var dl = _host.get("_dl_sys")
	if dl == null:
		return
	var r: Rect2 = dl.call("_tut_anchor", "my_unit")
	if r.size.x <= 0.0:
		_note("tut_drag_no_unit")
		return
	var xf: Transform2D = get_viewport().get_final_transform()
	var a: Vector2 = r.get_center()
	var b: Vector2 = a + Vector2(110, -40)
	var steps := 12
	_mouse_btn(xf * a, true)
	await get_tree().process_frame
	for i in range(1, steps + 1):
		var p: Vector2 = xf * a.lerp(b, float(i) / float(steps))
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_mouse_btn(xf * b, false)
	_note("tut_drag")


func _mouse_btn(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)


## 等 n 帧。返回 false = 场景(或我自己)已经不在了 ⇒ **别再碰 `_host`**。
## ★每次 await 回来都重新确认一遍: 切场景/战斗释放都会让 `_host` 变成已释放实例,
##   那时再去调它就是 "Nonexistent function ... on previously freed"
##   (同族纪律 `tools/await_guard_audit.py`)。
func _wait(n: int) -> bool:
	for _i in range(maxi(1, n)):
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return is_inside_tree() and is_instance_valid(_host) and _host.is_inside_tree()


func _go_btn_ready() -> bool:
	if _host == null or not is_instance_valid(_host):
		return false
	var b = _host.get("_dl_go_btn")
	return is_instance_valid(b) and b is Button


func _note(tag: String) -> void:
	print("[AUTOPILOT] ", tag)
