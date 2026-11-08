extends Node
## verify_shell_vfx.gd — 龟壳「复制」「暗影俯冲」特效重做(2026-11-08)的门禁。
##
## 用户 11-08:「龟壳的复制和暗影，这些需要优…需要设计。」复制对标塞拉斯 R, 暗影俯冲对标库奇 W
##   (参考逐帧 docs/studies/20261108-龟壳复制参考-塞拉斯R逐帧.md / 20261108-龟壳暗影俯冲参考-库奇W逐帧.md)。
## 演出在 scripts/scenes/battle/shell_vfx.gd, 帧表由 tools/assetgen/build_shell_vfx.py 生成。
##
## 判据全落在【_world 里真的出现的精灵】上(按贴图路径数, 打印分母), 不数我自己插的调用:
##   暗影俯冲(11-08 晚起是「匀速飞 + 沿途火道」, 结算另有 verify_shell_dive_trail):
##             ① 起飞喷焰在起跳点、四格都播到 ②~④ 沿途火团 = 路线等分数 + 1 块(起点、落点各一块), 按路径依次落、在龟壳身后落、
##             间距 = 路程 / 等分数、可见宽 = 火道宽(画面 = 判定)、从落下到消失 = 那一处的燃烧时长、先落先灭、三段都播到;
##             旧的落地区 7 块不再有 ⑤ 命中火球: 被打中的每名敌人身上各一个、和它掉血在同一刻、按龟壳飞过的先后
##             ⑥ 落地没有大爆炸(冲击环 / 火团 / 命中火球以外, 落点附近不许新出现 ≥1.5 米的公告板)
##   复制: 每个原主各一条分节锁链(色阶由龟壳端暗紫到原主端白、粗 → 细 → 细线三态)、旋涡、身后白闪、脚下小圈(挂够)、紫流(三格);
##         甩链月牙; 头顶底框两个且依次出现(图标 1 收了图标 2 才出, 用户 08-27「图标1 收 → 头顶浮出图标2」); 持有态电弧挂到第二发;
##         第二发放出那一刻龟壳闪白(放招闪色)
##   ★结算不变: 两个场景改前改后伤害 / 位置逐步相同(金标 tests/golden/shell_vfx_dmg.json)。
##     暗影俯冲那一段 11-08 晚**有意**改了结算(瞬移 → 匀速飞 + 火道, 用户要的), 那一段按新代码重录; 复制那一段逐字不变。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shell_vfx.tscn
## 重录金标(只在【确实改了结果】时): SHELL_VFX_GOLDEN=write(只录结算轨迹, 不判画面)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SkillIcons := preload("res://scripts/gamedata/skill_icons.gd")
const ShellSystem := preload("res://scripts/systems/skills/shell_system.gd")
const SVfx := preload("res://scripts/scenes/battle/shell_vfx.gd")
const GOLDEN := "res://tests/golden/shell_vfx_dmg.json"
const VFX := "res://assets/sprites/vfx/"
const DIVE_STEPS := 420            # 7 秒: 飞 0.8 + 火道每一处 5 秒 + 余量
const COPY_STEPS := 180            # 3 秒: 两发 + 演出全收

var _n := 0
var _fail := 0
var _s = null
var _write := false
var _glow = null

## 追踪(每个场景重置)
var _trk := {}                     # 节点 iid → 记录(只记 shell-* 帧表与图标)
var _seen := {}                    # 见过的全部 Sprite3D iid
var _new := []                     # 新出现的精灵 [{step, file, size, pos, bb}]
var _icon_paths := []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _arena_of(p: Vector3) -> Vector2:
	return Vector2(p.x / _s.WS + _s._arena_center.x, p.z / _s.WS + _s._arena_center.y)


func _reset_track() -> void:
	_trk = {}
	_new = []
	for ch in _s._world.get_children():
		_seen[ch.get_instance_id()] = true


