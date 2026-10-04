extends Node
## verify_render_writeback.gd — 渲染不许写 sim 会读的字段(回放 v0.19.530 遗留 · 方案书 20261003-跨设备回放 §9.6)
##
## 渲染(`_render_step`)按**真实帧**跑, sim 按固定步长跑。渲染往单位字典写一个 sim 读的键
##   ⇒ sim 结果跟「一帧跑几步 / 渲染了几次」挂钩 ⇒ 同一场重放在别的设备(别的帧率)上分叉。
## 第一例 face_right: 渲染按帧位移写它, sim 在两个兜底分支读它
##   (`hiding_system._sk_minion_rocket` 目标向量 ≤1 码 / `headless_system._headless_scythe` 场上没有敌人)。
##
## 三段:
##   ① 造兜底: 最后一个敌人已死、无头还在被推着走(先右移 1 码/步 ×10, 再左移 0.2 码/步 ×6),
##      然后镰刀收尾 ⇒ 走 `face_right` 兜底。两种渲染节奏(每步渲染 1 次 / 隔一步渲染 2 次)
##      ⇒ 镰刀方向必须相同。修之前: 隔步渲染看到的位移是 0.4 > 0.3 阈值 ⇒ 朝左, 每步渲染朝右 ⇒ 红。
##   ② 真双路对局(固定种子), 两种渲染节奏(每步 1 次 / 0·3·1·0·2·0·1·3 次):
##      · 量渲染实际写了哪些单位键 ⇒ 必须 ⊆ `BattleRender.RENDER_OWNED_KEYS`(且不含 face_right)
##      · 每个 sim 步之后, 全体单位**全部标量键**(去掉渲染自有键)+ 战斗场标量成员 ⇒ 逐步相同
##   ③ 毒化: 每个 sim 步之前把 RENDER_OWNED_KEYS 全换成垃圾值(步后还原没被 sim 改过的), 指纹仍与 ② 逐步相同
##      ⇒ 表里的键 sim 读了也不改结果。
##   ④ 静态: 渲染文件 battle_render.gd 里所有 `u["键"] =` 写入点 ⊆ RENDER_OWNED_KEYS(运行时没走到的写入也管住)。
##
## ★为什么用 det 模式直接调 `_sim_step` + `_render._render_step`: 两者的调用次数比就是要量的那个「节奏」,
##   由本测试精确控制; 一步一采, 循环里不 await(CLAUDE.md §2「每帧采一次抓帧内跃迁」那一行)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RENDER := preload("res://scripts/scenes/battle/battle_render.gd")
const Backend := preload("res://scripts/net/backend.gd")
const PAT_A := [1]
const PAT_B := [0, 3, 1, 0, 2, 0, 1, 3]
const STEPS := 2400
## 不是渲染写的、但本身是**演出随机**(全局 randf, 不进 sim)的键 —— 读者只有 battle_vfx 的呼吸浮动。
## ★它两遍必然不同(全局随机), 从指纹里拿掉; 判据④不管它(不是渲染写的)。
const VISUAL_RANDOM := ["bob_phase"]
## 战斗场成员里渲染自己的东西(相机震屏 / 插值分数 / 本帧 sim 量)与演出表的长度。
const BATTLE_RENDER_MEMBERS := ["_shake_amp", "_shake_t", "_render_alpha", "_sim_accum", "_frame_sim_dt",
	"_last_hit_sfx_t"]

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## ★手跑也不许打真网络: project.godot 里填着真 Supabase 地址; 空白串 = 后端整层停用(与 run-tests.sh 同)
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	print("=== ① 造兜底: 无头镰刀收尾时场上没有敌人 ⇒ 方向取 face_right ===")
	var fa: Dictionary = await _fallback(1)
	var fb: Dictionary = await _fallback(2)
	_ok("分母 · 两遍都真的走了兜底分支(镰刀那一刻最近敌人 = null)", bool(fa["fallback"]) and bool(fb["fallback"]))
	_ok("分母 · 两遍的渲染次数不同(%d / %d)" % [int(fa["renders"]), int(fb["renders"])], int(fa["renders"]) != int(fb["renders"]))
	_ok("★★① 两种渲染节奏 ⇒ 镰刀方向相同(%s / %s)" % [str(fa["aim"]), str(fb["aim"])], fa["aim"] == fb["aim"])
	_ok("★① 方向是「最后一段明显位移」的方向(右; 之后 0.2 码/步的蠕动低于阈值)", fa["aim"] == Vector2.RIGHT, str(fa["aim"]))

	print("=== ② 真双路对局, 两种渲染节奏 ===")
	OS.set_environment("TURTLE_SEED", "515151")
	var a: Dictionary = await _lane(PAT_A, false)
	var b: Dictionary = await _lane(PAT_B, false)
	_ok("分母 · A 每步渲染 1 次, B 有 0 次也有 ≥2 次(%s / %s)" % [str(a["rmin"]) + "~" + str(a["rmax"]), str(b["rmin"]) + "~" + str(b["rmax"])],
		int(a["rmin"]) == 1 and int(a["rmax"]) == 1 and int(b["rmin"]) == 0 and int(b["rmax"]) >= 2)
	_ok("分母 · 两遍都开打过、跑满 %d 步(%d / %d)" % [STEPS, int(a["steps"]), int(b["steps"])],
		bool(a["fought"]) and bool(b["fought"]) and int(a["steps"]) >= STEPS and int(b["steps"]) >= STEPS)
	var w: Dictionary = (a["w"] as Dictionary).duplicate()
	w.merge(b["w"])
	var wk: Array = w.keys()
	wk.sort()
	print("  [量] 渲染写过的单位键 %d 个: %s" % [wk.size(), str(wk)])
	var stray: Array = []
	for k in wk:
		if not k in RENDER.RENDER_OWNED_KEYS:
			stray.append(k)
	_ok("分母 · 渲染确实写过单位键(≥10 个, 否则「⊆ 表」是空检查)", wk.size() >= 10, str(wk.size()))
	_ok("★★② 渲染写的单位键全在 RENDER_OWNED_KEYS 里", stray.is_empty(), "表外: " + str(stray))
	_ok("★② 渲染不写 face_right / last_x", not w.has("face_right") and not w.has("last_x"))
	var cmp: Array = _compare(a["fp"], b["fp"])
	_ok("分母 · 比过的步数 ≥ %d、每步比的键数 ≥ 300(%d 步 / %d 键)" % [STEPS - 10, int(cmp[1]), int(cmp[4])],
		int(cmp[1]) >= STEPS - 10 and int(cmp[4]) >= 300)
	_ok("★★★② 换渲染节奏 ⇒ sim 状态逐步相同: %d/%d 步分叉(首个 %d)" % [int(cmp[0]), int(cmp[1]), int(cmp[2])],
		int(cmp[0]) == 0, str(cmp[3]))

	print("=== ③ 毒化: 每步之前把 RENDER_OWNED_KEYS 换成垃圾值 ===")
	var c: Dictionary = await _lane(PAT_A, true)
	_ok("分母 · 真的毒化过(%d 次键值替换)" % int(c["poisoned"]), int(c["poisoned"]) > 1000)
	var cmp2: Array = _compare(a["fp"], c["fp"])
	_ok("★★③ 渲染自有键全换成垃圾 ⇒ sim 状态逐步相同: %d/%d 步分叉(首个 %d)" % [int(cmp2[0]), int(cmp2[1]), int(cmp2[2])],
		int(cmp2[0]) == 0 and int(cmp2[1]) >= STEPS - 10, str(cmp2[3]))

	print("=== ④ 静态: battle_render.gd 里的单位键写入点 ===")
	var src := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_render.gd")
	var re := RegEx.new()
	re.compile("\\bu\\[\"([A-Za-z_0-9]+)\"\\]\\s*=[^=]")
	var wrote := {}
	for line in src.split("\n"):
		var code: String = line.split("#")[0]
		for m in re.search_all(code):
			wrote[m.get_string(1)] = true
	var stray2: Array = []
	for k in wrote:
		if not k in RENDER.RENDER_OWNED_KEYS:
			stray2.append(k)
	_ok("分母 · battle_render.gd 里找到单位键写入点(%d 个键)" % wrote.size(), wrote.size() >= 5, str(wrote.keys()))
	_ok("★④ battle_render.gd 写的单位键全在 RENDER_OWNED_KEYS 里", stray2.is_empty(), "表外: " + str(stray2))
	_finish()


