extends Node

## verify_trainer_config.gd — 训龟大师 配置界面(R1f) + loadout 持久化 (用户2026-07-23)
## 主菜单独立入口 → TrainerConfig 选形象/被动/主动 → 写 GameState + 存盘 → 战斗读取。

const CfgScene := preload("res://scripts/scenes/TrainerConfigScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame

	# ① 场景实例化不崩 + 读到当前 loadout
	GameState.trainer_active = "glacier"
	GameState.trainer_passive = "magic_stone"
	GameState.trainer_appearance = "default"
	var scene = CfgScene.new()
	add_child(scene)
	await get_tree().process_frame
	_ok("配置场景实例化不崩(分母)", is_instance_valid(scene))
	_ok("★读到当前装配·主动=glacier", scene._sel_active == "glacier", scene._sel_active)
	_ok("★读到当前装配·被动=magic_stone", scene._sel_passive == "magic_stone")

	# ② 改选 → 写回 GameState(不真写盘·免污染玩家存档; 存/读字段接线由下面源码断言守)
	scene._sel_active = "whistle"
	scene._sel_passive = ""
	scene._write_loadout()
	_ok("★写回 GameState·主动=whistle", str(GameState.trainer_active) == "whistle")
	_ok("★写回 GameState·被动=空", str(GameState.trainer_passive) == "")
	scene.queue_free()

	# ③ 接线证据(源码): 主菜单独立按钮 + GameState 存/读含 trainer 字段
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MainMenuScene.gd")
	_ok("★主菜单有【训龟大师】独立按钮 → TrainerConfig", mm.contains("训龟大师") and mm.contains('_go("TrainerConfig")'))
	var gs := FileAccess.get_file_as_string("res://autoload/GameState.gd")
	_ok("★GameState 存档含 trainer_active", gs.contains('"trainer_active": trainer_active'))
	_ok("★GameState 读档含 trainer_active", gs.contains('trainer_active = str(data.get("trainer_active"'))
	_ok("★TrainerConfig.tscn 存在(_go 找得到)", ResourceLoader.exists("res://scenes/TrainerConfig.tscn"))

	print("ALL PASS — 训龟大师配置界面 + loadout持久化" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
