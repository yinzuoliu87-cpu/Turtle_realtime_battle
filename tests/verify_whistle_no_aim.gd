extends Node
## verify_whistle_no_aim.gd — 口哨「点击就放·不该有拖动」(用户 2026-07-30)
##
## 用户原话:「口哨如果释放的是气波的话是小龟自动朝最近的人放对吧, 也就是3种情况都是点击就放,
##           不应该有拖动」
##
## ★改前的三条路【全都】把口哨当"能瞄"的技能:
##   ① SpellDisc._gui_input 按下就无条件 `_aiming = true` → 冒出方向轮盘, 玩家得拖+松手
##   ② BattleAim._draw_aim_indicator 写的是 `if aim_type == "point" … else 画方向带`,
##      "none" 掉进 else → 战场上给不吃方向的技能画了一条方向带
##   ③ BattleAim._begin_q_aim 只排除了"装了被动", 没排除 aim="none" → 按住 Q 也进瞄准态
##   而口哨的 `_cast_whistle(trainer, _aim)` 参数带下划线 = 【压根没用方向】。
##   拖了半天没有任何影响 = 假的可操作性。
##
## ★断言【走真入口】: 直接喂 InputEventScreenTouch/Drag 给圆盘的 _gui_input,
##   不是"读一读 _aimable 字段" —— 字段对了而输入分支没接上, 照样是白改。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_whistle_no_aim.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DISC := preload("res://scripts/scenes/spell_disc.gd")