## ① 造兜底。every: 每 every 步渲染 every 次(1 = 每步 1 次; 2 = 隔一步 2 次 ⇒ 总次数相同但看到的位移是两步的)。
## ★总渲染次数故意不等: every=2 时跳过的那一步不渲染、下一步补 1 次 ⇒ 渲染看到的位移跨两步。
func _fallback(every: int) -> Dictionary:
	OS.set_environment("TURTLE_SEED", "4242")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._debug._edit_place_unit("headless", "left", Vector2(400, 300))
	s._debug._edit_place_unit("basic", "right", Vector2(900, 300))
	s._debug._edit_start_battle()
	var h: Dictionary = {}
	var r: Dictionary = {}
	for u in s._units:
		if str(u.get("id", "")) == "headless" and str(u.get("side", "")) == "left": h = u
		if str(u.get("id", "")) == "basic" and str(u.get("side", "")) == "right": r = u
	var renders := 0
	for i in range(30):
		s._sim_step(s.SIM_DT, false, false)
	## 最后一个敌人死了(场上没有敌人) —— 无头身上不再有战斗目标
	r["alive"] = false
	r["hp"] = 0.0
	h["_has_target"] = false
	var moves: Array = []
	for i in range(10): moves.append(1.0)
	for i in range(6): moves.append(-0.2)
	for i in range(moves.size()):
		h["pos"] = (h["pos"] as Vector2) + Vector2(float(moves[i]), 0.0)
		s._sim_step(s.SIM_DT, false, false)
		if every == 1 or i % 2 == 1:
			s._render._render_step(1.0 / 60.0, false, false)
			renders += 1
	var fallback: bool = s._targeting._nearest_enemy(h) == null
	s._headless_sys._headless_scythe(h)
	var aim: Vector2 = h.get("_scythe_aim", Vector2.ZERO)
	s.queue_free()
	RB.DEBUG_EDIT = false
	await get_tree().process_frame
	await get_tree().process_frame
	return {"aim": aim, "fallback": fallback, "renders": renders}