func _scan(step: int) -> void:
	for ch in _s._world.get_children():
		if not (ch is Sprite3D):
			continue
		var sp := ch as Sprite3D
		var iid := sp.get_instance_id()
		var path := ""
		if sp.texture != null:
			path = str(sp.texture.resource_path)
		## 新出现的精灵: 记出生步 + 【整个存活期里最大的】世界尺寸(爆炸类是从 0.4 倍胀开的, 只量出生那一刻会量小)
		var th: int = sp.texture.get_height() if sp.texture != null else 0
		var sz: float = sp.pixel_size * float(th) / float(maxi(1, sp.vframes)) * absf(sp.scale.y)
		if not _seen.has(iid):
			_seen[iid] = {"step": step, "file": path.get_file(), "glow": sp.texture != null and sp.texture == _glow,
				"size": sz, "pos": _arena_of(sp.position), "bb": sp.billboard != BaseMaterial3D.BILLBOARD_DISABLED}
			_new.append(_seen[iid])
		elif _seen[iid] is Dictionary:
			_seen[iid]["size"] = maxf(float(_seen[iid]["size"]), sz)
		var mine: bool = path.begins_with(VFX + "shell-") or _icon_paths.has(path)
		if not mine or not sp.visible:
			continue
		var r = _trk.get(iid)
		if r == null:
			var tw: int = sp.texture.get_width()
			r = {"file": path.get_file(), "first": step, "last": step, "frames": {}, "kind": str(sp.get_meta("shell_fx", "")),
				"pos": _arena_of(sp.position), "ground": sp.billboard == BaseMaterial3D.BILLBOARD_DISABLED and sp.axis == Vector3.AXIS_Y,
				"w": sp.pixel_size * float(tw) / float(maxi(1, sp.hframes)) / _s.WS, "tier": int(sp.get_meta("tier", -1)),
				"prio": sp.render_priority}
			_trk[iid] = r
		r["last"] = step
		r["frames"][sp.frame] = true
		r["pos_last"] = _arena_of(sp.position)


func _of(file: String, kind: String = "") -> Array:
	var out: Array = []
	for iid in _trk:
		var r: Dictionary = _trk[iid]
		if r["file"] == file and (kind == "" or r["kind"] == kind):
			out.append(r)
	return out


## 结算轨迹: 血量每一次变化 + 每 30 步一次位置。整数化后逐条比。
func _trace(units: Array, step: int, prev: Array, out: Array) -> void:
	for i in range(units.size()):
		var hpi := int(round(float(units[i]["hp"]) * 1000.0))
		if hpi != int(prev[i]):
			out.append("%d|%d|hp|%d" % [step, i, hpi])
			prev[i] = hpi
		if step % 30 == 0:
			var p: Vector2 = units[i]["pos"]
			out.append("%d|%d|pos|%d|%d|%s" % [step, i, int(round(p.x * 100.0)), int(round(p.y * 100.0)), str(units[i]["alive"])])


## 单位立绘的真实渲染优先级(精灵自己的, 与接地材质的取大)。贴地层要比它小才压在龟脚下。
func _unit_prio(u: Dictionary) -> int:
	var spr = u.get("sprite", null)
	if not (spr is Sprite3D):
		return -999
	var pr: int = (spr as Sprite3D).render_priority
	var mo = (spr as Sprite3D).material_override
	if mo is Material:
		pr = maxi(pr, (mo as Material).render_priority)
	return pr


