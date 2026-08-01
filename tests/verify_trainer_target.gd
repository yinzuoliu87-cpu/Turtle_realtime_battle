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
	var pick: Array = b._targeting._pick_enemies_of(att)
	_ok("定向选取包含普通敌", _has(pick, "en"))
	_ok("★定向不选训龟大师(点4核心)", not _has(pick, "tr"), str(pick.size()))
	_ok("★定向不选组装期机甲(点4: 忍者被动等不锁它)", not _has(pick, "mech"))

	# ② _enemies_of: 真 AOE —— 仍然波及大师(吃1)+ 机甲
	var enem: Array = b._targeting._enemies_of(att)
	_ok("AOE 仍波及普通敌", _has(enem, "en"))
	_ok("★AOE 仍波及训龟大师(龟派气波等溅射·点4)", _has(enem, "tr"))

	# ③ _allies_share_pool: 护盾均分 —— 排除大师与龟蛋、含自己/普通友军
	var al: Array = b._targeting._allies_share_pool(att)
	_ok("均分含自己", _has(al, "att"))
	_ok("均分含普通友军", _has(al, "ally"))
	_ok("★护盾均分排除大师(不占份额·点4)", not _has(al, "trAlly"))

	# ④ 分母: 确认改造真发生 —— 场上有 15 处单取已走闸门
	var src: String = ""
	if Battle is GDScript:
		src = (Battle as GDScript).source_code
	var n_pick: int = src.count("_pick_enemies_of(") + _count_gd("res://scripts/systems", "_pick_enemies_of(")   # 技能已抽到 skills/*, 单取调用点随之外迁·分母跨场景+系统统计(2026-07-25)
	_ok("★分母: _pick_enemies_of 调用点>=15(单取站点已改·含抽出系统)", n_pick >= 15, "实际 %d" % n_pick)

	b.free()
	print("ALL PASS — 训龟大师防误锁(集中闸门)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 递归统计目录下所有 .gd 里 needle 出现次数(技能抽出后调用点跨文件·分母不能只数场景)
func _count_gd(dir: String, needle: String) -> int:
	var total := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := dir + "/" + name
		if d.current_is_dir():
			if name != "." and name != "..":
				total += _count_gd(p, needle)
		elif name.ends_with(".gd"):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				total += f.get_as_text().count(needle)
				f.close()
		name = d.get_next()
	d.list_dir_end()
	return total
