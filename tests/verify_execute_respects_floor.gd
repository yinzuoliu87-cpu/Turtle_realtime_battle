extends Node
## verify_execute_respects_floor —— 处决不能绕过免死; 特殊护盾必须进血条标准路线(2026-11-06 · 玩家反馈)。
##
## 玩家反馈「无头龟被动为什么被处决」: 亡灵文案「首次受到致命伤害时进入亡灵状态, 5 秒内生命值不会低于 1」。
##   处决不走扣血路径, 弓箭 / 药水 / 暴君之牙 / 精英吞噬都没看免死, 猎人只看了已经进亡灵的情况。
## 玩家反馈「奶油护盾显示肯定有问题」: 071 自画一条 ColorRect, 按 maxHp 算段起点 ⇒ 满血时宽度恒 0, 也不进血条的 _bm。
##   072 在 8 月修过同一个问题, 071 漏了。
## 判据:
##   S ★一整类(静态): scripts/ 里每一处直接把 hp 写成 0 的地方(除两条伤害路径)都先问 execute_saved; 分母 ≥ 4
##   E 真入口: 弓箭 on_hit / 药水 try_behead / 猎人强化箭 / 暴君之牙规则 对无头龟 ⇒ 第一次进亡灵、锁 1 血、不死;
##     亡灵期间再处决 ⇒ 不死; 亡灵过了 ⇒ 真死(分母: 处决本身没被关掉); 普通单位 ⇒ 照常死
##   H ★血条: 满血 + 奶油盾 ⇒ HpBar 的 _bm 变大、_cream > 0(宽度真的 > 0); 与普通盾同时在 ⇒ 总量都算进去; 没盾 ⇒ 不占位
##   R 录流字段表里有 _creamShieldVal(服务器局看的是流, 不录就看不见)
##   B 一整类: SpecialBalance 的每个 key 都有血条读数(镜像 _xxxShieldVal 或登记了理由)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const HpBar := preload("res://scripts/scenes/hp_bar.gd")
const Recorder := preload("res://scripts/systems/stream/stream_recorder.gd")

## 两条伤害路径本身(它们在写 0 之前已经判过免死)、演示台, 不算处决路径。
const HP0_OK := ["scripts/scenes/battle/battle_damage.gd"]

var _s = null
var _fails := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if d == "" else "  " + d))
	if not c:
		_fails += 1


func _walk(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), out)


## 从第 i 行往上找到所在函数开头, 返回这个函数从开头到第 i 行的文本。
func _fn_head(lines: PackedStringArray, i: int) -> String:
	var k := i
	while k > 0 and not lines[k].begins_with("func ") and not lines[k].begins_with("static func "):
		k -= 1
	return "\n".join(lines.slice(k, i + 1))


func _t_static() -> void:
	var files: Array = []
	_walk("res://scripts", files)
	var re := RegEx.new()
	re.compile("\\[\"hp\"\\]\\s*=\\s*0(\\.0)?\\s*($|#)")
	var sites := 0
	var bad: Array = []
	for f in files:
		if str(f).trim_prefix("res://") in HP0_OK:
			continue
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in range(lines.size()):
			var ln := lines[i].strip_edges()
			if ln.begins_with("#") or re.search(ln) == null:
				continue
			sites += 1
			if _fn_head(lines, i).find("execute_saved") < 0:
				bad.append("%s:%d" % [str(f).get_file(), i + 1])
	print("  [分母] 扫 %d 个 .gd, 直接把 hp 写成 0 的处决点 %d 处" % [files.size(), sites])
	_ok("S 分母: 真的扫到了处决点(弓箭 / 药水 / 暴君之牙 / 猎人)", files.size() >= 200 and sites >= 4, "%d 文件 %d 处" % [files.size(), sites])
	_ok("S ★一整类: 每一处都先问 execute_saved", bad.is_empty(), str(bad))
	var elite := FileAccess.get_file_as_string("res://scripts/systems/skills/elite_system.gd")
	_ok("S 精英吞噬(直接 _kill, 不写 hp)也问了", elite.find("execute_saved(tref)") >= 0)


