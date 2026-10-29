extends Node
## verify_reserve_vfx.gd —— 援军小将·四面合围 的演出(scripts/systems/skills/reserve_vfx.gd, 素材 tools/build_reserve_vfx.py)。
##
## 演出模块的契约: 飞行逻辑(ReserveSystem)施法时调 converge_spawn, 每步对每道气波调 wave_trail(位置, 方向)、对目标调 lock_follow,
##   打中调 wave_hit(被打者位置, 方向), 没打中消失调 wave_fizzle。这里按这个契约逐 sim 步喂一段「四道追踪气波合围一个会走的目标」,
##   与 _sim_step 同序(延时队列 → 演出 tween)。不依赖飞行逻辑怎么写(它在另一处改), 只量演出本身。
##
##   A 素材: 7 张表在、帧数 = 代码时长表、零半透明、每帧非空、相邻帧不重复、一次性的末帧 ≤ 峰值 35%(靠掉像素散, 不靠变透明);
##           锁定箭头真的画在 ±x / ±y 轴上; 出现印末帧外沿 ≈ RING_LAST_R; 有方向弹体: 6 帧 40×20、白热在前(+X)、暗尾在后、帧帧不同
##   B 施法那一刻: 凝聚 ×4(立牌、出发点 × 气团高度) / 出现印 ×4(躺平、末帧外沿 = 判定半宽) / 锁定 ×1(躺平、目标脚下、本地 X = 施法者那侧)
##   C 时间: 凝聚 0.20 秒、出现印 0.22 秒收掉; ★锁定切到「收紧」帧那一步 = 气波名义飞到中心那一步(±2 步); 再 0.14 秒收掉; lock_follow 跟上目标
##   D 拖尾: 每道 ≥ 10 团、每团都在「弹体位置 − 方向 × 尾长」(尾焰末端)、排序垫在弹体后面、同一道相邻两团间距 ≥ TRAIL_GAP;
##           顿帧(同一位置连调 10 次)只多 ≤ 1 团
##   E 命中: 四道打一个人 ⇒ 4 朵爆点在四个面(各在被打者「来向」那侧 HIT_BACK 码、朝镜头)、4 种样子、不做深度测试排最上层、0.245 秒收掉;
##           wave_fizzle 在给的位置散一次、0.20 秒收掉
##   F 不碰结算: 只跑演出 90 步, 全部单位字段逐项相同、_battle_rng 状态不变、_pending_shots 不多不少
##   G 不留残节点: 全部跑完, _world 里带 ReserveVfx.TAG 的节点 = 0
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RV := preload("res://scripts/systems/skills/reserve_vfx.gd")
const WAVE_DIR := "res://assets/sprites/vfx/reserve-wave-dir.png"   ## 有方向弹体(归 ReserveSystem 加载; 这里只量素材)
const WAVE_DIR_FRAMES := 6
const WAVE_LEN := ReserveSystem.WAVE_DIR_LEN   ## 喂给 wave_trail 的弹长
const ONCE := {
	"res://assets/sprites/vfx/reserve-gather.png": "GATHER_DURS",
	"res://assets/sprites/vfx/reserve-ring.png": "RING_DURS",
	"res://assets/sprites/vfx/reserve-lock.png": "LOCK",
	"res://assets/sprites/vfx/reserve-trail.png": "TRAIL_DURS",
	"res://assets/sprites/vfx/reserve-fizzle.png": "FIZZLE_DURS",
	"res://assets/sprites/vfx/reserve-hit.png": "HIT_DURS",
}

