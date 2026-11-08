extends Node
## 小将拉向目标按速度飞(用户 2026-11-08):
##   近战小将「把自己拉向对面这个时间现在是固定的…我让你改成就是以这个速度去飞行」
##   精英小将「把自己拉进敌人这个速度也是太快，而且为什么固定就不应该，你就要慢慢…飞过去」
## 判据量的是【时长随距离变】: 远的比近的多飞 (距离差 ÷ 速度) 秒 —— 固定时长时这个差是 0, 必红。
## 速度写需求外的我定值 500 码 / 秒(期望值写字面数, 不引用常量)。动作要跟着拉长: 量真单位上真播的那张表的时长。
## ★绳索(11-08 逐帧查出: 两个小将的链子都在拉人开始前 / 拉到一半就淡掉了): 量场上带 rope_f 标记、可见且不透明的链节数 ——
##   拉人开始那一刻 > 0(原 bug 下是 0)、飞到一半比开始时少(逐段收)、落地后 0。

const WANT_SPD := 500.0

var _fail := 0


func _chk(name: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s%s" % ["PASS" if ok else "FAIL", name, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(6):
		await get_tree().process_frame
	s._deterministic = true
	print("=== 小将拉向目标按速度飞(11-08) ===")
	## ★不能把场上原有单位判死: 一方全灭 ⇒ 这一路结束、战斗时钟停走, 量出来全是 0(首版就这么假红)。
	##   ① 用合成单位(不进 _units); ② 用嘲讽把精英的靶锁成我们放的那个, 并让精英不可选中免得被打断。

	## ① 近战小将·人体浪板: 合成单位(只操作传进去的字典), 量「放技能 → 接触扣血」用时
	var surf := []
	for gap in [400.0, 1000.0]:
		## 真造单位但不进 _units(接触那一下走真伤害路径, 手搓字典缺 crit / shield 等键会刷脚本错)
		var mn: Dictionary = s._spawn._make_unit("__minion__", "left", Vector2(300, 400), {"minion": true, "level": 1})
		var foe: Dictionary = s._spawn._make_unit("stone", "right", Vector2(300 + gap, 400), {})
		foe["maxHp"] = 50000.0; foe["hp"] = 50000.0
		var t0: float = float(s._t)
		s._hiding_sys._sk_minion_bodysurf(mn, foe)
		var w := 0
		## 起跳是原地的: 第一次离地 5 以上时的位置 = 俯冲起点(取最后一次会取到俯冲半途, 首版就量错了)
		var apex := Vector2.INF
		var h_prev := 0.0
		var rope_start := -1
		var rope_mid := -1
		while w < 4000 and float(foe["hp"]) >= 50000.0:
			await get_tree().process_frame
			w += 1
			var hh: float = float(mn.get("height", 0.0))
			if apex == Vector2.INF and hh > 5.0:
				apex = mn["pos"]
			if rope_start < 0 and apex != Vector2.INF and hh < h_prev - 0.001:   # 高度开始往下 = 俯冲(被拽)开始
				rope_start = _rope_visible(s)
			if rope_start >= 0 and rope_mid < 0 and apex != Vector2.INF and (mn["pos"] as Vector2).distance_to(apex) >= 0.5 * apex.distance_to(foe["pos"]):
				rope_mid = _rope_visible(s)
			h_prev = hh
		var took: float = float(s._t) - t0   # 先记时长再等绳节淡完(等的 30 帧不算进飞行)
		for _k in range(30):
			await get_tree().process_frame
		var rope_end: int = _rope_visible(s)
		print("  ① 目标距 %.0f: 绳节 拉人开始 %d / 飞到一半 %d / 落地后 %d" % [gap, rope_start, rope_mid, rope_end])
		_chk("① 距 %.0f ★拉人开始那一刻铁索还在(原来射出 0.42 秒就淡掉)" % gap, rope_start > 0, "%d 节" % rope_start)
		_chk("① 距 %.0f 飞到一半: 经过的绳节已收掉(%d < %d)、前面的还在" % [gap, rope_mid, rope_start], rope_mid > 0 and rope_mid < rope_start)
		_chk("① 距 %.0f 落地后绳节清零" % gap, rope_end == 0, "%d 节" % rope_end)
		var dist: float = apex.distance_to(foe["pos"])
		print("    (战斗仍在进行: _dl_state=%s 呈现中=%s _over=%s · 等了 %d 帧)" % [str(s._dl_state), str(s._dl_sys._dl_is_present()), str(s._over), w])
		surf.append([took, dist])
		print("  ① 目标距 %.0f: 放技能到接触 %.2f 秒(悬停点到目标 %.0f 码)" % [gap, took, dist])
	if surf.size() == 2:
		var want: float = (float(surf[1][1]) - float(surf[0][1])) / WANT_SPD
		var got: float = float(surf[1][0]) - float(surf[0][0])
		_chk("① 分母: 两次都接触到了(远近差 %.0f 码)" % (float(surf[1][1]) - float(surf[0][1])), float(surf[0][0]) > 1.0 and float(surf[1][0]) > 1.0)
		_chk("① 远的比近的多飞 %.2f 秒(= 距离差 ÷ 500), 实测 %.2f" % [want, got], absf(got - want) <= 0.05)

	## ② 精英小将·铁锁: 真单位(要从场上选靶), 量拉体时长 + 甩臂动作真播的时长
	var whip := []
	for gap in [180.0, 340.0]:
		var e: Dictionary = s._spawn._make_unit("__minion__", "left", Vector2(400, 300), {"minion": true, "elite": true, "level": 1})
		var f: Dictionary = s._spawn._make_unit("stone", "right", Vector2(400 + gap, 300), {})
		f["maxHp"] = 50000.0; f["hp"] = 50000.0
		s._units.append(e); s._units.append(f)
		e["_whip_cd"] = 0.0; e["stun_until"] = 0.0; e["_slam"] = false
		e["taunt_until"] = float(s._t) + 100.0; e["taunt_by"] = f
		e["untargetable_until"] = float(s._t) + 100.0
		var t0: float = float(s._t)
		var e0: Vector2 = e["pos"]
		s._tick_elite_whip(e)
		_chk("② 距 %.0f 分母: 铁锁确实射出(_slam 置位)" % gap, bool(e.get("_slam", false)))
		var sd: Dictionary = e.get("anim_sd", {})
		var anim_sec: float = float(sd.get("frames", 0)) / maxf(0.001, float(sd.get("fps", 0.0)))
		var w := 0
		var lk_start := -1
		var lk_mid := -1
		var pull_len: float = e0.distance_to(f["pos"]) + 46.0
		while w < 2000 and bool(e.get("_slam", false)):
			await get_tree().process_frame
			w += 1
			var moved: float = (e["pos"] as Vector2).distance_to(e0)
			if lk_start < 0 and moved > 0.5:          # 开始被拽
				lk_start = _rope_visible(s)
			if lk_mid < 0 and moved >= 0.5 * pull_len:
				lk_mid = _rope_visible(s)
		var took: float = float(s._t) - t0   # 先记时长再等链节淡完
		for _k in range(30):
			await get_tree().process_frame
		var lk_end: int = _rope_visible(s)
		print("  ② 目标距 %.0f: 链节 拉人开始 %d / 飞到一半 %d / 落地后 %d" % [gap, lk_start, lk_mid, lk_end])
		_chk("② 距 %.0f ★拉人开始那一刻铁链还在" % gap, lk_start > 0, "%d 节" % lk_start)
		_chk("② 距 %.0f ★飞到一半铁链还在、经过的已收掉(%d < %d; 原来链节亮起 0.3 秒就淡掉)" % [gap, lk_mid, lk_start], lk_mid > 0 and lk_mid < lk_start)
		_chk("② 距 %.0f 拉完后链节清零" % gap, lk_end == 0, "%d 节" % lk_end)
		whip.append([took, gap, anim_sec, str(e.get("anim_action", ""))])
		print("  ② 目标距 %.0f: 出手到拉完 %.2f 秒 · 甩臂动作 %s 时长 %.2f 秒" % [gap, took, str(sd.get("frames", "?")), anim_sec])
		e["alive"] = false; f["alive"] = false
	if whip.size() == 2:
		var want2: float = (float(whip[1][1]) - float(whip[0][1])) / WANT_SPD
		var got2: float = float(whip[1][0]) - float(whip[0][0])
		_chk("② 远的比近的多飞 %.2f 秒(= 距离差 ÷ 500), 实测 %.2f" % [want2, got2], absf(got2 - want2) <= 0.05)
		for k in range(2):
			_chk("② 距 %.0f: 甩臂动作时长 %.2f ≈ 出手到拉完 %.2f(播完才不会半空回站姿)" % [float(whip[k][1]), float(whip[k][2]), float(whip[k][0])],
				absf(float(whip[k][2]) - float(whip[k][0])) <= 0.08)

	## ③ 人体浪板俯冲动作: 调用处按飞行时长传 fps(合成单位没贴图, 量不到真播 ⇒ 这里查接线, 录像验画面)
	var src: String = FileAccess.get_file_as_string("res://scripts/systems/skills/hiding_system.gd")
	_chk("③ 俯冲动作按飞行时长拉长(_melee_anim(u, \"dive\", 4.0 / dive_sec))", src.contains("battle._melee_anim(u, \"dive\", 4.0 / dive_sec)"))

	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 小将拉向目标按速度飞" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 场上可见的链节 / 绳节(PullRopeVfx 摆的, 带 rope_f 标记)数
func _rope_visible(s) -> int:
	var n := 0
	for c in s._world.get_children():
		if c is Sprite3D and c.has_meta("rope_f") and (c as Sprite3D).visible and (c as Sprite3D).modulate.a > 0.5:
			n += 1
	return n