func _mk(id: String, side: String, off: Vector2, hp: float = 1000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	u["crit"] = 0.0
	_s._units.append(u)
	return u


## 一条处决路径对无头龟: 首次 ⇒ 亡灵; 亡灵中 ⇒ 不死; 亡灵过了 ⇒ 死。`hit` = 对目标打一次这条处决。
func _t_path(name: String, hit: Callable) -> void:
	var src := _mk("basic", "left", Vector2(-120.0, 0.0))
	var tgt := _mk("headless", "right", Vector2(120.0, 0.0))
	tgt["hp"] = 10.0
	hit.call(src, tgt)
	_ok("E %s ★无头龟首次被处决 ⇒ 进亡灵、锁 1 血、没死" % name, bool(tgt.get("alive", false)) and bool(tgt.get("undead_used", false))
		and float(tgt["hp"]) >= 1.0 and float(tgt.get("deathfloor_until", 0.0)) > float(_s._t),
		"alive=%s used=%s hp=%.0f" % [str(tgt.get("alive")), str(tgt.get("undead_used")), float(tgt["hp"])])
	hit.call(src, tgt)
	_ok("E %s ★亡灵期间再处决 ⇒ 还活着" % name, bool(tgt.get("alive", false)), "hp=%.0f" % float(tgt["hp"]))
	tgt["deathfloor_until"] = float(_s._t) - 1.0
	tgt["hp"] = 10.0
	hit.call(src, tgt)
	_ok("E %s 分母: 亡灵过了 ⇒ 处决照常生效(不是把处决关了)" % name, not bool(tgt.get("alive", true)))
	var plain := _mk("basic", "right", Vector2(160.0, 40.0))
	plain["hp"] = 10.0
	hit.call(src, plain)
	_ok("E %s 分母: 普通单位照常被处决" % name, not bool(plain.get("alive", true)))
	_s._units.erase(src)
	_s._units.erase(tgt)
	_s._units.erase(plain)


func _t_paths() -> void:
	## 弓箭 / 药水的门槛是羁绊档位: 直接摆档位, 走系统自己的函数体
	_s._synergy._by_side["left"] = {"弓箭": 3, "药水": 3}
	_t_path("猎人强化箭", func(src, tgt) -> void:
		_s._hunter_sys._hunter_exec_arrow_hit(src, tgt))
	_t_path("弓箭【处决】", func(src, tgt) -> void:
		_s._bow_syn.on_hit(src, tgt))
	_t_path("药水【斩首】", func(src, tgt) -> void:
		_s._potion_syn._prey["left"] = tgt
		_s._potion_syn.try_behead(src, tgt))
	_s._synergy._by_side.erase("left")


func _t_bar() -> void:
	var bar = HpBar.new()
	add_child(bar)
	bar.update_state({"maxHp": 1000.0, "hp": 1000.0, "shield": 0.0})
	_ok("H 分母: 满血没盾 ⇒ _bm = 最大生命", absf(float(bar._bm) - 1000.0) < 0.01, str(bar._bm))
	bar.update_state({"maxHp": 1000.0, "hp": 1000.0, "shield": 0.0, "_creamShieldVal": 250.0})
	_ok("H ★满血 + 25% 奶油盾 ⇒ 血条让出位置(_bm 1250, 盾段占 20%)", absf(float(bar._bm) - 1250.0) < 0.01 and float(bar._cream) > 0.0,
		"_bm=%.0f _cream=%.0f" % [float(bar._bm), float(bar._cream)])
	bar.update_state({"maxHp": 1000.0, "hp": 800.0, "shield": 100.0, "_creamShieldVal": 250.0})
	_ok("H ★和普通盾同时在 ⇒ 两段都算进总量", absf(float(bar._bm) - 1150.0) < 0.01, str(bar._bm))
	bar.queue_free()
	_ok("R ★录流字段表里有 _creamShieldVal(服务器局看的是流)", "_creamShieldVal" in Recorder.UKEYS, "表里没有")
	## 一整类: 所有 SpecialBalance 护盾 key 都有血条读数
	var src := FileAccess.get_file_as_string("res://scripts/scenes/hp_bar.gd")
	for k in ["_creamShieldVal", "_ultShieldVal", "_ghostShieldVal", "_manaShieldVal"]:
		_ok("B 血条读 %s" % k, src.find(k) >= 0)
	var fv := FileAccess.get_file_as_string("res://scripts/scenes/battle/food_eq_vfx.gd")
	_ok("B 自画奶油段的旧函数删了(零调用者不留空壳)", fv.find("func cream_bar_update") < 0)


func _ready() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	GameState.test_mode = true
	_t_static()
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_t_paths()
	_t_bar()
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
