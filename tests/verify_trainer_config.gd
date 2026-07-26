extends Node

## verify_trainer_config.gd — 训龟大师 配置界面 + loadout 持久化 (用户2026-07-26 更正: 全部技能【五选一·单个】)
## 主菜单独立入口 → TrainerConfig 选形象/单技能 → 写 GameState.trainer_skill + 存盘 → 战斗读取(派生主动/被动)。

const CfgScene := preload("res://scripts/scenes/TrainerConfigScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame

	# ① 场景实例化不崩 + 读到当前 loadout(单技能)
	GameState.trainer_skill = "glacier"
	GameState.trainer_appearance = "default"
	var scene = CfgScene.new()
	add_child(scene)
	await get_tree().process_frame
	_ok("配置场景实例化不崩(分母)", is_instance_valid(scene))
	_ok("★读到当前装配·技能=glacier", scene._sel_skill == "glacier", scene._sel_skill)

	# ② 改选 → 写回 GameState(不真写盘·免污染玩家存档; 存/读字段接线由下面源码断言守)
	scene._sel_skill = "whistle"
	scene._write_loadout()
	_ok("★写回 GameState·技能=whistle", str(GameState.trainer_skill) == "whistle")
	scene.queue_free()

	# ③ ★单技能派生: 选被动→无主动; 选主动→无被动(战斗侧据此接线)
	GameState.trainer_skill = "magic_stone"
	_ok("★选被动·主动派生为空(右下无Q)", GameState.trainer_active_skill() == "")
	_ok("★选被动·被动派生=magic_stone", GameState.trainer_passive_skill() == "magic_stone")
	GameState.trainer_skill = "hook"
	_ok("★选主动·主动派生=hook", GameState.trainer_active_skill() == "hook")
	_ok("★选主动·被动派生为空", GameState.trainer_passive_skill() == "")

	# ④ 接线证据(源码): 主菜单独立按钮 + GameState 存/读含 trainer_skill + 旧档迁移
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MainMenuScene.gd")
	_ok("★主菜单有【训龟大师】独立按钮 → TrainerConfig", mm.contains("训龟大师") and mm.contains('_go("TrainerConfig")'))
	var gs := FileAccess.get_file_as_string("res://autoload/GameState.gd")
	_ok("★GameState 存档含 trainer_skill", gs.contains('"trainer_skill": trainer_skill'))
	_ok("★GameState 读档含 trainer_skill", gs.contains('trainer_skill = str(data.get("trainer_skill"'))
	_ok("★旧档迁移: 读档回退到旧 trainer_active", gs.contains('data.get("trainer_active"'))
	_ok("★TrainerConfig.tscn 存在(_go 找得到)", ResourceLoader.exists("res://scenes/TrainerConfig.tscn"))

	print("ALL PASS — 训龟大师配置界面 + loadout持久化(单技能)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