func _unit(id: String, side: String, p: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, p)
	u["no_basic"] = true
	u["no_move"] = true
	u["energy"] = 0.0
	if side == "right":
		u["maxHp"] = 50000.0
		u["hp"] = 50000.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_write = OS.get_environment("SHELL_VFX_GOLDEN") == "write"
	print("=== 龟壳复制 / 暗影俯冲 特效重做 ===%s" % ("  (录金标模式)" if _write else ""))
	## ★固定建场种子: 不设时每次随机选一张地图, 地图上的障碍会把被击退的敌人挤开(11-08 实测: 同一份代码
	##   一会儿过一会儿不过, 中段敌人第 90 步位置差 68 码) —— 判据就跟着地图抽签走了。设了它地图 / 障碍 / 对局随机流都固定。
	OS.set_environment("TURTLE_SEED", "424242")
	_s = RB.new()
	add_child(_s)
	_s._deterministic = true
	for _i in range(30):
		await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	_glow = VfxTex._make_fire_glow_tex()
	var tr_dive: Array = await _run_dive()
	var tr_copy: Array = await _run_copy()

	# ── 结算不变(金标 = 改前的代码录的) ──
	if _write:
		var f := FileAccess.open(GOLDEN, FileAccess.WRITE)
		f.store_string(JSON.stringify({"_说明": "verify_shell_vfx 的结算轨迹金标(血量 ×1000 / 位置 ×100 取整)。只改画面时不许变。copy = 改特效前的代码录; dive = 2026-11-08 晚暗影俯冲改成匀速飞 + 沿途火道(用户要的规则改动)后重录。",
			"dive": tr_dive, "copy": tr_copy}, "\t") + "\n")
		f.close()
		print("  金标已写: dive %d 条 / copy %d 条" % [tr_dive.size(), tr_copy.size()])
	else:
		var g = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
		_ok("★分母: 金标在、两段都有记录", g is Dictionary and (g["dive"] as Array).size() > 20 and (g["copy"] as Array).size() > 10,
			"dive %d / copy %d 条" % [(g["dive"] as Array).size() if g is Dictionary else 0, (g["copy"] as Array).size() if g is Dictionary else 0])
		if g is Dictionary:
			_cmp("★★暗影俯冲: 伤害 / 击退 / 燃烧逐步与改前相同", g["dive"], tr_dive)
			_cmp("★★复制: 两发技能的结算逐步与改前相同", g["copy"], tr_copy)
	_done()


func _cmp(name: String, want: Array, got: Array) -> void:
	var first_diff := -1
	for i in range(maxi(want.size(), got.size())):
		var a: String = str(want[i]) if i < want.size() else "(无)"
		var b: String = str(got[i]) if i < got.size() else "(无)"
		if a != b:
			first_diff = i
			break
	var hp_ev := 0
	for x in got:
		if "|hp|" in str(x):
			hp_ev += 1
	_ok(name, first_diff < 0 and hp_ev > 0,
		("%d 条(其中掉血 %d 次)" % [got.size(), hp_ev]) if first_diff < 0 else
		("第 %d 条不同: 改前 %s / 现在 %s" % [first_diff, str(want[first_diff]) if first_diff < want.size() else "(无)", str(got[first_diff]) if first_diff < got.size() else "(无)"]))