var _s
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(kind: String, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(kind, side, pos)
	u["no_basic"] = true
	u["no_move"] = true
	return u


## 一个 sim 步里与演出相关的两段, 与 _sim_step 同序: 延时队列 → 演出 tween。
func _step() -> void:
	_s._t += _s.SIM_DT
	_s._ballistics._step_pending_shots(_s.SIM_DT)
	_s._step_sim_tweens(_s.SIM_DT)


## _world 里还活着(没排队删除)的演出节点; kind = "" 全部, 否则名字里带 TAG + kind 的。
func _fx(kind: String = "") -> Array:
	var out: Array = []
	for c in _s._world.get_children():
		if String(c.name).contains(RV.TAG + kind) and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _wpos(p: Vector2, h: float) -> Vector3:
	return _s._world_pos(p, h)


func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _flat_up(sp: Sprite3D) -> float:
	return (sp.global_transform.basis * Vector3.UP).normalized().dot(Vector3.UP)


func _durs(key: String) -> Array:
	if key == "LOCK":
		return RV.lock_durs()
	return {"GATHER_DURS": RV.GATHER_DURS, "RING_DURS": RV.RING_DURS, "TRAIL_DURS": RV.TRAIL_DURS,
		"FIZZLE_DURS": RV.FIZZLE_DURS, "HIT_DURS": RV.HIT_DURS}[key]


func _sum(a: Array) -> float:
	var t := 0.0
	for x in a:
		t += float(x)
	return t


func _snap() -> Array:
	var out: Array = []
	for u in _s._units:
		var d: Dictionary = u
		var keys: Array = d.keys()
		keys.sort()
		var row := PackedStringArray()
		for k in keys:
			var v = d[k]
			var ty: int = typeof(v)
			if ty in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR]:
				row.append("%s=%s" % [str(k), var_to_str(v)])
			elif ty == TYPE_ARRAY:
				row.append("%s#%d" % [str(k), (v as Array).size()])
			elif ty == TYPE_DICTIONARY:
				row.append("%s#%d" % [str(k), (v as Dictionary).size()])
		out.append(";".join(row))
	return out


