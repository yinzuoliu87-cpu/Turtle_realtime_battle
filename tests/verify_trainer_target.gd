extends Node

## verify_trainer_target.gd — 点4: 训龟大师防误锁 集中闸门 (用户 2026-07-23)
## 规则: 定向/单取技能【不选】大师(和组装期机甲), 但真 AOE 循环【仍波及】大师(吃1)。
## 直接 .new() 战斗脚本, 测三个目标原语(不起 3D 场景)。

const Battle := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail: int = 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _has(arr: Array, tag: String) -> bool:
	for o in arr:
		if str(o.get("tag", "")) == tag:
			return true
	return false

func _ready() -> void:
	var b = Battle.new()
	var att   := {"side": "left",  "alive": true, "tag": "att"}
	var en    := {"side": "right", "alive": true, "tag": "en"}
	var tr    := {"side": "right", "alive": true, "is_trainer": true, "tag": "tr"}
	var mech  := {"side": "right", "alive": true, "_assembling": true, "tag": "mech"}   # 组装期机甲(不可选)
	var ally  := {"side": "left",  "alive": true, "tag": "ally"}
	var trAlly := {"side": "left", "alive": true, "is_trainer": true, "tag": "trAlly"}
	b._units = [att, en, tr, mech, ally, trAlly]

	# ① _pick_enemies_of: 定向选取 —— 不选大师、不选组装期机甲
	var pick: Array = b._pick_enemies_of(att)
	_ok("定向选取包含普通敌", _has(pick, "en"))
	_ok("★定向不选训龟大师(点4核心)", not _has(pick, "tr"), str(pick.size()))
	_ok("★定向不选组装期机甲(点4: 忍者被动等不锁它)", not _has(pick, "mech"))

	# ② _enemies_of: 真 AOE —— 仍然波及大师(吃1)+ 机甲
	var enem: Array = b._enemies_of(att)
	_ok("AOE 仍波及普通敌", _has(enem, "en"))
	_ok("★AOE 仍波及训龟大师(龟派气波等溅射·点4)", _has(enem, "tr"))

	# ③ _allies_no_trainer: 护盾均分 —— 排除大师、含自己/普通友军
	var al: Array = b._allies_no_trainer(att)
	_ok("均分含自己", _has(al, "att"))
	_ok("均分含普通友军", _has(al, "ally"))
	_ok("★护盾均分排除大师(不占份额·点4)", not _has(al, "trAlly"))

	# ④ 分母: 确认改造真发生 —— 场上有 15 处单取已走闸门
	var src: String = ""
	if Battle is GDScript:
		src = (Battle as GDScript).source_code
	var n_pick: int = src.count("_pick_enemies_of(")
	_ok("★分母: _pick_enemies_of 调用点>=15(单取站点已改)", n_pick >= 15, "实际 %d" % n_pick)

	b.free()
	print("ALL PASS — 训龟大师防误锁(集中闸门)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