# ═══════════════════════════════ 暗影俯冲 ═══════════════════════════════
func _run_dive() -> Array:
	print("— 暗影俯冲 —")
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var sh := _unit("shell", "left", c + Vector2(-320, 0))
	var e1 := _unit("basic", "right", c + Vector2(-80, 10))      # 路径中段(被冲过)
	var e2 := _unit("basic", "right", c + Vector2(240, -20))     # 落点附近(目标)
	var e3 := _unit("basic", "right", c + Vector2(-60, 260))     # 路径外(不该被打中)
	var units := [sh, e1, e2, e3]
	_s._units.clear()
	_s._units.append_array(units)
	_s._over = false
	_reset_track()
	_s._battle_rng.seed = 424242
	seed(20261108)
	var start: Vector2 = sh["pos"]
	var dir: Vector2 = DetMath.norm(e2["pos"] - start)
	var dest: Vector2 = ArenaShape.clamp_in(start + dir * ShellSystem.DIVE_RANGE, _s.ARENA)
	var trace: Array = []
	var prev: Array = [-1, -1, -1, -1]
	_s._do_skill(sh, e2, "shellShadow")
	var land := -1
	var e1_at := {}
	for k in range(DIVE_STEPS):
		for u in units:
			u["energy"] = 0.0
		if land < 0 and DetMath.dist(sh["pos"], dest) < 1.0:
			land = k
		_scan(k)
		_trace(units, k, prev, trace)
		e1_at[k] = [e1["pos"], e2["pos"], sh["pos"]]
		await get_tree().process_frame
	if _write:
		return trace

	## ① 起飞喷焰
	var ln := _of("shell-dive-launch.png")
	_ok("★① 起飞喷焰出现一次、在起跳点身后、四格都播到(烟 2 → 火球 2)",
		ln.size() == 1 and ln[0]["first"] <= 1 and DetMath.dist(ln[0]["pos"], start) < 40.0 and ln[0]["frames"].size() == 4,
		"分母 %d 个; %s" % [ln.size(), ("第 %d 步出现 / 离起跳点 %.0f 码 / 播到 %s 格" % [ln[0]["first"], DetMath.dist(ln[0]["pos"], start), str(ln[0]["frames"].keys())]) if ln.size() > 0 else ""])

	## ②~④ 沿途火团(路线等分数 + 1 块, 起点、落点各一块)
	var L: float = DetMath.dist(start, dest)
	var np: int = SVfx.patch_count(L)
	var tr := _of("shell-dive-patch.png", "trail")
	tr.sort_custom(func(a, b): return DetMath.dot(a["pos"] - start, dir) < DetMath.dot(b["pos"] - start, dir))
	var appear: Array = []
	var vanish: Array = []
	var behind_ok := true
	var behind_msg := ""
	var phases_ok := true
	for r in tr:
		appear.append(r["first"])
		vanish.append(r["last"])
		var sp: Vector2 = e1_at[int(r["first"])][2]
		var sh_proj: float = DetMath.dot(sp - start, dir)
		var pt_proj: float = DetMath.dot(r["pos"] - start, dir)
		if sh_proj < pt_proj - 10.0:
			behind_ok = false
			behind_msg = "第 %d 步落在 %.0f 码处, 龟壳才到 %.0f 码" % [r["first"], pt_proj, sh_proj]
		var fs: Dictionary = r["frames"]
		if not (fs.has(0) and fs.has(2) and (fs.has(3) or fs.has(4) or fs.has(5) or fs.has(6)) and fs.has(10)):
			phases_ok = false
	_ok("★分母: 沿途火团 %d 块(路线 %.0f 码切 %d 段, 起点落点各一块)" % [np + 1, L, np], tr.size() == np + 1 and np >= 3, "%d 块" % tr.size())
	var distinct := {}
	for a in appear:
		distinct[a] = true
	var sorted_app := appear.duplicate()
	sorted_app.sort()
	_ok("★★② 沿途火团按路径【依次】落(由近到远, 不是同一帧一起出)",
		tr.size() == np + 1 and appear == sorted_app and distinct.size() >= np, "出现步 %s" % str(appear))
	_ok("★★② 每块都在龟壳【身后】落(龟壳飞过那一点之后)", tr.size() == np + 1 and behind_ok, behind_msg)
	_ok("★② 头一块在起点、末一块在落点(±5 码)", tr.size() == np + 1 and DetMath.dist(tr[0]["pos"], start) <= 5.0 and DetMath.dist(tr[-1]["pos"], dest) <= 5.0,
		("头 %.0f / 尾 %.0f 码" % [DetMath.dist(tr[0]["pos"], start), DetMath.dist(tr[-1]["pos"], dest)]) if tr.size() > 0 else "")
	var gap_ok := tr.size() == np + 1
	var gaps: Array = []
	for i in range(1, tr.size()):
		var d: float = DetMath.dist(tr[i]["pos"], tr[i - 1]["pos"])
		gaps.append("%.0f" % d)
		if absf(d - L / float(np)) > 3.0:
			gap_ok = false
	_ok("★② 相邻火团等距(= 路程 / 段数 %.0f 码, ±3)" % (L / float(maxi(1, np))), gap_ok, "间距 %s" % str(gaps))
	var w_ok := tr.size() > 0
	var ws: Array = []
	for r in tr:
		var vis: float = float(r["w"]) * SVfx.PATCH_VIS
		ws.append("%.0f" % vis)
		if absf(vis - ShellSystem.TRAIL_WIDTH) > ShellSystem.TRAIL_WIDTH * 0.02:
			w_ok = false
	_ok("★★② 画面 = 判定: 每块烟晕可见宽 = 火道宽 %.0f 码(±2%%)" % ShellSystem.TRAIL_WIDTH, w_ok, "可见宽 %s" % str(ws))
	var life_ok := tr.size() == np + 1
	var lives: Array = []
	for r in tr:
		var sec: float = float(r["last"] - r["first"] + 1) / 60.0
		lives.append("%.2f" % sec)
		if sec < ShellSystem.BURN_LIFE - 0.05 or sec > ShellSystem.BURN_LIFE + 0.1:
			life_ok = false
	var sorted_van := vanish.duplicate()
	sorted_van.sort()
	_ok("★★④ 每块从落下到消失 = 那一处的燃烧时长 %.1f 秒, 【先落先灭】" % ShellSystem.BURN_LIFE,
		life_ok and vanish == sorted_van, "寿命 %s 秒; 消失步 %s" % [str(lives), str(vanish)])
	_ok("★③ 每块都走完 生成 → 循环 → 消散 三段(第 0/2 格、循环格、末格 10 都播到)", tr.size() == np + 1 and phases_ok)
	_ok("★沿途火团是贴地的(躺平, 不是公告板)", tr.size() > 0 and tr.all(func(r): return r["ground"]))
	## 11-08 实录第一版: 火团与站在上面的龟深度并列, 落点敌人和龟壳整个被火团盖没。贴地层必须比立绘(渲染优先级 0)先画。
	var ground_all := _of("shell-dive-patch.png")
	var up: int = mini(_unit_prio(e1), _unit_prio(e2))
	_ok("★★火团压在龟脚下: 全部火团渲染优先级 < 站在上面的立绘", up > -999 and ground_all.size() == np + 1 and ground_all.all(func(r): return int(r["prio"]) < up),
		"%d 块, 火团优先级 %s / 立绘 %d" % [ground_all.size(), str(ground_all.map(func(r): return r["prio"]).reduce(func(a, x): return a if a.has(x) else a + [x], [])), up])
	_ok("★旧的落地区 7 块火团不再有(燃烧区改成整条火道)", _of("shell-dive-patch.png", "zone").is_empty(), "%d 块" % _of("shell-dive-patch.png", "zone").size())

	## ⑤ 命中火球
	var ht := _of("shell-dive-hit.png")
	var near1 := 0
	var near2 := 0
	var far3 := 0
	var s1 := -1
	var s2 := -1
	for r in ht:
		var at: Array = e1_at[int(r["first"])]
		if DetMath.dist(r["pos"], at[0]) < 30.0:
			near1 += 1
			s1 = r["first"]
		if DetMath.dist(r["pos"], at[1]) < 30.0:
			near2 += 1
			s2 = r["first"]
		if DetMath.dist(r["pos"], e3["pos"]) < 60.0:
			far3 += 1
	_ok("★★⑤ 路径上被打中的两名敌人身上各炸一个命中火球, 路径外那名没有", ht.size() == 2 and near1 == 1 and near2 == 1 and far3 == 0,
		"分母 %d 个: 中段敌 %d / 落点敌 %d / 路径外 %d" % [ht.size(), near1, near2, far3])
	_ok("★⑤ 先飞过的先炸(中段敌早于落点敌)", s1 >= 0 and s2 >= 0 and s1 < s2, "第 %d 步 / 第 %d 步" % [s1, s2])
	## 命中火球和那名敌人掉血在同一刻(±2 步; 火球帧表下一步才显示) —— 不再是「出手那一帧全掉血、火球按预算时刻补放」
	var hp1 := -1
	var hp2 := -1
	for x in trace:
		var f: PackedStringArray = str(x).split("|")
		if f.size() >= 4 and f[2] == "hp" and int(f[0]) > 0:
			if f[1] == "1" and hp1 < 0:
				hp1 = int(f[0])
			if f[1] == "2" and hp2 < 0:
				hp2 = int(f[0])
	_ok("★★⑤ 命中火球与掉血同一刻(中段敌 / 落点敌各 ±2 步), 且都不在出手那一步",
		hp1 > 1 and hp2 > 1 and s1 >= 0 and s2 >= 0 and absi(s1 - hp1) <= 2 and absi(s2 - hp2) <= 2,
		"掉血第 %d / %d 步 · 火球第 %d / %d 步" % [hp1, hp2, s1, s2])

	## ⑥ 落地没有大爆炸
	var big: Array = []
	var shock := 0
	for nn in _new:
		if land < 0 or int(nn["step"]) < land - 1 or int(nn["step"]) > land + 20:
			continue
		if DetMath.dist(nn["pos"], dest) > 250.0:
			continue
		if nn["file"] == "fx-shock-ring.png":
			shock += 1
			continue
		## frost-chill.png = 被火道减速的敌人身上的「冰寒」状态标记(battle_vfx.chill_mark, 挂在 spd_dbf_until 上):
		##   11-08 晚起落点那名是龟壳飞到才开始被烧 + 减速, 标记正好落在落地前后 —— 它是状态, 不是爆炸。
		if nn["bb"] and float(nn["size"]) >= 1.5 and not (nn["file"] in ["shell-dive-hit.png", "shell-dive-patch.png", "frost-chill.png"]):
			big.append("%s %.1f米%s" % [nn["file"] if nn["file"] != "" else "(程序贴图)", float(nn["size"]), " 柔光团" if nn["glow"] else ""])
	_ok("★★⑥ 落地不另放大爆炸(落点附近没有新出现 ≥1.5 米的公告板)", land >= 0 and big.is_empty(),
		"第 %d 步落地; 多出来的: %s" % [land, str(big)])
	_ok("★⑥ 落地仍有原来的冲击环(只删爆炸, 不删冲击环)", shock == 1, "%d 个" % shock)
	return trace


