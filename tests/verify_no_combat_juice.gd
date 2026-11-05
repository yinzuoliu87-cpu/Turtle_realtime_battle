extends Node
## verify_no_combat_juice.gd — 战斗中不屏震、不顿帧(2026-11-04 · 方案书 docs/plans/20261104b-特效对标商业做法.md P3)
## 用户「参考游戏有震屏吗」「全部赶在这版上线」。实量: 云顶战斗录像 40 + 60 秒场景整体平移 0 帧; 我们原来一局每分钟屏震 70~138 次、顿帧 28~60 次。
##   ① 入口: _shake / _add_hitstop 不生效; _shake_force / _hitstop_force(转场节点与竹叶龟拽人专用)生效
##   ② ★真打一局(双路自动战 · 固定种子 · 每帧恰一步): 战斗中屏震 ≤ 3 次、顿帧 ≤ 6 次(只许转场节点 + 竹叶龟拽人);
##      分母: 全场放技能 ≥ 8 次、掉血 ≥ 100 次(没打起来 = 0 次不算过)
##   ③ 静态: scripts/ 下不许再直接写「_hitstop = maxf(」绕开入口
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_no_combat_juice.tscn --quit-after 9000

const RTScene := preload("res://scenes/RealtimeBattle3D.tscn")
const FIGHT_SECONDS := 60.0

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	for kv in [["SHIP", "1"], ["DUALLANE", "1"], ["DL_AUTOFIGHT", "1"], ["TURTLE_SEED", "20261104"]]:
		OS.set_environment(str(kv[0]), str(kv[1]))
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = RTScene.instantiate()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame

	## ① 入口
	s._shake_amp = 0.0
	s._hitstop = 0.0
	s._shake(0.2)
	s._add_hitstop(0.2)
	var off_ok: bool = float(s._shake_amp) == 0.0 and float(s._hitstop) == 0.0
	s._shake_force(0.1)
	s._hitstop_force(0.1)
	var force_ok: bool = float(s._shake_amp) > 0.05 and float(s._hitstop) > 0.05
	_ok("① _shake / _add_hitstop 战斗中不生效; *_force 生效", off_ok and force_ok,
		"关=%s 开=%s" % [str(off_ok), str(force_ok)])
	s._shake_amp = 0.0
	s._hitstop = 0.0

	## ② 真打一局
	s._deterministic = true
	var t0 := -1.0
	var n_sh := 0
	var n_hs := 0
	var n_cast := 0
	var n_hit := 0
	var sh_prev := float(s._shake_t)
	var hs_prev := float(s._hitstop)
	var cd_prev := {}
	var hp_prev := {}
	var frames := 0
	while frames < 8500:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(s):
			break
		var fighting: bool = str(s._dl_state) == "fight"
		var sh := float(s._shake_t)
		var hs := float(s._hitstop)
		if fighting:
			if t0 < 0.0:
				t0 = float(s._t)
			if sh < sh_prev - 1e-6:
				n_sh += 1
			if hs > 0.0 and hs_prev <= 0.0:
				n_hs += 1
			var i := 0
			for u in s._units:
				i += 1
				var cds = u.get("skill_cd", {})
				if cds is Dictionary:
					for k in cds:
						var key := "%d:%s" % [i, str(k)]
						var v := float(cds[k])
						if cd_prev.has(key) and v > float(cd_prev[key]) + 0.5:
							n_cast += 1
						cd_prev[key] = v
				var hk := "%d" % i
				var hp := float(u.get("hp", 0.0))
				if hp_prev.has(hk) and hp < float(hp_prev[hk]) - 0.01:
					n_hit += 1
				hp_prev[hk] = hp
		sh_prev = sh
		hs_prev = hs
		if t0 >= 0.0 and float(s._t) - t0 >= FIGHT_SECONDS:
			break
	var gt: float = (float(s._t) - t0) if t0 >= 0.0 else 0.0
	_ok("② 分母: 真打起来了(战斗 %.0f 秒 · 放技能 %d 次 · 掉血 %d 次)" % [gt, n_cast, n_hit], gt >= 30.0 and n_cast >= 8 and n_hit >= 100)
	_ok("②★战斗中屏震 ≤ 3 次(只许转场节点; 改前一分钟 70~138 次)", n_sh <= 3, "实测 %d 次" % n_sh)
	_ok("②★战斗中顿帧 ≤ 6 次(只许转场节点 + 竹叶龟拽人; 改前一分钟 28~60 次)", n_hs <= 6, "实测 %d 次" % n_hs)

	## ③ 静态: 不许绕开入口直接写顿帧
	## 只抓「往上抬」的写法 maxf(_hitstop, X) / maxf(battle._hitstop, X); 主循环每帧倒计时 maxf(0.0, _hitstop - dt) 不算
	var bad: Array = []
	var n_files := 0
	var re := RegEx.create_from_string("_hitstop\\s*=\\s*maxf\\(\\s*(battle\\.)?_hitstop\\s*,")
	for f in _gd_files("res://scripts"):
		n_files += 1
		var src := FileAccess.get_file_as_string(f)
		if re.search(src) != null:
			bad.append(f.get_file())
	_ok("③ scripts/ 下 %d 个 .gd 没有「_hitstop = maxf(_hitstop, …)」直写(一律走 _hitstop_force 并写理由)" % n_files, n_files > 100 and bad.is_empty(), str(bad))

	print("分母: %d 项" % _n)
	if _fail == 0:
		print("ALL PASS — 战斗中不屏震、不顿帧(只剩转场节点与用户点名的一处)")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _gd_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		var p := dir + "/" + fn
		if d.current_is_dir():
			if not fn.begins_with("."):
				out.append_array(_gd_files(p))
		elif fn.ends_with(".gd"):
			out.append(p)
		fn = d.get_next()
	return out
