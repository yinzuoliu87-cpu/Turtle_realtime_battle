extends Node
## demo_ranged_minion.gd — 【验收场景 A12】远程小将的三个新动作
##
## 用户 2026-08-21:「动作就攻击，技能，走路就好了」「现在这个原画其实也丑，你新搞个原画，生成一套立绘吧」
## ⇒ 远程小将此前**一张动作图都没有**(移动滑行·开火纹丝不动·技能只有特效)。
##
## 怎么跑:
##   <godot> --path . res://tests/demo_ranged_minion.tscn
##   RM_SECS=30   跑多少秒(默认 30)
##
## 配置表:
##   · 我方 1 只【远程小将】—— 从远处起步, 会**走过来**(看走路动画), 进射程后**开火**(看攻击动画),
##     龟能攒满放**追踪火箭**(看技能动画)。龟能起手给满, 不用等。
##   · 敌方 1 个假人: 锁血 99999、不还手、不移动 ⇒ 打不死也不还手, 动作能反复看
##   · 相机拉近
##
## ★为什么假人要锁血又不还手: 打死了就没得看; 还手的话小将会被打断/后退, 动作播一半。

var _scn = null
var _t0 := 0.0
var _seen := {}


func _ready() -> void:
	await get_tree().process_frame
	## ★★验收场景一律强制 `test_mode` —— **窗口模式下它默认是 false, 会写真存档**
	##   (headless 才自动开; 见 `GameState.gd:912`)。2026-08-21 我跑了一次带窗口的 demo,
	##   往 `match_history` 写进一条对局记录, `verify_ui_consistency` 当场红。
	##   铁律: 测试/演示不许污染玩家存档。
	## ★★验收场景【不判胜负】—— `NOVERDICT` 走的是 `_check_end` 里那道守卫。
	##   由来(2026-08-21 用户实拍截图): `demo_spirit_stacks` 阶段①要"场上一个敌人都没有"
	##   才演得出"射程内没敌人就只攒不放", 结果正好撞上「敌方全灭 = 胜利」⇒
	##   演到一半弹出「胜利」结算屏把画面全盖住了。
	## ⚠ 不借 `VFXPREVIEW`: 那个开关会连带开一整套技能预览并改相机 fov(battle_vfx.gd:603)。
	## ⚠ 也不新增成员变量: 上帝文件有行数预算(`tools/arch_budget.py`), 改已有那行守卫净增 0 行。
	OS.set_environment("NOVERDICT", "1")
	var _gs = get_node_or_null("/root/GameState")
	if _gs != null:
		_gs.test_mode = true
	get_tree().root.size = Vector2i(1280, 720)
	_scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame

	for u in _scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	_scn._units.clear()

	var cx: float = _scn.ARENA.position.x + _scn.ARENA.size.x * 0.5
	var cy: float = _scn.ARENA.position.y + _scn.ARENA.size.y * 0.5

	# ── 远程小将(我方) ── 放远一点, 让它先走一段路
	var mn: Dictionary = _scn._spawn._make_unit("__minion__", "left",
		Vector2(cx - 700.0, cy), {"minion": true, "role": "back"})
	mn["deathfloor_until"] = 999999.0
	mn["energy"] = 999.0                      # 龟能给满: 一进射程就能看到技能
	_scn._units.append(mn)

	# ── 假人(敌方) ── 锁血不还手不移动
	var d: Dictionary = _scn._spawn._make_unit("basic", "right", Vector2(cx + 120.0, cy))
	d["no_move"] = true
	d["no_basic"] = true
	d["move_spd"] = 0.0
	d["active_skills"] = []
	d["maxHp"] = 99999.0
	d["hp"] = 99999.0
	d["deathfloor_until"] = 999999.0
	_scn._units.append(d)

	if _scn._cam != null and is_instance_valid(_scn._cam):
		_scn._cam.fov = 34.0

	print("=== 【验收场景】远程小将·三个新动作 ===")
	print("  它会: 走过来(run) → 进射程开火(attack) → 龟能满放追踪火箭(skill)")
	print("  ★分母自证: 动画键 = %s (不是 __minion_back__ 就是没配对)" % _scn._anim_key(mn))
	print("  素材: pets/animations/ranged/{run,attack,skill}.png + idle pets/minion-back.png")
	print("  下面每换一个动作都会打印一次(同一个动作只打印第一次)。")
	print("")
	_t0 = float(Time.get_ticks_msec()) / 1000.0
	set_process(true)


func _process(_dt: float) -> void:
	if _scn == null or not is_instance_valid(_scn):
		return
	for u in _scn._units:
		if not (u is Dictionary) or not u.get("_isMinion", false):
			continue
		## ★走路动画**不写 `anim_action`** —— 它只在 anim_action 为空时接管(见 _update_run_anim),
		##   所以按 anim_action 检测永远看不到 "run"。改成按【实际位移】判, 量产品自己的账。
		var act: String = str(u.get("anim_action", ""))
		if act == "":
			var mv: float = float(u.get("_run_acc", 0.0))
			act = "run(走路)" if mv > 5.0 else "idle"
		if not _seen.has(act):
			_seen[act] = true
			print("  [动作] %-8s  (第 %.1f 秒)"
				% [act, float(Time.get_ticks_msec()) / 1000.0 - _t0])
	var el: float = float(Time.get_ticks_msec()) / 1000.0 - _t0
	var want: float = float(int(OS.get_environment("RM_SECS"))) if OS.has_environment("RM_SECS") else 30.0
	if el >= want:
		print("")
		print("  看到的动作: %s" % ", ".join(PackedStringArray(_seen.keys())))
		print("DEMO DONE")
		get_tree().quit(0)
