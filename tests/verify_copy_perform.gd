extends Node
## verify_copy_perform.gd — 龟壳「复制」的头顶抄袭图标演出 (2026-08-29)
##
## ══════════════════════════════════════════════════════════════════════
##  由来
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-27:
##   「演出应该是有过头顶怎么样出现图标，然后龟壳释放该技能，
##     放完后出现图标2，然后放第二个技能」
##
## 修之前复制是**什么提示都没有**的：屏幕上突然多出两段别人的技能，玩家既不知道
## 抄到了什么，也看不出第二发是哪来的（它还隔了 0.6 秒凭空出现）。
##
## ══════════════════════════════════════════════════════════════════════
##  这条门禁守什么
## ══════════════════════════════════════════════════════════════════════
## ★判据落在【`_world` 里真的多了一个挂着那张图的 Sprite3D】，
##   **不是**"`copy_steal_icon` 被调过" —— 断言自己插的触发标记 = 插一行数一行必绿
##   (memory [[fb-gate-must-measure-requirement-not-my-hook]])。
## ★而且要**逐张比对贴图路径**：只数"多了几个精灵"守不住"图对不对"
##   （抄了 A 却显示 B 的图标，数量照样对）。
## ★每条断言配分母：候选技能真的构造出来了、图标路径真的解析得到。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_copy_perform.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SkillIcons := preload("res://scripts/gamedata/skill_icons.gd")
const SkillForms := preload("res://scripts/gamedata/skill_forms.gd")
const ShellSystem := preload("res://scripts/systems/skills/shell_system.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## `_world` 里当前挂着的所有 Sprite3D 的贴图路径(去掉没贴图的)。
func _world_tex_paths() -> Array:
	var out: Array = []
	if _s._world == null:
		return out
	for ch in _s._world.get_children():
		if ch is Sprite3D and (ch as Sprite3D).texture != null:
			var rp := str((ch as Sprite3D).texture.resource_path)
			if rp != "":
				out.append(rp)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 龟壳复制·头顶抄袭图标 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── ① SkillIcons 本身 ──
	var p_ice := SkillIcons.path_of("iceFreeze")
	_ok("★① type → 图标解析得到(iceFreeze)", p_ice.ends_with(".png") and ResourceLoader.exists(p_ice), p_ice)
	_ok("★① 不存在的 type 返回空串(不许编一个路径出来)",
		SkillIcons.path_of("__nope__") == "" and SkillIcons.path_of("") == "")
	## ★多形态技能按【当前形态】取 —— 拿"技能池里那一条"会永远显示第一态
	var pu0 := {"ship_summoned": false}
	var pu1 := {"ship_summoned": true}
	var ip0 := SkillIcons.path_of("pirateShipPassive", pu0)
	var ip1 := SkillIcons.path_of("pirateShipPassive", pu1)
	_ok("★★① 多形态技能按当前形态取图标(两态不同)",
		ip0 != "" and ip1 != "" and ip0 != ip1,
		"%s  vs  %s" % [ip0.get_file(), ip1.get_file()])

	# ── ② ★★走真复制入口: `_world` 里真的多出了那两张图 ──
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var sh: Dictionary = _s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
	sh["no_basic"] = true
	sh["no_move"] = true
	sh["energy"] = 999.0
	## 敌人身上【只挂两个确定的技】⇒ 候选池确定, 图标也就确定(不靠随机凑)
	var want := ["iceFreeze", "lineInkBomb"]
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
	foe["active_skills"] = want.duplicate()
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	foe["no_basic"] = true
	foe["no_move"] = true
	_s._units.clear()
	_s._units.append(sh)
	_s._units.append(foe)
	_s._over = false

	var want_paths: Array = []
	for w in want:
		want_paths.append(SkillIcons.path_of(str(w)))
	_ok("★分母: 两个候选技的图标路径都解析得到",
		not want_paths.has("") and want_paths[0] != want_paths[1],
		str(want_paths.map(func(x): return str(x).get_file())))

	var before: Array = _world_tex_paths()
	_s._shell_sys._sk_shell_copy(sh, foe)
	## 第一张是同步出的(在 `_do_skill` 之前调) —— 立刻就该在
	var mid: Array = _world_tex_paths()
	var got1 := 0
	for pth in mid:
		if str(pth) == str(want_paths[0]) or str(pth) == str(want_paths[1]):
			got1 += 1
	_ok("★★② 放技能【之前】头顶就有图标了(第一发)", got1 >= 1,
		"_world 里命中 %d 张; 施放前 %d 个精灵 → 现在 %d 个" % [got1, before.size(), mid.size()])

	## 第二发隔 0.6 秒错峰 —— 用**墙钟**等(CLAUDE.md §3.5: 帧数在无头下每帧只推 1ms,
	## 游戏时钟 _kill 后会冻结)。等到 1.6 秒把两发都覆盖。
	var seen: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1600:
		for pth in _world_tex_paths():
			if str(pth) == str(want_paths[0]) or str(pth) == str(want_paths[1]):
				seen[str(pth)] = true
		await get_tree().process_frame
	_ok("★★② 两发【各自】的图标都真的出现过(逐张比路径, 不只数个数)",
		seen.size() == 2,
		"看到 %d/2: %s" % [seen.size(), str(seen.keys().map(func(x): return str(x).get_file()))])

	# ── ③ 图标会自己收掉(不许一直挂在头顶) ──
	## 弹入 0.16 + 保持 0.55 + 淡出 0.22 ≈ 0.93 秒; 第二发 0.6 秒起 ⇒ 1.6 秒后都该没了。
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 2200:
		await get_tree().process_frame
	var left := 0
	for pth in _world_tex_paths():
		if str(pth) == str(want_paths[0]) or str(pth) == str(want_paths[1]):
			left += 1
	_ok("★③ 图标演完会自己收掉(不许常驻头顶)", left == 0, "还剩 %d 张" % left)

	# ── ④ 没图标的技能: 静默跳过, 不许崩也不许画空框 ──
	## 小将技走 MinionCodex, 那张表里没有 icon 字段 —— 这条路必须能安全走完。
	var n_before := _world_tex_paths().size()
	_s._vfx.copy_steal_icon(sh, "minionBodysurf", 0.3)
	_s._vfx.copy_steal_icon(sh, "__nope_not_a_skill__", 0.3)
	await get_tree().process_frame
	_ok("★④ 查不到图标时静默跳过(不崩·不画空框)",
		_world_tex_paths().size() == n_before,
		"精灵数 %d → %d" % [n_before, _world_tex_paths().size()])

	# ── ⑤ 常量在合理范围(写死高度是 memory 里记的老毛病) ──
	_ok("★⑤ 图标高度在头顶(血条 ~2.0 之上)且没写离谱",
		ShellSystem.COPY_ICON_HEIGHT > 2.0 and ShellSystem.COPY_ICON_HEIGHT < 4.0,
		"%.2f" % ShellSystem.COPY_ICON_HEIGHT)
	_ok("★⑤ 图标尺寸在合理区间(20~90 码)",
		ShellSystem.COPY_ICON_H >= 20.0 and ShellSystem.COPY_ICON_H <= 90.0,
		"%.0f 码" % ShellSystem.COPY_ICON_H)

	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 10:
		print("  [FAIL] ★分母: 断言只有 %d 条(<10) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 复制头顶图标演出" if _fail == 0 else "FAIL x%d — 复制头顶图标演出" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
