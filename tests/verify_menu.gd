extends Node
## verify_menu.gd — 自证: 主菜单路由完整 + 调试入口不泄漏给玩家 + REVIEW_DEMO 可就地关。
## 跑法: godot --headless --path . res://tests/verify_menu.tscn --quit-after 300
##
## 覆盖:
##  1. 主菜单要跳的场景文件都存在 (打错名字 → 原来静默黑屏)
##  2. 每个子场景都有回主菜单的路径 (无死胡同)
##  3. ★「🛠 调试场」按钮被 gate 在 OS.is_debug_build() / DEVTOOLS 之后 (正式包里玩家看不到)
##  4. ★REVIEW_DEMO 不再是硬 const —— `SHIP=1` 可就地关掉
##  5. ★记录事实: REVIEW_DEMO=true 时 `_unit_level()` 恒返回 1 (真实对局里赛季等级不生效)
##     → 这是【上线前必须 SHIP=1 / 改默认值】的原因, 见轮次账本轮7

const RT = preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 主菜单会跳去的场景 (与 MainMenuScene 里的 _go(...) / _start_battle_flow 对齐)
const MENU_TARGETS := ["Inventory", "Shop", "Settings", "Codex", "Leaderboard", "Record", "TeamSelect", "RealtimeBattle3D"]
## 子场景脚本 → 必须能回主菜单
const SUB_SCENES := [
	"CodexScene", "InventoryScene", "LeaderboardScene", "RecordScene",
	"ShopScene", "SettingsScene", "TeamSelectScene", "MatchmakingScene",
]

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✓ ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ✗ ", name, "  ", detail)


func _ready() -> void:
	print("=== 1. 主菜单目标场景都存在 ===")
	for s in MENU_TARGETS:
		var p := "res://scenes/%s.tscn" % s
		_ok("场景存在: %s" % s, ResourceLoader.exists(p))

	print("=== 2. 子场景无死胡同 (都能回主菜单) ===")
	for s in SUB_SCENES:
		_ok("%s 有返回主菜单" % s, _src_has("res://scripts/scenes/%s.gd" % s, "MainMenu.tscn"))

	print("=== 3. ★调试场入口被 gate (正式包玩家看不到) ===")
	var menu_src := _src("res://scripts/scenes/MainMenuScene.gd")
	_ok("调试场入口有 gate", menu_src.find("OS.is_debug_build() or OS.has_environment(\"DEVTOOLS\")") >= 0)
	_ok("gate 出现在 _debug_arena_entry() 调用之前",
		menu_src.find("OS.is_debug_build()") < menu_src.find("\t\t_debug_arena_entry()"))
	_ok("_go() 有场景存在性守卫", menu_src.find("ResourceLoader.exists(path)") >= 0)

	print("=== 4. ★REVIEW_DEMO 可就地关 (SHIP=1) ===")
	var bat := _src("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("已改为 static func _review_demo()", bat.find("static func _review_demo() -> bool:") >= 0)
	_ok("读 SHIP 环境变量", bat.find("OS.has_environment(\"SHIP\")") >= 0)
	_ok("不再有裸 const REVIEW_DEMO :=", bat.find("const REVIEW_DEMO :=") < 0)
	# ★不要在这里写死 REVIEW_DEMO_DEFAULT 的取值!
	#   2026-07-16 用户把它 true→false(iOS测试包需真实对局), 而本测试仍断言 ==true,
	#   于是 run-tests.sh 从那天起一直是红的、没人发现 —— 直到 07-20 改成自动发现才暴露。
	#   默认值是【会被业务需要反复翻】的旋钮, 断言它的取值等于给自己埋雷。
	#   这里只守【机制不变量】: 三条优先级链路必须在, 且默认路径与常量保持一致。
	_ok("SHIP=1 短路为 false(最高优先级)",
		bat.find("if OS.has_environment(\"SHIP\"):") >= 0)
	_ok("REVIEW=1 强制为 true(次优先, release 包里也能开评审场)",
		bat.find("if OS.has_environment(\"REVIEW\"):") >= 0)
	# 本进程没设 SHIP/REVIEW → 结果必须等于 DEFAULT ∧ is_debug_build(), 与常量当前取值无关
	if not OS.has_environment("SHIP") and not OS.has_environment("REVIEW"):
		_ok("无环境变量时 _review_demo() == DEFAULT ∧ is_debug_build()",
			RT._review_demo() == (RT.REVIEW_DEMO_DEFAULT and OS.is_debug_build()),
			"DEFAULT=%s debug=%s → %s" % [RT.REVIEW_DEMO_DEFAULT, OS.is_debug_build(), RT._review_demo()])

	print("=== 5. ★事实记录: 评审模式会强制全体 Lv1 (含真实双路对局) ===")
	_ok("_unit_level() 里有 `if _review_demo(): return 1`",
		bat.find("if _review_demo():") >= 0 and bat.find("return 1                             # 评审默认 Lv1") >= 0)
	print("     → 所以 REVIEW_DEMO=true 时赛季等级不生效。上线前必须 SHIP=1 或把 REVIEW_DEMO_DEFAULT 改 false。")

	print("")
	if _fail == 0:
		print("ALL PASS — 主菜单路由/调试入口 gate/REVIEW_DEMO 可关")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return ""
	var s := f.get_as_text()
	f.close()
	return s


func _src_has(path: String, needle: String) -> bool:
	return _src(path).find(needle) >= 0
