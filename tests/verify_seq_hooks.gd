extends Node
## verify_seq_hooks.gd — 新形象 14 只的动作要按技能的真实流程播(2026-11-07)。
##
## 由来: 用户 11-07「他有些技能不是你看上去那么简单…比如说那个无头龟的灵魂打击…后面那个镰刀扫击，那该怎么去弄呢？」。
##   动作接法原来只有一种假设: 技能前摇播一段, 播完回待机。实际很多技能是分段的:
##   灵魂打击放技能只是充能、第 3 下普攻后才挥镰; 万千触须引导 4 秒; 稳定骰子连续突刺; 海盗船第二形态是霰弹…
##   查 11-07 时 FORM 里新增的 10 段**零调用**(表里有、没人播), 所以这条门禁量「真的播起来了」, 不量表里有没有。
## 判据:
##   ① 静态: 14 只的每个 FORM 段都有调用者; `<状态>_end` 段对得上这只龟的持续状态
##   ② 无头: 强化的三下播拍爪段; 第 3 下之后的挥镰(_headless_scythe)在播 scythe 段, 举爪撑到预警结束才扫出
##   ③ 海盗船: 第一形态 / 第二形态放的是两段不同动作
##   ④ 持续状态: 触须 / 连续突刺 / 缩壳 / 滚球 期间在播状态循环, 结束接收招段, 收招段播完回待机
##   ⑤ 释放动作可打断: 打断帧之前普攻不许断(技能本身), 之后能断(否则身体摆着施法姿势滑步)
##   ⑥ 被动一次性段: 不打断技能 / 普攻前摇; 空闲时播得起来
##   ⑦ 飘锤: 糖果龟自己放不再飘(锤子在帧里); 龟壳复制没有这段动作, 仍然飘
##   ⑧ 朝向: 缩头 / 无头换成朝左的新形象后, 不在 ART_FACES_RIGHT 里
##   ⑩ 动作开始不瞬移(用户 11-07「它怎么瞬移到别的地方去了」): 第 1 帧本体与第 0 帧(= 待机)脚底不飘、左右还重叠。
##      那次是糖果龟三段技能的裸帧按带特效舞台的偏移量摆, 一放技能就偏 60 多像素、往上飘 90 像素; 帧条自己的第 0 帧换成待机所以 ② 量不出。
##   ⑨ 被动段走真入口: 不直接调 play_passive, 而是调游戏里真正触发它的函数(闪避结算 / 处决扫描 / 连击 / 吸取 / 登场 / 壁垒收尾 / 接瓶)
const TA := preload("res://scripts/gamedata/turtle_actions.gd")
const NEW14 := ["bubble", "candy", "chest", "crystal", "cyber", "diamond", "dice", "gambler", "headless", "hiding", "hunter", "line", "pirate", "space"]
const SCYTHE_STRIKE_SEC := 1.05   # headless_system._headless_scythe: 蓄力 0.55 + 预警 0.5
const SCYTHE_RAISE_FRAMES := 16   # 举爪段帧数(tools/oneoff/turtle_seq_1107/seq_export.py 排的): 第 16 帧起往下砍

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _src_all() -> String:
	var out := ""
	var stack := ["res://scripts"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			stack.append(d + "/" + sub)
		for f in da.get_files():
			if f.ends_with(".gd") and f != "turtle_actions.gd":
				out += FileAccess.get_file_as_string(d + "/" + f)
	return out


func _sheet(u: Dictionary) -> String:
	var tex = (u.get("anim_sd", {}) as Dictionary).get("tex", null)
	return tex.resource_path if tex != null else ""


## 把渲染步推到这段播完(不靠真实时间: 无头下帧率不定)
func _tick(scn, u: Dictionary, sec: float) -> void:
	var left := sec
	while left > 0.0:
		scn._render._advance_anim(u, 0.05)
		left -= 0.05


func _ready() -> void:
	await get_tree().process_frame
	print("=== 新形象 14 只的动作按技能真实流程播 ===")
	_check_static()
	_check_no_teleport()
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	for u0 in scn._units.duplicate():
		var sp0 = u0.get("sprite", null)
		if sp0 != null and is_instance_valid(sp0):
			sp0.queue_free()
	scn._units.clear()
	var at := Vector2(scn.ARENA.position.x + scn.ARENA.size.x * 0.5, scn.ARENA.position.y + scn.ARENA.size.y * 0.5)
	var mk := func(id: String, i: int) -> Dictionary:
		var u: Dictionary = scn._spawn._make_unit(id, "left", at + Vector2(-400.0 + 70.0 * i, 0.0))
		u["no_move"] = true
		u["no_basic"] = true
		scn._units.append(u)
		return u
	_check_scythe(scn, mk.call("headless", 0))
	_check_pirate(scn, mk.call("pirate", 1))
	_check_states(scn, mk)
	_check_cancel(scn, mk.call("line", 7))
	_check_passive(scn, mk.call("hunter", 8))
	_check_hammer(scn, mk.call("candy", 9), mk.call("shell", 10))
	_check_real_entries(scn, mk, at)
	var cs: Dictionary = (load("res://scripts/scenes/RealtimeBattle3DScene.gd") as Script).get_script_constant_map()
	var right: Array = cs.get("ART_FACES_RIGHT", [])
	_ok("⑧ ★分母: 读到朝向表", not right.is_empty(), str(right))
	var bad: Array = []
	for id in NEW14:
		if right.has(id):
			bad.append(id)
	_ok("⑧ 14 只新形象都朝左, 不登记在 ART_FACES_RIGHT(登记了 = 背对战场)", bad.is_empty(), str(bad))
	if _fail == 0:
		print("ALL PASS (%d 项)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _check_static() -> void:
	var src := _src_all()
	_ok("① ★分母: 读到了 scripts/ 源码", src.length() > 100000, "%d 字" % src.length())
	var nseg := 0
	var orphans: Array = []
	for id in NEW14:
		var forms: Dictionary = TA.FORM.get(id, {})
		var state_names: Array = []
		for r in TA.STATE.get(id, []):
			state_names.append(str(r[0]))
		for seg in forms:
			nseg += 1
			var s := str(seg)
			if s.ends_with("_end") and state_names.has(s.trim_suffix("_end")):
				continue
			if not src.contains("\"%s\"" % s):
				orphans.append("%s.%s" % [id, s])
	_ok("① ★分母: 14 只的一次性段", nseg >= 10, "%d 段" % nseg)
	_ok("① ★★每个一次性段都有调用者(表里有、没人播 = 11-07 那 10 段)", orphans.is_empty(), str(orphans))


func _check_scythe(scn, u: Dictionary) -> void:
	## 三下强化攻击用拍爪, 不用普攻(用户 11-07); 走普攻真入口 AttackRhythm.begin
	var plain := AttackRhythm.sheet_path(scn, u)
	u["headless_soul_stacks"] = 3
	AttackRhythm.begin(scn, u, 0.375)
	_ok("② ★★强化的三下播拍爪段, 不是普攻", _sheet(u).ends_with("headless/soul_attack.png"), _sheet(u))
	_ok("② 拍爪段登记了命中帧(否则按 40% 估, 伤害对不上拍下那一帧)", TurtleActions.HIT.has("pets/animations/headless/soul_attack.png"))
	scn._set_anim_sheet(u, u.get("idle_sd", {}), "", true)
	u["_atk_wind"] = false
	u["headless_soul_stacks"] = 0
	_ok("② 强化结束回普攻", AttackRhythm.sheet_path(scn, u) == plain, plain)
	u["headless_soul_stacks"] = 3
	scn._headless_sys._headless_scythe(u)
	_ok("② ★★第 3 下后在播挥镰段(不是待机, 也不是放技能时那一段)", _sheet(u).ends_with("headless/scythe.png"), _sheet(u))
	var sd: Dictionary = u.get("anim_sd", {})
	var fps: float = float(sd.get("fps", 0.0))
	_ok("② ★分母: 挥镰段有帧率", fps > 0.0, "%.1f 帧/秒" % fps)
	var strike: float = float(SCYTHE_RAISE_FRAMES) / maxf(0.001, fps)
	_ok("② 砍下那一帧对上横扫(差不超过 1 帧)", absf(strike - SCYTHE_STRIKE_SEC) <= 1.0 / maxf(0.001, fps) + 0.001, "%.3f / %.2f 秒" % [strike, SCYTHE_STRIKE_SEC])
	_ok("② 挥镰段比举爪长(后面有砍下和收招)", int(sd.get("frames", 0)) > SCYTHE_RAISE_FRAMES, "%d 帧" % int(sd.get("frames", 0)))
	u["_slam"] = false
	scn._set_anim_sheet(u, u.get("idle_sd", {}), "", true)


func _check_pirate(scn, u: Dictionary) -> void:
	var e0: Array = AttackRhythm.cast_entry(scn, u, "pirateShipPassive")
	_ok("③ ★分母: 第一形态有动作", not e0.is_empty())
	u["ship_summoned"] = true
	var e1: Array = AttackRhythm.cast_entry(scn, u, "pirateShipPassive")
	_ok("③ ★分母: 第二形态有动作", not e1.is_empty())
	_ok("③ ★★第一形态召船、第二形态霰弹, 是两段不同动作", str(e0[0]) != str(e1[0]) and str(e1[0]).ends_with("cast_pirateShipShot.png"),
		"%s / %s" % [str(e0[0]), str(e1[0])])
	u["ship_summoned"] = false


func _check_states(scn, mk: Callable) -> void:
	var rows := [
		["headless", "headlessTendrils", func(u: Dictionary) -> void: u["channel_until"] = scn._t + 99.0, func(u: Dictionary) -> void: u["channel_until"] = 0.0],
		["hiding", "hidingShrink", func(u: Dictionary) -> void: u["channel_until"] = scn._t + 99.0, func(u: Dictionary) -> void: u["channel_until"] = 0.0],
		["dice", "diceDash", func(u: Dictionary) -> void: u["dice_dash_active"] = true, func(u: Dictionary) -> void: u["dice_dash_active"] = false],
		["diamond", "diamondRoll", func(u: Dictionary) -> void: u["roll_active"] = true, func(u: Dictionary) -> void: u["roll_active"] = false],
	]
	var i := 2
	for r in rows:
		var id: String = str(r[0])
		var st: String = str(r[1])
		var u: Dictionary = mk.call(id, i)
		i += 1
		(r[2] as Callable).call(u)
		_tick(scn, u, 0.1)
		_ok("④ ★★%s %s 期间在播状态循环" % [id, st], _sheet(u).ends_with("state_%s.png" % st), _sheet(u))
		(r[3] as Callable).call(u)
		_tick(scn, u, 0.05)
		_ok("④ ★%s 状态结束接收招段" % id, _sheet(u).ends_with("%s_end.png" % st), _sheet(u))
		_tick(scn, u, 3.0)
		var idle_tex = (u.get("idle_sd", {}) as Dictionary).get("tex", null)
		_ok("④ %s 收招播完回待机" % id, _sheet(u) == (idle_tex.resource_path if idle_tex != null else "#") and str(u.get("anim_action", "")) == "", _sheet(u))


func _check_cancel(scn, u: Dictionary) -> void:
	AttackRhythm.cast_begin(scn, u, "lineLink", 0.34)
	_ok("⑤ ★分母: 释放动作播起来了", str(u.get("anim_action", "")) == "cast")
	var cast_sheet := _sheet(u)
	scn._vfx._play_action(u, "attack")
	_ok("⑤ ★打断帧之前普攻不许断(技能本身)", _sheet(u) == cast_sheet, _sheet(u))
	var rel: int = int((TA.CAST["line"]["lineLink"] as Array)[2])
	var fps: float = float((u.get("anim_sd", {}) as Dictionary).get("fps", 1.0))
	u["anim_t"] = float(rel + AttackRhythm.CAST_CANCEL_AFTER) / fps + 0.001
	_ok("⑤ ★打断帧到了 cast_cancelable 变真", AttackRhythm.cast_cancelable(u))
	scn._vfx._play_action(u, "attack")
	_ok("⑤ ★★打断帧之后普攻能断(否则身体摆着施法姿势、普攻没动作)", _sheet(u).ends_with("line/attack.png"), _sheet(u))
	scn._set_anim_sheet(u, u.get("idle_sd", {}), "", true)


func _check_passive(scn, u: Dictionary) -> void:
	AttackRhythm.cast_begin(scn, u, "hunterShot", 0.34)
	var cast_sheet := _sheet(u)
	AttackRhythm.play_passive(scn, u, "dodge")
	_ok("⑥ 技能动作中不被闪避打断", _sheet(u) == cast_sheet and cast_sheet != "", _sheet(u))
	scn._set_anim_sheet(u, u.get("idle_sd", {}), "", true)
	u["_atk_wind"] = true
	AttackRhythm.play_passive(scn, u, "dodge")
	_ok("⑥ 普攻前摇中不被闪避打断", not _sheet(u).ends_with("dodge.png"), _sheet(u))
	u["_atk_wind"] = false
	AttackRhythm.play_passive(scn, u, "dodge")
	_ok("⑥ ★★空闲时闪避动作播得起来", _sheet(u).ends_with("hunter/dodge.png"), _sheet(u))
	AttackRhythm.play_passive(scn, u, "没有这一段")
	_ok("⑥ 没有这一段的什么都不做", _sheet(u).ends_with("hunter/dodge.png"), _sheet(u))
	scn._set_anim_sheet(u, u.get("idle_sd", {}), "", true)


func _check_hammer(scn, candy: Dictionary, shell: Dictionary) -> void:
	_ok("⑦ ★糖果龟有糖果锤动作(锤子在帧里, 不再飘)", not AttackRhythm.cast_entry(scn, candy, "candyHammer").is_empty())
	_ok("⑦ ★龟壳复制糖果锤没有这段动作(飘锤留给它)", AttackRhythm.cast_entry(scn, shell, "candyHammer").is_empty())


func _idle(scn, u: Dictionary) -> void:
	u["_atk_wind"] = false
	scn._set_anim_sheet(u, u.get("idle_sd", {}), "", true)


func _check_real_entries(scn, mk: Callable, at: Vector2) -> void:
	var foe: Dictionary = scn._spawn._make_unit("basic", "right", at + Vector2(120.0, 0.0))
	foe["no_move"] = true
	foe["no_basic"] = true
	scn._units.append(foe)
	## 闪避: 走真伤害结算
	var hunter: Dictionary = mk.call("hunter", 11)
	_idle(scn, hunter)
	hunter["dodge_bonus"] = 1.0
	scn._damage._apply_damage_from(foe, hunter, 10, Color.RED)
	_ok("⑨ ★★闪避结算 ⇒ 猎人播闪避段", _sheet(hunter).ends_with("hunter/dodge.png"), _sheet(hunter))
	hunter["dodge_bonus"] = 0.0
	## 处决箭: 走被动扫描
	_idle(scn, hunter)
	foe["hp"] = float(foe["maxHp"]) * 0.03
	hunter["_hunt_scan_t"] = -99.0
	scn._update_hunter_passive(hunter)
	_ok("⑨ ★★目标进处决线 ⇒ 猎人播处决段", _sheet(hunter).ends_with("hunter/execute.png"), _sheet(hunter))
	foe["hp"] = float(foe["maxHp"])
	foe["_hunt_exec_pending"] = false
	## 连击: 概率拉满, 走真冷却函数
	var gam: Dictionary = mk.call("gambler", 12)
	_idle(scn, gam)
	gam["multi_base"] = 9.0
	scn._gambler_sys._gambler_multi_cd(gam)
	_ok("⑨ ★★多重打击连上 ⇒ 赌神播补牌段", _sheet(gam).ends_with("gambler/multi.png"), _sheet(gam))
	## 登场: 走真登场被动
	for id in ["diamond", "pirate", "gambler"]:
		var u: Dictionary = mk.call(id, 13)
		_idle(scn, u)
		scn._spawn._apply_spawn_passive_one(u)
		_ok("⑨ ★★%s 登场被动 ⇒ 播登场段" % id, _sheet(u).ends_with("%s/enter.png" % id), _sheet(u))
	## 吸取: 走真被动
	var candy: Dictionary = mk.call("candy", 14)
	_idle(scn, candy)
	scn._candy_sys._candy_sweet_drain(candy)
	_ok("⑨ ★★甜蜜吸取 ⇒ 糖果龟播吸取段", _sheet(candy).ends_with("candy/drain.png"), _sheet(candy))
	## 壁垒: 走真收尾
	var cry: Dictionary = mk.call("crystal", 15)
	_idle(scn, cry)
	cry["_bulwark_armed"] = true
	cry["bulwark_until"] = 0.0
	scn._tick_bulwark(cry)
	_ok("⑨ ★★壁垒到期 ⇒ 水晶龟播砸地段", _sheet(cry).ends_with("crystal/barrier_end.png"), _sheet(cry))
	## 接瓶: 瓶子飞行是 tween, 这里只量表和调用点(动作名写错 ⇒ ① 的「有调用者」红)
	_ok("⑨ 朗姆酒接瓶段在表里", (TA.FORM.get("pirate", {}) as Dictionary).has("drink"))
	var rum: Array = TA.CAST["pirate"]["pirateRum"]
	_ok("⑨ 接瓶前不许被普攻打断(打断帧晚于最慢的瓶, 0.34 + 0.7 秒)", rum.size() > 3 and float(rum[3]) / (float(rum[2]) / 0.34) >= 1.0, str(rum))


func _check_no_teleport() -> void:
	var n := 0
	var bad: Array = []
	for id in NEW14:
		var paths: Array = [(TA.ATTACK[id] as Array)[0]]
		for st in (TA.CAST.get(id, {}) as Dictionary):
			paths.append((TA.CAST[id][st] as Array)[0])
		for rel in paths:
			var im: Image = (load("res://assets/sprites/" + str(rel)) as Texture2D).get_image()
			im.convert(Image.FORMAT_RGBA8)
			var S: int = im.get_height() / int((TA.ROWS.get(str(rel), [1, 0]) as Array)[0])
			var r0: Rect2i = im.get_region(Rect2i(0, 0, S, S)).get_used_rect()
			var r1: Rect2i = im.get_region(Rect2i(S, 0, S, S)).get_used_rect()
			n += 1
			var overlap: int = mini(r0.end.x, r1.end.x) - maxi(r0.position.x, r1.position.x)
			if absi(r1.end.y - r0.end.y) > 16 or float(overlap) < float(r0.size.x) * 0.5:
				bad.append("%s 脚底差 %d 重叠 %d/%d" % [str(rel).get_file(), r1.end.y - r0.end.y, overlap, r0.size.x])
	_ok("⑩ ★分母: 量了 14 只的普攻 + 技能帧条", n >= 56, "%d 条" % n)
	_ok("⑩ ★★动作第 1 帧本体没瞬移(脚底差 ≤ 16 像素, 左右重叠 ≥ 一半)", bad.is_empty(), str(bad))