# ── 需求字面值: 哪些技能吃方向、哪些不吃(不引用代码常量, 引用就是拿代码跟自己比) ──
const WANT_AIM := {
	"hook": "dir", "glacier": "dir",           # 方向技: 拖动决定朝哪儿
	"fury_potion": "point",                    # 点目标: 拖动幅度决定落点距离
	"hunt_order": "target", "tame": "target",  # 选敌: 拖动决定选谁(_hunt_pick_target/_cast_tame 真读了 aim)
	"whistle": "none",                         # ★口哨: 三种效果都不吃方向
}

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	gs.trainer_skill = "whistle"
	print("=== 口哨: 点击就放·不该有拖动 ===")

	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame

	var tr = null
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			tr = u; break
	if tr == null:
		print("  [FAIL] ★分母: 没有我方大师 —— 后面全是空检查"); _fail += 1; _done(s); return
	_ok("① ★分母: 我方大师装的是口哨",
		str(tr.get("_tr_active", "")) == "whistle",
		"_tr_active=%s / GameState=%s" % [str(tr.get("_tr_active", "")), gs.trainer_active_skill()])

	# ── ② 六个技能的 aim 分类都对(唯一判定 _aim_type_of) ──
	print("")
	var bad := []
	for sid in WANT_AIM.keys():
		var fake := {"_tr_active": sid}
		var got: String = s._aim._aim_type_of(fake)
		if got != str(WANT_AIM[sid]):
			bad.append("%s: 要 %s 得 %s" % [sid, WANT_AIM[sid], got])
	_ok("② 六个主动技的瞄准分类(分母 %d)" % WANT_AIM.size(), bad.is_empty(), "; ".join(bad))
	_ok("② 装了被动(无主动技) → none",
		s._aim._aim_type_of({"_tr_active": ""}) == "none")

	# ── ③ 圆盘: 按下【不进瞄准态】(走真 _gui_input) ──
	print("")
	var disc = s._spell_disc
	if disc == null or not is_instance_valid(disc):
		s._hud._build_spell_disc()
		disc = s._spell_disc
	if disc == null or not is_instance_valid(disc):
		print("  [FAIL] ★分母: 圆盘没建出来 —— ③④ 全是空检查"); _fail += 1; _done(s); return
	disc._cd_frac = 0.0                                  # 就绪(否则输入分支直接 return, 又是空检查)

	var cast_n := [0]
	disc._on_tap = func() -> void: cast_n[0] += 1        # 只记"放了几次", 不真跑技能(避免 CD 干扰)
	var aim_calls := [0]
	disc._on_aim = func(_ph: String, _off: Vector2) -> void: aim_calls[0] += 1

	_press(disc, Vector2(DISC.R, DISC.R))
	_ok("③ 按下: 不进瞄准态(不冒方向轮盘)", disc._aiming == false, "_aiming=%s" % disc._aiming)
	_ok("③ 按下: 不往主场景发 aim 回调", aim_calls[0] == 0, "aim 回调 %d 次" % aim_calls[0])
	_ok("③ 按下: 已武装(松手会放)", disc._tap_armed == true)

	_drag(disc, Vector2(DISC.R + 80.0, DISC.R + 40.0))   # 拖出圆盘一大截 —— 应当完全无效
	_ok("③ ★拖动 90px: 仍不进瞄准态", disc._aiming == false, "_aiming=%s" % disc._aiming)
	_ok("③ ★拖动 90px: 偏移仍为 0(轮盘把手不会跟手)",
		disc._aim_off.length() < 0.001, "_aim_off=%.1f" % disc._aim_off.length())

	_release(disc, Vector2(DISC.R + 80.0, DISC.R + 40.0))
	# ★关键: 拖了 90px 松手, 走的必须是【自动瞄准最近敌】那条(_on_tap), 不是"朝拖动方向施法"(_on_aim cast)
	_ok("③ ★松手: 走自动瞄准(_on_tap), 而不是朝拖动方向施法",
		cast_n[0] == 1 and aim_calls[0] == 0, "tap=%d aim=%d" % [cast_n[0], aim_calls[0]])
	_ok("③ 松手后武装位已清", disc._tap_armed == false)

	# ── ④ 对照组: 换成钩锁, 同样的输入【必须】进瞄准态 ──
	#    没有这组的话, 一个"永远不进瞄准态"的实现也能全绿。
	print("")
	disc.set_aimable(true)
	disc._aiming = false; disc._aim_off = Vector2.ZERO; disc._tap_armed = false
	aim_calls[0] = 0; cast_n[0] = 0
	_press(disc, Vector2(DISC.R, DISC.R))
	_drag(disc, Vector2(DISC.R + 80.0, DISC.R + 40.0))
	_ok("④ ★对照组(方向技): 同样的输入【会】进瞄准态", disc._aiming == true)
	_ok("④ ★对照组: 偏移跟手", disc._aim_off.length() > 80.0, "_aim_off=%.1f" % disc._aim_off.length())
	_release(disc, Vector2(DISC.R + 80.0, DISC.R + 40.0))
	_ok("④ ★对照组: 松手走朝方向施法(_on_aim cast)", cast_n[0] == 0 and aim_calls[0] > 0,
		"tap=%d aim=%d" % [cast_n[0], aim_calls[0]])
	disc.set_aimable(false)

	# ── ⑤ 战场指示器: 口哨不画任何一条 ──
	print("")
	s._disc_aim_dir = Vector2(300.0, 120.0)              # 假装在瞄
	s._aim._clear_aim_indicator()
	s._aim._draw_aim_indicator()
	var n_none: int = s._aim_ind.size()
	_ok("⑤ ★口哨: 一条指示器都不画(方向带/箭头/圈)", n_none == 0, "_aim_ind 有 %d 个节点" % n_none)

	tr["_tr_active"] = "hook"                            # 对照组: 钩锁必须画出来
	s._aim._clear_aim_indicator()
	s._aim._draw_aim_indicator()
	var n_hook: int = s._aim_ind.size()
	_ok("⑤ ★对照组(钩锁): 画得出来(否则上一条是空检查)", n_hook > 0, "_aim_ind 有 %d 个节点" % n_hook)
	s._aim._clear_aim_indicator()
	tr["_tr_active"] = "whistle"

	# ── ⑥ 主场景 aim 回调: 口哨喂 update 也不进瞄准态(绕过圆盘的第二道闸) ──
	print("")
	s._disc_aiming = false
	s._aim._on_spell_aim("update", Vector2(90.0, 40.0))
	_ok("⑥ ★口哨: _on_spell_aim(update) 不点亮 _disc_aiming", s._disc_aiming == false)
	tr["_tr_active"] = "hook"
	s._aim._on_spell_aim("update", Vector2(90.0, 40.0))
	_ok("⑥ ★对照组(钩锁): 会点亮(否则上一条是空检查)", s._disc_aiming == true)
	s._disc_aiming = false
	tr["_tr_active"] = "whistle"

	# ── ⑦ PC 按 Q: 不进瞄准态, 而且【当场就放出去了】 ──
	print("")
	tr["_active_cd"] = 0.0
	s._q_aiming = false
	s._aim._begin_q_aim()
	_ok("⑦ ★口哨按Q: 不进瞄准态(不用按住+松手)", s._q_aiming == false)
	_ok("⑦ ★口哨按Q: 当场就放了(CD 转起来)",
		float(tr.get("_active_cd", 0.0)) > 0.0, "_active_cd=%.1f" % float(tr.get("_active_cd", 0.0)))

	tr["_tr_active"] = "hook"                            # 对照组: 钩锁按 Q 必须【进】瞄准态
	tr["_active_cd"] = 0.0
	s._q_aiming = false
	s._aim._begin_q_aim()
	_ok("⑦ ★对照组(钩锁)按Q: 进瞄准态、按下时【不放】", s._q_aiming == true
		and float(tr.get("_active_cd", 0.0)) <= 0.0)
	s._q_aiming = false

	_done(s)


# 真输入事件(不是直接改字段) —— 圆盘的 _gui_input 收的就是这些。
func _press(disc, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.pressed = true; e.position = at
	disc._gui_input(e)


func _drag(disc, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.position = at
	disc._gui_input(e)


func _release(disc, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.pressed = false; e.position = at
	disc._gui_input(e)


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条)" % _n)
	print("ALL PASS — 口哨点击就放·不该有拖动" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
