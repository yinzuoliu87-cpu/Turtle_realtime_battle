extends Node
## demo_wraith.gd — 【验收场景 A13】亡魂立绘 + 走路 / 攻击
##
## 用户 2026-08-20:「亡魂也需要建模和动作或者动画立绘」「统一的」「不需要受伤和死亡但走路待机攻击得有」
##
## 此前亡魂是**队色软发光球** —— `_spawn_summon(dead, "wraith", ...)` 没传 `spr_id`,
## 落到 `battle_spawn.gd:776-780` 的兜底。
##
## 配置表:
##   · 我方 2 只带灵物装备的龟(凑够羁绊档位 ⇒ 亡灵机制才生效)
##   · 其中一只**开场就打死** ⇒ 立刻召唤亡魂, 相机就位能直接看
##   · 敌方 1 个假人: 锁血不还手不移动 ⇒ 亡魂会走过去打它(走路 + 攻击两个动作都能看到)
##   · 相机拉近
##
## ★为什么不等自然阵亡: 那要等几十秒还不一定死, 验收时干等 = 我没配好环境。

const SPIRIT_IDS := ["p2eq_032", "p2eq_025"]

var _scn = null
var _t0 := 0.0
var _seen := {}


func _ready() -> void:
	await get_tree().process_frame
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

	var eqs: Array = []
	for i in range(SPIRIT_IDS.size()):
		eqs.append({"id": SPIRIT_IDS[i], "star": 1})

	# 携带者(活着) + 祭品(马上打死 → 召唤亡魂)
	var keeper: Dictionary = _scn._spawn._make_unit("basic", "left", Vector2(cx - 420.0, cy - 90.0))
	keeper["equips"] = eqs.duplicate(true)
	keeper["no_move"] = true
	keeper["no_basic"] = true
	keeper["move_spd"] = 0.0
	keeper["active_skills"] = []
	keeper["deathfloor_until"] = 999999.0
	_scn._units.append(keeper)

	var victim: Dictionary = _scn._spawn._make_unit("basic", "left", Vector2(cx - 300.0, cy))
	victim["equips"] = eqs.duplicate(true)
	victim["base_atk"] = 200.0
	_scn._units.append(victim)

	var foe: Dictionary = _scn._spawn._make_unit("basic", "right", Vector2(cx + 260.0, cy))
	foe["no_move"] = true
	foe["no_basic"] = true
	foe["move_spd"] = 0.0
	foe["active_skills"] = []
	foe["maxHp"] = 99999.0
	foe["hp"] = 99999.0
	foe["deathfloor_until"] = 999999.0
	_scn._units.append(foe)

	## ★羁绊档位必须重算 —— 装备是 _make_unit 之后塞的(同 demo_spirit_slap 那个坑)
	_scn._synergy.apply_all()
	print("=== 【验收场景】亡魂立绘 + 走路 / 攻击 ===")
	print("  ★分母自证: 我方灵物档位 = %d (0 就是没配上, 不会有亡魂)"
		% _scn._spirit_syn._side_tier("left"))

	if _scn._cam != null and is_instance_valid(_scn._cam):
		_scn._cam.fov = 32.0

	# 开场就把祭品打死 → 立刻出亡魂
	await get_tree().process_frame
	victim["hp"] = 1.0
	_scn._kill(victim)
	print("  祭品已阵亡 → 亡魂应当登场; 它会飘向右边的假人并攻击。")
	print("  下面每换一个动作打印一次。")
	print("")
	_t0 = float(Time.get_ticks_msec()) / 1000.0
	set_process(true)


func _process(_dt: float) -> void:
	if _scn == null or not is_instance_valid(_scn):
		return
	for u in _scn._units:
		if not (u is Dictionary) or not u.get("_is_wraith", false):
			continue
		var act: String = str(u.get("anim_action", ""))
		if act == "":
			act = "run(飘行)" if float(u.get("_run_acc", 0.0)) > 5.0 else "idle"
		if not _seen.has(act):
			_seen[act] = true
			print("  [亡魂动作] %-10s (第 %.1f 秒)"
				% [act, float(Time.get_ticks_msec()) / 1000.0 - _t0])
	var el: float = float(Time.get_ticks_msec()) / 1000.0 - _t0
	var want: float = float(int(OS.get_environment("WR_SECS"))) if OS.has_environment("WR_SECS") else 40.0
	if el >= want:
		print("")
		print("  看到的动作: %s" % ", ".join(PackedStringArray(_seen.keys())))
		print("DEMO DONE")
		get_tree().quit(0)