## 逐帧量一张表: 返回 {semi, counts(按行×帧), dup}。
func _frames_of(img: Image, fw: int, fh: int, nf: int, rows: int) -> Dictionary:
	var semi := 0
	var counts: Array = []
	var dup := 0
	for r in range(rows):
		var prev := PackedByteArray()
		for f in range(nf):
			var cnt := 0
			var bytes := PackedByteArray()
			for y in range(fh):
				for x in range(fw):
					var a: float = img.get_pixel(f * fw + x, r * fh + y).a
					if a > 0.0 and a < 1.0:
						semi += 1
					if a > 0.0:
						cnt += 1
					bytes.append(1 if a > 0.0 else 0)
			counts.append(cnt)
			if f > 0 and bytes == prev:
				dup += 1
			prev = bytes
	return {"semi": semi, "counts": counts, "dup": dup}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	print("=== 援军小将·四面合围 演出 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.set_process(false)
	_s._edit_mode = false
	_s._over = false
	_s._units.clear()
	_s._pending_shots.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var WS: float = _s.WS
	var DT: float = _s.SIM_DT

	# ═══ A 素材 ═══
	print("--- A 素材 ---")
	for path in ONCE:
		var durs: Array = _durs(str(ONCE[path]))
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null or img.is_empty():
			_ok("A %s 在" % path.get_file(), false)
			continue
		var nf: int = durs.size()
		var cell: int = img.get_width() / nf
		var rows: int = img.get_height() / maxi(1, cell)
		_ok("A %s 帧数 = 代码时长表(%d 帧 × %d 行, 方格 %d²)" % [path.get_file(), nf, rows, cell],
			cell * nf == img.get_width() and rows * cell == img.get_height() and rows >= 1)
		var fr: Dictionary = _frames_of(img, cell, cell, nf, rows)
		var counts: Array = fr["counts"]
		var peak := 0
		var empty := 0
		for x in counts:
			peak = maxi(peak, int(x))
			if int(x) == 0:
				empty += 1
		var last_ok := true
		for r in range(rows):
			if int(counts[r * nf + nf - 1]) > int(peak * 0.35):
				last_ok = false
		_ok("A %s 零半透明 · 每帧非空 · 相邻帧不重复 · 末帧 ≤ 峰值 35%%" % path.get_file(),
			int(fr["semi"]) == 0 and empty == 0 and int(fr["dup"]) == 0 and last_ok,
			"半透 %d / 空帧 %d / 重复 %d / 各帧像素 %s" % [int(fr["semi"]), empty, int(fr["dup"]), str(counts)])
	# 有方向的弹体: 6 帧 40×20 循环, 白热(CORE)在前半、最暗的尾在后半, 帧帧不同(动态)
	var wimg := Image.load_from_file(ProjectSettings.globalize_path(WAVE_DIR))
	var fw: int = int(RV.WAVE_DIR_W_PX)
	_ok("A reserve-wave-dir.png %d 帧 × %d×20、宽 > 高" % [WAVE_DIR_FRAMES, fw],
		wimg.get_width() == fw * WAVE_DIR_FRAMES and wimg.get_height() == 20 and fw > wimg.get_height())
	var wf: Dictionary = _frames_of(wimg, fw, wimg.get_height(), WAVE_DIR_FRAMES, 1)
	var front_ok := 0
	for f in range(WAVE_DIR_FRAMES):
		var core_x := 0.0
		var core_n := 0
		var min_x := 999
		for y in range(wimg.get_height()):
			for x in range(fw):
				var col: Color = wimg.get_pixel(f * fw + x, y)
				if col.a <= 0.0:
					continue
				min_x = mini(min_x, x)
				if col.r > 0.95 and col.g > 0.95 and col.b > 0.95:
					core_x += float(x)
					core_n += 1
		if core_n > 0 and core_x / float(core_n) > float(fw) * 0.6 and min_x < fw / 4:
			front_ok += 1
	_ok("A 有方向弹体: 每帧白热都在前(+X 侧)、尾巴拖到后 1/4, 零半透明, 帧帧不同",
		front_ok == WAVE_DIR_FRAMES and int(wf["semi"]) == 0 and int(wf["dup"]) == 0,
		"机头朝 +X 的帧 %d/%d / 半透 %d / 重复 %d" % [front_ok, WAVE_DIR_FRAMES, int(wf["semi"]), int(wf["dup"])])
	# 锁定箭头在 ±x / ±y 轴上(帧 1), 对角线同距离没有
	var limg := Image.load_from_file(ProjectSettings.globalize_path(RV.FX_LOCK))
	var lc: int = limg.get_height()
	var lmid: float = (float(lc) - 1.0) * 0.5
	var on_axis := 0
	var on_diag := 0
	for ax in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
		var got := false
		for rr in range(28, 39):
			var px: Vector2 = Vector2(lmid, lmid) + (ax as Vector2) * float(rr)
			if limg.get_pixel(lc + int(round(px.x)), int(round(px.y))).a > 0.0:
				got = true
		if got:
			on_axis += 1
	for dg in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		for rr in range(28, 39):
			var pd: Vector2 = Vector2(lmid, lmid) + (dg as Vector2).normalized() * float(rr)
			if limg.get_pixel(lc + int(round(pd.x)), int(round(pd.y))).a > 0.0:
				on_diag += 1
	_ok("A 锁定箭头画在 ±x / ±y 四条轴上(代码把 +x 转到施法者那侧)", on_axis == 4 and on_diag == 0, "轴上 %d/4 · 对角线误中 %d" % [on_axis, on_diag])
	var rimg := Image.load_from_file(ProjectSettings.globalize_path(RV.FX_RING))
	var rc: int = rimg.get_height()
	var rmid: float = (float(rc) - 1.0) * 0.5
	var rmax := 0.0
	for y in range(rc):
		for x in range(rc):
			if rimg.get_pixel(4 * rc + x, y).a > 0.0:
				rmax = maxf(rmax, Vector2(x - rmid, y - rmid).length())
	_ok("A 出现印末帧外沿 ≈ RING_LAST_R(%.0f 像素, 代码按它换算成判定半宽)" % RV.RING_LAST_R, absf(rmax - RV.RING_LAST_R) <= 1.0, "实量 %.2f" % rmax)

	# ═══ B 施法那一刻 ═══
	print("--- B 施法那一刻 ---")
	var caster := _mk("basic", "left", c - Vector2(420, 90))
	var foe := _mk("green", "right", c)
	_s._units.append_array([caster, foe])
	var vfx: RefCounted = RV.new(_s)
	var points: Array = _s._reserve_sys.spawn_points(caster, foe)
	var f_dir: Vector2 = DetMath.norm((caster["pos"] as Vector2) - c)
	vfx.converge_spawn(points, c)
	var g: Array = _fx("Gather")
	var rg: Array = _fx("Ring")
	var lk: Array = _fx("Lock")
	_ok("B 节点数: 凝聚 4 / 出现印 4 / 锁定 1", g.size() == 4 and rg.size() == 4 and lk.size() == 1, "%d / %d / %d" % [g.size(), rg.size(), lk.size()])
	var g_ok := 0
	var r_ok := 0
	for p in points:
		for n in g:
			var sp: Sprite3D = n
			if (sp.position - _wpos(p, RV.WAVE_H)).length() < 0.001 and sp.billboard == BaseMaterial3D.BILLBOARD_ENABLED \
					and sp.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and is_equal_approx(sp.pixel_size, RV.TEXEL * WS):
				g_ok += 1
		for n in rg:
			var sp2: Sprite3D = n
			var outer: float = sp2.pixel_size * RV.RING_LAST_R / WS
			if _xz(sp2.position, _wpos(p, 0.0)) < 0.001 and _flat_up(sp2) > 0.999 \
					and absf(outer - ReserveConsts.WAVE_HALF_W) < 0.01 and sp2.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST:
				r_ok += 1
	_ok("B 凝聚: 每个出发点一个, 立牌、在气团高度、NEAREST、一像素 = %.0f 码" % RV.TEXEL, g_ok == 4, "%d/4" % g_ok)
	_ok("B 出现印: 每个出发点一个, 躺平(世界法线·上 > 0.999)、末帧外沿 = 判定半宽 %.0f 码" % ReserveConsts.WAVE_HALF_W, r_ok == 4, "%d/4" % r_ok)
	var lock: Sprite3D = lk[0] if lk.size() == 1 else null
	if lock != null:
		var lx: Vector3 = lock.global_transform.basis.x.normalized()
		_ok("B 锁定: 在目标脚下、躺平、本地 X 指向施法者那侧(= 第一道气波来的方向)",
			_xz(lock.position, _wpos(c, 0.0)) < 0.001 and lock.position.y < 0.1
				and _flat_up(lock) > 0.999 and lx.dot(Vector3(f_dir.x, 0.0, f_dir.y)) > 0.999,
			"法线·上 %.3f / X·施法者方向 %.3f" % [_flat_up(lock), lx.dot(Vector3(f_dir.x, 0.0, f_dir.y))])
	else:
		_ok("B 锁定建出来了", false)

	# ═══ C / D / E: 四道追踪气波, 目标往下走 ═══
	print("--- C 时间 / D 拖尾 / E 命中 ---")
	var wp: Array = points.duplicate()
	var alive: Array = [true, true, true, true]
	var last_dir: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var t_gather := -1.0
	var t_ring := -1.0
	var t_lock7 := -1.0
	var t_lock_gone := -1.0
	var t_arrive_nom: float = ReserveConsts.WAVE_HOLD + ReserveConsts.WAVE_RADIUS / ReserveConsts.WAVE_SPEED
	var lock_lag := 0.0
	var puff_seen: Dictionary = {}
	var puff_by_wave: Array = [[], [], [], []]
	var puff_bad := 0
	var puff_sort_bad := 0
	var hits: Array = []                 # [第几道, 命中那刻目标位置, 方向]
	var hit_nodes: Dictionary = {}       # instance_id → [节点, 第一次看到那步, 最后一次看到那步, 位置]
	var step := 0
	var foe_v := Vector2(0.0, 25.0)            # 目标每秒往下走 25 码(气波要追; 走太快四道会追成同一个来向)
	while step < 240:
		step += 1
		var tt: float = float(step) * DT
		foe["pos"] = (foe["pos"] as Vector2) + foe_v * DT
		var tp: Vector2 = foe["pos"]
		for k in range(4):
			if not bool(alive[k]):
				continue
			var to: Vector2 = tp - (wp[k] as Vector2)
			var dk: Vector2 = DetMath.norm(to)
			last_dir[k] = dk
			if tt <= ReserveConsts.WAVE_HOLD + 0.0001:
				continue                 # 同飞行逻辑: 出现后原地停 WAVE_HOLD 秒, 不动不留尾迹
			var adv: float = ReserveConsts.WAVE_SPEED * DT
			if DetMath.vlen(to) <= adv + 8.0:
				alive[k] = false
				hits.append([k, tp, dk])
				vfx.wave_hit(tp, dk)
				continue
			wp[k] = (wp[k] as Vector2) + dk * adv
			vfx.wave_trail(wp[k], dk, WAVE_LEN)
		vfx.lock_follow(tp)
		_step()
		# 新生的尾迹团: 认是哪一道(离哪道「弹体 − 方向 × 尾长」最近)
		for n in _fx("Trail"):
			var id: int = (n as Object).get_instance_id()
			if puff_seen.has(id):
				continue
			puff_seen[id] = true
			var sp3: Sprite3D = n
			if sp3.sorting_offset >= 0.0 or not is_equal_approx(sp3.pixel_size, WAVE_LEN / RV.WAVE_DIR_W_PX * WS):
				puff_sort_bad += 1
			var best_k := -1
			var best_d := INF
			for k in range(4):
				var want: Vector3 = _wpos((wp[k] as Vector2) - (last_dir[k] as Vector2) * (WAVE_LEN * RV.WAVE_DIR_TAIL_FRAC), RV.WAVE_H)
				var d: float = (sp3.position - want).length() / WS
				if d < best_d:
					best_d = d
					best_k = k
			if best_d > 0.5:
				puff_bad += 1
			else:
				(puff_by_wave[best_k] as Array).append(Vector2(sp3.position.x, sp3.position.z) / WS)
		for n in _fx("Hit"):
			var hid: int = (n as Object).get_instance_id()
			if not hit_nodes.has(hid):
				hit_nodes[hid] = [n, step, step, (n as Sprite3D).position]
			(hit_nodes[hid] as Array)[2] = step
		if t_gather < 0.0 and _fx("Gather").is_empty():
			t_gather = tt
		if t_ring < 0.0 and _fx("Ring").is_empty():
			t_ring = tt
		var lks: Array = _fx("Lock")
		if lks.size() == 1:
			lock_lag = maxf(lock_lag, _xz((lks[0] as Sprite3D).position, _wpos(tp, 0.0)) / WS)
			if t_lock7 < 0.0 and (lks[0] as Sprite3D).frame == 7:
				t_lock7 = tt
		if t_lock_gone < 0.0 and lks.is_empty():
			t_lock_gone = tt
	_ok("C 凝聚 0.20 秒后收掉(实测 %.3f)" % t_gather, t_gather > 0.0 and absf(t_gather - 0.20) <= 2.0 * DT)
	_ok("C 出现印 0.22 秒后收掉(实测 %.3f)" % t_ring, t_ring > 0.0 and absf(t_ring - 0.22) <= 2.0 * DT)
	_ok("C ★锁定切到「收紧」帧 = 气波名义飞到中心那一步(±2 步)", t_lock7 > 0.0 and absf(t_lock7 - t_arrive_nom) <= 2.0 * DT + 0.001,
		"收紧 %.3f 秒 / 名义合拢 %.3f 秒" % [t_lock7, t_arrive_nom])
	_ok("C 锁定合拢后 0.14 秒收掉(实测 %.3f, 时长表合计 %.3f)" % [t_lock_gone, _sum(RV.lock_durs())], t_lock_gone > 0.0 and absf(t_lock_gone - _sum(RV.lock_durs())) <= 2.0 * DT)
	_ok("C lock_follow: 锁定一直贴着会走的目标(最大偏差 ≤ 1 码)", lock_lag <= 1.0, "%.2f 码" % lock_lag)
	var min_per := 9999
	var gap_bad := 0
	for k in range(4):
		var arr: Array = puff_by_wave[k]
		min_per = mini(min_per, arr.size())
		for i in range(1, arr.size()):
			if ((arr[i] as Vector2) - (arr[i - 1] as Vector2)).length() < RV.TRAIL_GAP - 0.5:
				gap_bad += 1
	_ok("D ★分母: 每道都留了尾迹(≥ 10 团)", min_per >= 10, "各道 %s" % str([(puff_by_wave[0] as Array).size(), (puff_by_wave[1] as Array).size(), (puff_by_wave[2] as Array).size(), (puff_by_wave[3] as Array).size()]))
	_ok("D 每团都在弹体尾焰末端(弹体 − 方向 × 弹长 × %.3f, 气团高度)" % RV.WAVE_DIR_TAIL_FRAC, puff_bad == 0, "对不上 %d 团" % puff_bad)
	_ok("D 尾迹排序垫在弹体后面(sorting_offset < 0) · 与弹体同一像素密度", puff_sort_bad == 0, "%d 团不对" % puff_sort_bad)
	_ok("D 同一道相邻两团间距 ≥ TRAIL_GAP(%.0f 码)" % RV.TRAIL_GAP, gap_bad == 0, "%d 处太挤" % gap_bad)
	_ok("E ★分母: 四道都追上并打中了会走的目标", hits.size() == 4, "%d 道" % hits.size())
	var cam: Camera3D = _s._cam
	var back: Vector3 = cam.transform.basis.z.normalized() if cam != null else RV.CAM_DIR_FALLBACK
	var looks: Dictionary = {}
	var offs: Array = []
	var top_ok := 0
	var life_bad := 0
	for id in hit_nodes:
		var rec: Array = hit_nodes[id]
		offs.append(rec[3])
		var life: float = float(int(rec[2]) - int(rec[1]) + 1) * DT
		if absf(life - _sum(RV.HIT_DURS)) > 2.0 * DT:
			life_bad += 1
		var hn: Sprite3D = rec[0]
		if not is_instance_valid(hn):
			continue
		looks["%d/%s" % [hn.frame / hn.hframes, str(hn.flip_h)]] = true
		if hn.no_depth_test and hn.render_priority >= RV.HIT_PRIORITY and hn.billboard == BaseMaterial3D.BILLBOARD_ENABLED \
				and hn.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST:
			top_ok += 1
	# 位置: 每朵 = 命中那刻的目标位置 − 那道的方向 × HIT_BACK, 再朝镜头 HIT_TOWARD_CAM; 四朵分在四个面(来向两两夹角 ≥ 45°)
	var pos_ok := 0
	for h in hits:
		var want: Vector3 = _wpos((h[1] as Vector2) - (h[2] as Vector2) * RV.HIT_BACK, RV.WAVE_H) + back * RV.HIT_TOWARD_CAM
		for p3 in offs:
			if ((p3 as Vector3) - want).length() < 0.001:
				pos_ok += 1
				break
	var min_ang := 180.0
	for i in range(hits.size()):
		for j in range(i + 1, hits.size()):
			var cosv: float = DetMath.dot(hits[i][2], hits[j][2])
			min_ang = minf(min_ang, rad_to_deg(acos(clampf(cosv, -1.0, 1.0))))
	_ok("E 4 朵爆点各在被打者「来向」那侧 %.0f 码、朝镜头 %.1f 米, 分在四个面(来向两两夹角 ≥ 45°)" % [RV.HIT_BACK, RV.HIT_TOWARD_CAM],
		hit_nodes.size() == 4 and pos_ok == 4 and min_ang >= 45.0, "爆点 %d / 位置对上 %d / 最小夹角 %.0f°" % [hit_nodes.size(), pos_ok, min_ang])
	_ok("E 4 种样子 · 不做深度测试、排最上层(立绘 / 地面挡不住) · 立牌 NEAREST", looks.size() == 4 and top_ok == 4, "样子 %d / 合格 %d" % [looks.size(), top_ok])
	_ok("E 每朵爆点 %.3f 秒后收掉(±2 步)" % _sum(RV.HIT_DURS), hit_nodes.size() == 4 and life_bad == 0, "超差 %d 朵" % life_bad)
	# 顿帧: 同一位置连调 10 次只多 ≤ 1 团
	var before: int = _fx("Trail").size()
	for _k in range(10):
		vfx.wave_trail(c + Vector2(0, -150), Vector2.RIGHT)
		_step()
	_ok("D 顿帧(同一位置连调 10 步)只多 ≤ 1 团", _fx("Trail").size() - before <= 1, "多了 %d 团" % (_fx("Trail").size() - before))
	# 散去
	var fzp: Vector2 = c + Vector2(200, 120)
	vfx.wave_fizzle(fzp)
	var fz: Array = _fx("Fizzle")
	var t_fz := -1.0
	for st2 in range(40):
		_step()
		if t_fz < 0.0 and _fx("Fizzle").is_empty():
			t_fz = float(st2 + 1) * DT
	_ok("E wave_fizzle 在给的位置散一次、0.20 秒收掉", fz.size() == 1 and ((fz[0] as Sprite3D).position - _wpos(fzp, RV.WAVE_H)).length() < 0.001
		and absf(t_fz - _sum(RV.FIZZLE_DURS)) <= 2.0 * DT, "%d 个 / %.3f 秒" % [fz.size(), t_fz])

	# ═══ F 不碰结算: 只跑演出 ═══
	print("--- F 不碰结算 ---")
	for _k in range(60):
		_step()
	var rng_state: int = _s._battle_rng.state
	var ps0: int = _s._pending_shots.size()
	var snap0: Array = _snap()
	var fv: RefCounted = RV.new(_s)
	fv.converge_spawn(_s._reserve_sys.spawn_points(caster, foe), foe["pos"])
	for u in _s._units:
		fv.wave_hit(u["pos"], Vector2.RIGHT)
	var made: int = _fx().size()
	for k in range(90):
		if k < 40:
			fv.wave_trail(c + Vector2(6.0 * float(k), -100.0), Vector2.RIGHT)
			fv.lock_follow(foe["pos"])
		_s._step_sim_tweens(DT)
	_ok("F ★分母: 这段只跑演出, 建了演出节点", made >= 9 + _s._units.size(), "%d 个" % made)
	var snap1: Array = _snap()
	var diff := 0
	for i in range(mini(snap0.size(), snap1.size())):
		if str(snap0[i]) != str(snap1[i]):
			diff += 1
	_ok("F 全部单位字段逐项不变(%d 个单位)" % snap0.size(), snap0.size() == snap1.size() and diff == 0 and snap0.size() >= 2, "%d 个变了" % diff)
	_ok("F _battle_rng 状态不变 · _pending_shots 不多不少", _s._battle_rng.state == rng_state and _s._pending_shots.size() == ps0,
		"rng %s→%s / 队列 %d→%d" % [str(rng_state), str(_s._battle_rng.state), ps0, _s._pending_shots.size()])

	# ═══ H 走真入口: _reserve_sys.cast() —— 不自己喂契约, 量 ReserveSystem 真的把演出接上了 ═══
	print("--- H 走真入口 cast() ---")
	for _k in range(120):
		_step()
	_ok("H 起跑前场上没有演出节点(前面几段都收干净了)", _fx().is_empty(), "%d 个" % _fx().size())
	var seen: Dictionary = {"Gather": {}, "Ring": {}, "Lock": {}, "Trail": {}, "Hit": {}, "Fizzle": {}}
	var watch := func() -> void:
		for kind in seen:
			for n in _fx(str(kind)):
				(seen[kind] as Dictionary)[(n as Object).get_instance_id()] = true
	# H1 打中: 目标一边被追一边往下走(测 lock_follow 跟着它)
	foe["alive"] = true
	foe["hp"] = foe["maxHp"]
	foe["pos"] = c
	caster["pos"] = c - Vector2(420, 0)
	var hp_h0: float = float(foe["hp"])
	## 停 + 飞到中心的名义时长折成步数, 再多给 40 步(气波数值改了它自己跟着变)
	var n_fly: int = int(ceil((ReserveConsts.WAVE_HOLD + ReserveConsts.WAVE_RADIUS / ReserveConsts.WAVE_SPEED) / DT)) + 90
	_s._reserve_sys.cast(caster, foe)
	watch.call()
	var lag_h := 0.0
	var lock_steps := 0
	for _k in range(n_fly):
		foe["pos"] = (foe["pos"] as Vector2) + Vector2(0.0, 40.0) * DT
		_step()
		watch.call()
		var lks2: Array = _fx("Lock")
		if lks2.size() == 1:
			lock_steps += 1
			lag_h = maxf(lag_h, _xz((lks2[0] as Sprite3D).position, _wpos(foe["pos"], 0.0)) / WS)
	var cnt := func(kind: String) -> int:
		return (seen[kind] as Dictionary).size()
	_ok("H1 ★分母: 真入口的四道气波打中了目标(掉血)", float(foe["hp"]) < hp_h0, "%.0f → %.0f" % [hp_h0, float(foe["hp"])])
	_ok("H1 施法那一刻: 凝聚 4 / 出现印 4 / 锁定 1", cnt.call("Gather") == 4 and cnt.call("Ring") == 4 and cnt.call("Lock") == 1,
		"%d / %d / %d" % [cnt.call("Gather"), cnt.call("Ring"), cnt.call("Lock")])
	_ok("H1 飞行中留了尾迹(≥ 8 团)", cnt.call("Trail") >= 8, "%d 团" % cnt.call("Trail"))
	_ok("H1 打中出了命中爆点(四道都打中 ⇒ 4 朵)", cnt.call("Hit") == 4, "%d 朵" % cnt.call("Hit"))
	## 气波每 SKILLSHOT_STEP(0.05 秒)才走一步、才调一次 lock_follow ⇒ 两次之间目标最多走 40 × 0.05 = 2 码; 不跟的话要差 30 码以上
	var lag_tol: float = 40.0 * float(_s._ballistics.SKILLSHOT_STEP) + 1.0
	_ok("H1 锁定一直跟着会走的目标(跟了 %d 步, 最大偏差 ≤ %.0f 码)" % [lock_steps, lag_tol], lock_steps >= 20 and lag_h <= lag_tol, "%.2f 码" % lag_h)
	# H2 目标刚放完技就没了 ⇒ 四道飞到它最后的位置散掉(不打人)
	for _k in range(60):
		_step()
	seen["Fizzle"] = {}
	seen["Hit"] = {}
	foe["pos"] = c
	_s._reserve_sys.cast(caster, foe)
	foe["alive"] = false
	for _k in range(n_fly):
		_step()
		watch.call()
	foe["alive"] = true
	_ok("H2 目标没了 ⇒ 四道各在终点散一次、不出命中爆点", cnt.call("Fizzle") == 4 and cnt.call("Hit") == 0,
		"散 %d / 爆点 %d" % [cnt.call("Fizzle"), cnt.call("Hit")])
	for _k in range(60):
		_step()
	_ok("H 真入口跑完全部收干净", _fx().is_empty(), "%d 个" % _fx().size())

	# ═══ J 实际飞行速度 = 标称(按真实的 1/60 秒 sim 步推进; 旧版延时 0.05 秒要 4 步才到点 ⇒ 实际只有 3/4) ═══
	print("--- J 实际速度 ---")
	foe["alive"] = true
	foe["hp"] = foe["maxHp"]
	foe["pos"] = c
	caster["pos"] = c - Vector2(420, 0)
	var hp_j0: float = float(foe["hp"])
	_s._reserve_sys.cast(caster, foe)
	var j_steps := -1
	for _k in range(600):
		_step()
		if j_steps < 0 and float(foe["hp"]) < hp_j0:
			j_steps = _k + 1
	var adv_j: float = ReserveConsts.WAVE_SPEED * float(_s._ballistics.SKILLSHOT_STEP)
	var t_want: float = ReserveConsts.WAVE_HOLD + (ReserveConsts.WAVE_RADIUS - adv_j) / ReserveConsts.WAVE_SPEED
	_ok("J ★站着不动的目标: 停 %.1f 秒 + 飞 %.0f 码(%.0f 码/秒)后打中 —— 实际时刻 = 标称(±2 个 0.05 秒步)" % [ReserveConsts.WAVE_HOLD, ReserveConsts.WAVE_RADIUS, ReserveConsts.WAVE_SPEED],
		j_steps > 0 and absf(float(j_steps) * DT - t_want) <= 2.0 * float(_s._ballistics.SKILLSHOT_STEP) + 0.001,
		"实测 %.3f 秒 / 标称 %.3f 秒" % [float(j_steps) * DT, t_want])

	# ═══ I 普攻弹体: 援军小将走专属气弹(用户 2026-10-29「他普攻有弹道吗？」—— 原来是全体远程共用的程序小光点) ═══
	print("--- I 普攻气弹 ---")
	foe["alive"] = true
	foe["hp"] = foe["maxHp"]
	foe["pos"] = c
	var rsv: Dictionary = _s._spawn._make_unit("__minion__", "left", c - Vector2(300, 0), {"minion": true, "role": "reserve", "battles": 0})
	var np0: int = _s._projectiles.size()
	_s._ballistics._fire_bolt_from(rsv, foe, 1, Color.WHITE, null, true)
	var pr_ok := false
	var pr_d := "没出弹(弹道表 %d → %d)" % [np0, _s._projectiles.size()]
	if _s._projectiles.size() == np0 + 1:
		var prd: Dictionary = _s._projectiles[np0]
		var sp4: Sprite3D = prd["node"] as Sprite3D
		var tpath: String = sp4.texture.resource_path if sp4 != null and sp4.texture != null else "(无贴图)"
		pr_d = "贴图 %s · 朝向 %s · %d 帧 · pixel_size %.4f" % [tpath, str(prd.get("oriented", false)), sp4.hframes if sp4 != null else 0,
			sp4.pixel_size if sp4 != null else 0.0]
		pr_ok = tpath == ReserveSystem.SHOT_TEX and bool(prd.get("oriented", false)) and sp4.hframes == 4 			and is_equal_approx(sp4.pixel_size, ReserveSystem.SHOT_LEN * WS / 16.0)
		_s._projectiles.remove_at(np0)
		if sp4 != null:
			sp4.queue_free()
	_ok("I 援军小将普攻 = 专属气弹(reserve-shot · 4 帧 · 弹头朝飞行方向 · 场上 SHOT_LEN 码)", pr_ok, pr_d)

	# ═══ G 不留残节点 ═══
	for _k in range(120):
		_step()
	await get_tree().process_frame
	await get_tree().process_frame
	var left: Array = []
	for n in _s._world.get_children():
		if String(n.name).contains(RV.TAG):
			left.append(String(n.name))
	_ok("G 全部跑完不留残节点(带 %s 的节点 = 0)" % RV.TAG, left.is_empty(), str(left))

	print("")
	print("共 %d 项 · FAIL %d" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