# ═══════════════════════════════ 复制 ═══════════════════════════════
func _run_copy() -> Array:
	print("— 复制 —")
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var sh := _unit("shell", "left", c + Vector2(-220, 0))
	var fa := _unit("basic", "right", c + Vector2(160, -90))
	var fb := _unit("basic", "right", c + Vector2(160, 90))
	fa["active_skills"] = ["iceFreeze"]
	fb["active_skills"] = ["lineInkBomb"]
	var units := [sh, fa, fb]
	_s._units.clear()
	_s._units.append_array(units)
	_s._over = false
	_icon_paths = [SkillIcons.path_of("iceFreeze"), SkillIcons.path_of("lineInkBomb")]
	_reset_track()
	_s._battle_rng.seed = 424242
	seed(20261108)
	var trace: Array = []
	var prev: Array = [-1, -1, -1]
	var at := {}
	_s._do_skill(sh, fa, "shellCopy")
	var flash0 = sh.get("flash_col", null)
	for k in range(COPY_STEPS):
		for u in units:
			u["energy"] = 0.0
		if k == 30:
			sh["flash_col"] = Color(0, 0, 0)        # 清掉第一发的闪色, 之后再出现 = 第二发放出时闪的
		_scan(k)
		_trace(units, k, prev, trace)
		at[k] = [sh["pos"], fa["pos"], fb["pos"]]
		await get_tree().process_frame
	if _write:
		return trace
	var me: Vector2 = sh["pos"]
	var srcs := [fa, fb]

	## ① 甩链月牙
	var cr := _of("shell-copy-crescent.png")
	var cr_ok := cr.size() == 2
	for r in cr:
		if int(r["first"]) > 1 or int(r["last"]) > 14 or DetMath.dist(r["pos"], me) > 60.0 or r["frames"].size() != 2:
			cr_ok = false
	_ok("★① 甩链月牙: 朝每个原主各一道、施放当帧出、两格播完 0.2 秒收", cr_ok, "分母 %d 个" % cr.size())

	## ② 分节锁链
	var lk := _of("shell-copy-link.png")
	var per_src: Array = [0, 0]
	var tiers_ok := true
	var states := {}
	for si in range(2):
		var sp: Vector2 = srcs[si]["pos"]
		var seg: Vector2 = sp - me
		var mine: Array = []
		for r in lk:
			var t: float = DetMath.dot(r["pos"] - me, seg) / DetMath.dot(seg, seg)
			var perp: float = DetMath.dist(r["pos"], me + seg * t)
			if t > 0.0 and t < 1.0 and perp < 15.0:
				mine.append([t, int(r["tier"])])
		per_src[si] = mine.size()
		mine.sort_custom(func(a, b): return a[0] < b[0])
		if mine.size() < 3 or int(mine[0][1]) != 0 or int(mine[-1][1]) != 3:
			tiers_ok = false
		for i in range(1, mine.size()):
			if int(mine[i][1]) < int(mine[i - 1][1]):
				tiers_ok = false
	for r in lk:
		for f in r["frames"]:
			states[int(f) / 4] = true
	_ok("★★② 每个原主各一条分节锁链(沿线一节节, 每条 ≥3 节)", per_src[0] >= 3 and per_src[1] >= 3, "分母: 原主 A %d 节 / 原主 B %d 节" % per_src)
	_ok("★② 锁链色阶: 龟壳端暗紫(0) → 原主端白(3), 由近到远不倒退", tiers_ok)
	_ok("★② 锁链三态都播到: 粗 → 细 → 只剩暗紫细线", states.has(0) and states.has(1) and states.has(2), "态 %s" % str(states.keys()))
	_ok("★② 锁链 0.6 秒内收完(不常驻)", lk.size() > 0 and lk.all(func(r): return int(r["last"]) <= 36))

	## ② 旋涡 / ③ 白闪 / ③ 小圈 / ④ 紫流 —— 每个原主各一套
	var vx := _of("shell-copy-vortex.png")
	var gb := _of("shell-copy-grab.png")
	var mk := _of("shell-copy-mark.png")
	var dr := _of("shell-copy-drain.png")
	var lk_first := 999
	for r in lk:
		lk_first = mini(lk_first, int(r["first"]))
	for si in range(2):
		var o: Dictionary = srcs[si]
		var tag := "原主 %s" % ["A", "B"][si]
		var v := vx.filter(func(r): return DetMath.dist(r["pos"], o["pos"]) < 40.0)
		_ok("★② %s 身上紫旋涡一个(锁链变细那一刻, 约 0.2 秒)" % tag, v.size() == 1 and int(v[0]["first"]) >= 10 and int(v[0]["first"]) <= 16,
			("第 %d 步" % v[0]["first"]) if v.size() == 1 else "%d 个" % v.size())
		var g := gb.filter(func(r): return DetMath.dist(r["pos"], o["pos"]) < 40.0)
		_ok("★③ %s 身后白色圆闪一个(锁链连上之后, 约 0.3 秒; 渲染优先级比立绘低 ⇒ 在身后)" % tag, g.size() == 1 and int(g[0]["first"]) >= lk_first + 12 and int(g[0]["first"]) <= 22 and int(g[0]["prio"]) < _unit_prio(o),
			("第 %d 步(锁链第 %d 步)" % [g[0]["first"], lk_first]) if g.size() == 1 else "%d 个" % g.size())
		var m := mk.filter(func(r): return DetMath.dist(r["pos"], o["pos"]) < 30.0)
		var ml: float = (float(m[0]["last"] - m[0]["first"] + 1) / 60.0) if m.size() == 1 else 0.0
		_ok("★③ %s 脚下「已被偷」小圈: 贴地且压在立绘下、挂到第二发放完之后(≥0.8 秒)、最后收掉" % tag,
			m.size() == 1 and m[0]["ground"] and int(m[0]["prio"]) < _unit_prio(o) and ml >= 0.8 and int(m[0]["last"]) < COPY_STEPS - 1 and m[0]["frames"].has(3),
			("挂 %.2f 秒" % ml) if m.size() == 1 else "%d 个" % m.size())
		var seg2: Vector2 = me - (o["pos"] as Vector2)
		var d := dr.filter(func(r):
			var t: float = DetMath.dot(r["pos"] - o["pos"], seg2) / DetMath.dot(seg2, seg2)
			return t > 0.0 and t < 1.0 and DetMath.dist(r["pos"], o["pos"] + seg2 * t) < 15.0)
		var dfr := {}
		var dfirst := 999
		for r in d:
			dfirst = mini(dfirst, int(r["first"]))
			for f in r["frames"]:
				dfr[int(f)] = true
		_ok("★④ %s → 龟壳 紫流(≥3 段、抓住之后才出、粗 → 粗 → 细锯齿三格都播到)" % tag,
			d.size() >= 3 and g.size() == 1 and dfirst >= int(g[0]["first"]) and dfr.size() == 3,
			"%d 段, 第 %d 步起, 格 %s" % [d.size(), dfirst, str(dfr.keys())])

	## ⑤ 头顶图标 + 底框: 依次(第一个收了第二个才出)
	var bd := _of("shell-copy-badge.png")
	bd.sort_custom(func(a, b): return int(a["first"]) < int(b["first"]))
	_ok("★分母: 头顶底框两个(两发各一个)", bd.size() == 2, "%d 个" % bd.size())
	if bd.size() == 2:
		_ok("★⑤ 第一个底框施放当帧出、弹入 4 格 + 淡出 2 格都播到", int(bd[0]["first"]) <= 1 and bd[0]["frames"].size() == 6, str(bd[0]["frames"].keys()))
		_ok("★★⑤ 依次弹: 第一个底框收了, 第二个(0.6 秒错峰那一发)才出", int(bd[0]["last"]) < int(bd[1]["first"]) and int(bd[1]["first"]) >= 34 and int(bd[1]["first"]) <= 40,
			"第一个 %d~%d 步 / 第二个第 %d 步起" % [bd[0]["first"], bd[0]["last"], bd[1]["first"]])
	var ic: Array = []
	for iid in _trk:
		if _trk[iid]["file"] in [str(_icon_paths[0]).get_file(), str(_icon_paths[1]).get_file()]:
			ic.append(_trk[iid])
	ic.sort_custom(func(a, b): return int(a["first"]) < int(b["first"]))
	_ok("★★⑤ 图标本体也依次(图标 1 收 → 图标 2 出, 用户 08-27 的演出)", ic.size() == 2 and int(ic[0]["last"]) < int(ic[1]["first"]),
		("图标 1 %d~%d 步 / 图标 2 第 %d 步起" % [ic[0]["first"], ic[0]["last"], ic[1]["first"]]) if ic.size() == 2 else "%d 个" % ic.size())

	## ⑥ 持有态电弧
	var ar := _of("shell-copy-arc.png")
	_ok("★⑥ 持有态碎电弧: 龟壳身上一个、抓住那一刻起、挂到第二发放出之后、四格循环、最后收掉",
		ar.size() == 1 and DetMath.dist(ar[0]["pos"], me) < 30.0 and int(ar[0]["first"]) >= 16 and int(ar[0]["first"]) <= 22
			and int(ar[0]["last"]) >= 38 and int(ar[0]["last"]) < 90 and ar[0]["frames"].size() == 4,
		("第 %d~%d 步, 格 %s" % [ar[0]["first"], ar[0]["last"], str(ar[0]["frames"].keys())]) if ar.size() == 1 else "%d 个" % ar.size())

	## ⑦ 放招闪白
	_ok("★⑦ 第一发放出那一刻龟壳闪白(放招闪色)", flash0 is Color and (flash0 as Color).is_equal_approx(SVfx.RELEASE_FLASH), str(flash0))
	var fl = sh.get("flash_col", null)
	_ok("★⑦ 第二发(0.6 秒)放出那一刻龟壳再闪一次", fl is Color and (fl as Color).is_equal_approx(SVfx.RELEASE_FLASH), str(fl))

	## 旧的柔光残影删掉了: 施放 0.4 秒内龟壳身边不许再冒程序柔光团
	var glow_near := 0
	for nn in _new:
		if nn["glow"] and int(nn["step"]) <= 24 and DetMath.dist(nn["pos"], me) < 100.0:
			glow_near += 1
	_ok("★旧版两团柔光残影已删(施放 0.4 秒内龟壳身边没有程序柔光团)", glow_near == 0, "%d 个" % glow_near)
	return trace


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if not _write and _n < 30:
		print("  [FAIL] ★分母: 断言只有 %d 条(<30) —— 有用例没跑到" % _n)
		_fail += 1
	if _write:
		print("ALL PASS — 龟壳特效金标已录")
	else:
		print("ALL PASS — 龟壳复制 / 暗影俯冲特效" if _fail == 0 else "FAIL x%d — 龟壳复制 / 暗影俯冲特效" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