func _setup_gs() -> void:
	var gs = get_node("/root/GameState")
	gs.reset_dual_lane()
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_phase = "ranked"
	var L: Array = ["ninja", "headless", "hiding"]
	gs.season_leaders = L.duplicate()
	gs.left_team.assign(L)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": L[0]}, {"kind": "minion", "role": "back", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": L[1], "equips": []},
			{"kind": "leader", "slot": 2, "id": L[2], "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
	}
	gs.persistent_equipped = {"ninja": [{"id": "p2eq_001", "star": 2}]}
	gs.loadouts = {"headless": 3}
	gs.season_level = 10
	gs.trainer_skill = "magic_stone"
	var rng := RandomNumberGenerator.new()
	rng.seed = 4262
	gs.dual_ghost = Backend.make_bot(20, rng)
	gs.dual_active = true


static func _prim(v) -> bool:
	match typeof(v):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, TYPE_VECTOR2I:
			return true
	return false


## 单位全部标量键(去掉渲染自有 + 演出随机)+ 战斗场标量成员 + sim 随机流状态。
static func _fp(s) -> Dictionary:
	var out := {}
	var i := 0
	for u in s._units:
		var uk := "%d/%s/%s" % [i, str(u.get("id", "")), str(u.get("side", ""))]
		for k in u:
			if k in RENDER.RENDER_OWNED_KEYS or k in VISUAL_RANDOM:
				continue
			var v = u[k]
			if _prim(v):
				out[uk + "." + str(k)] = v
		i += 1
	for p in s.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(p["name"])
		if n in BATTLE_RENDER_MEMBERS:
			continue
		var v2 = s.get(n)
		if _prim(v2):
			out["B." + n] = v2
	out["B.rng"] = int(s._battle_rng.state)
	return out


static func _poison(v):
	match typeof(v):
		TYPE_BOOL: return not v
		TYPE_INT: return v + 7
		TYPE_FLOAT: return v + 0.123
		TYPE_STRING, TYPE_STRING_NAME: return "__poison__"
		TYPE_VECTOR2: return v + Vector2(3.1, -2.7)
		TYPE_VECTOR3: return v + Vector3(0.31, 0.0, -0.27)
	return null


func _lane(pat: Array, poison: bool) -> Dictionary:
	_setup_gs()
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var fp := {}
	var w := {}
	var st_frames := 0
	var last_state := ""
	var fought := false
	var rmin := 99
	var rmax := 0
	var poisoned := 0
	var i := 0
	while int(s._sim_step_n) < STEPS and i < STEPS * 2:
		var st: String = str(s._dl_state)
		if st != last_state:
			last_state = st
			st_frames = 0
		st_frames += 1
		if (st == "overview" or st == "lane_settle") and st_frames == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and st_frames == 6 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
			fought = true
		var saved: Array = []
		if poison:
			for u in s._units:
				for k in RENDER.RENDER_OWNED_KEYS:
					if u.has(k):
						var pv = _poison(u[k])
						if pv != null:
							saved.append([u, k, u[k], pv])
							u[k] = pv
							poisoned += 1
		s._sim_step(s.SIM_DT, s._hitstop > 0.0, not s._timestop._ts_active.is_empty())
		s._frame_sim_dt = s.SIM_DT
		for e in saved:
			if (e[0] as Dictionary).get(e[1]) == e[3]:
				(e[0] as Dictionary)[e[1]] = e[2]       # sim 没碰它 ⇒ 还原(sim 改过的保留 sim 的)
		fp[int(s._sim_step_n)] = _fp(s)
		var k2: int = int(pat[i % pat.size()])
		if fought:
			rmin = mini(rmin, k2)
			rmax = maxi(rmax, k2)
		for _r in range(k2):
			if poison:          # 毒化那一遍只量 sim 指纹, 不再量渲染写了什么(②已经量过; 省一半时间)
				s._render._render_step(1.0 / 60.0, s._hitstop > 0.0, not s._timestop._ts_active.is_empty())
				continue
			var pre := _unit_prims(s)
			s._render._render_step(1.0 / 60.0, s._hitstop > 0.0, not s._timestop._ts_active.is_empty())
			var post := _unit_prims(s)
			for uk in post:
				var d0: Dictionary = pre.get(uk, {})
				var d1: Dictionary = post[uk]
				for kk in d1:
					if not d0.has(kk) or d0[kk] != d1[kk]:
						w[kk] = true
		i += 1
	var out := {"fp": fp, "w": w, "steps": int(s._sim_step_n), "fought": fought, "rmin": rmin, "rmax": rmax,
		"poisoned": poisoned}
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out


static func _unit_prims(s) -> Dictionary:
	var out := {}
	var i := 0
	for u in s._units:
		var d := {}
		for k in u:
			if _prim(u[k]):
				d[k] = u[k]
		out["%d/%s" % [i, str(u.get("id", ""))]] = d
		i += 1
	return out


## [分叉步数, 比过的步数, 首个分叉步, 首个分叉的键与两边值, 每步键数(取首步)]
func _compare(a: Dictionary, b: Dictionary) -> Array:
	var bad := 0
	var n := 0
	var first := -1
	var det := ""
	var nkeys := 0
	var ks: Array = a.keys()
	ks.sort()
	for st in ks:
		if not b.has(st):
			continue
		var da: Dictionary = a[st]
		var db: Dictionary = b[st]
		n += 1
		nkeys = maxi(nkeys, da.size())
		var same := da.size() == db.size()
		var why := ""
		for k in da:
			if not db.has(k) or db[k] != da[k]:
				same = false
				why = "%s: %s ≠ %s" % [k, str(da[k]), str(db.get(k, "<无>"))]
				break
		if not same:
			bad += 1
			if first < 0:
				first = int(st)
				det = why if why != "" else "键数 %d ≠ %d" % [da.size(), db.size()]
	return [bad, n, first, det, nkeys]


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 渲染不写 sim 读的字段 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
