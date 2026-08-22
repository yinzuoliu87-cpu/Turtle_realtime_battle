extends Node
## verify_spirit_slap_range.gd — 灵物触手拍击【命中带的几何】（2026-08-05）
##
## ★★★为什么建这条：
##   用户 2026-08-04 拍板把命中半宽 40 → 120（「我要实际攻击范围也是这 3 倍」）。
##   ×3 之后我去核平衡，读 `_slap` 时发现命中判定是：
##       rel.dot(dir) >= 0        （只排除"在身后"）
##       absf(rel.cross(dir)) <= 120
##   —— **没有任何长度上限**。也就是说伤害带是【向前无限延伸 × 240 码宽】的半平面。
##
##   而选靶那一步是**有**射程限制的（`attack_range_2d`，实测 400 码），代码注释还写了理由：
##       「必须在触手的固定射程内 …… 范围外的敌人不该被选中(否则演出伸不到、
##         或者为了够到而拉长，两种都会让"安全距离"这条规则失效)」
##   这个理由对**伤害带**同样成立 —— 触手根本够不到的敌人不该挨打。
##   战场是 1596×728，而射程只有 400 ⇒ 这条带子能横穿整个战场，是射程的 4 倍。
##   探针实测：640 码外(射程的 1.6 倍)的敌人被打掉 48065 血。
##
##   ⚠ 而且半宽 ×3 之后这个洞被放大了 3 倍：带子越宽，"顺带扫到远处路人"越多。
##
## ★第二个问题（顺着查出来的）：**预警带和伤害带不是一回事**。
##   预警带原来画到"目标身上就停"，而触手攻击时**一律伸到全长**、伤害也按射程算
##   ⇒ 目标离得近时，**目标之后那一段会打到人却没有任何预警**。
##   预警区存在的唯一意义就是"这里危险"，打得到却不画 = 骗玩家。
##   ⇒ 两者焊成同一个长度，由本文件第 ⑤ 条锁死。
##
## 守七条：
##   ① / ①b ★分母：档位真的 > 0、拍击真的结算了
##   ② ★射程内、带宽内的敌人 —— 必须命中
##   ③ ★带宽外的敌人 —— 必须不中（半宽 120 的边界两侧各放一个）
##   ④ ★★射程外的敌人 —— 必须不中
##   ⑤a/⑤b ★★预警带长度 == 伤害带长度。**两边分别量真实对象**：
##       预警 = 量 `warn_mi` 网格的真实包围盒；伤害 = 二分探测 `_slap` 的真实行为。
##       ⚠ 绝不许两边都读同一个 `attack_range_2d` —— 那是恒真式，改坏了照样绿。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_spirit_slap_range.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _dummy(side: String, p: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, p)
	u["alive"] = true
	u["pos"] = p
	u["hp"] = 999999.0
	u["maxHp"] = 999999.0
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	_s._units.append(u)
	return u


## 造真正的灵物携带者（`_side_tier` 是遍历本方单位算的，直写 `_by_side` 会得到假 PASS）
func _carrier(side: String, p: Vector2) -> Dictionary:
	var eq: Array = []
	for e in DataRegistry.phase2_equipment:
		if _s.Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == "灵物":
			eq.append({"id": str((e as Dictionary)["id"]), "star": 1})
		if eq.size() >= 5:
			break
	var u: Dictionary = _dummy(side, p)
	u["equips"] = eq
	u["eq_state"] = {}
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物触手: 拍击命中带的几何 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	if _s == null:
		print("  [FAIL] ⓪ 战场没建起来(依赖脚本编译失败?)")
		print("FAIL x1")
		get_tree().quit(1)
		return
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	# ★★★必须先清空: 战场自己会生成默认单位。第一版没清, 结果【选靶选中了场景自带的敌人】,
	#   于是 dir 根本不是我以为的 +X, 我算的横向偏移全部失效 ——
	#   表现是"命中 4 个"却又"射程外那个没挨打", 自相矛盾。
	#   CLAUDE.md §7: 拿随机 spawn 的单位测精确数值会 CI 偶发红, 要用干净的合成单位隔离。
	_s._units.clear()
	var syn = _s._spirit_syn
	var rng: float = float(_s._tentacle_vfx.attack_range_2d)
	var half: float = 120.0        # ★硬写, 不读被测常量(读了就是恒真式)

	# 携带者放在战场左侧, 触手会在它附近生成
	var base := Vector2(_s.ARENA.position.x + 200.0,
		_s.ARENA.position.y + _s.ARENA.size.y * 0.5)
	_carrier("left", base)
	var tier: int = syn._side_tier("left")
	_ok("① ★分母: 灵物档位真的 > 0 (实测 %d 档)" % tier, tier > 0,
		"档位是 0 ⇒ _slap 直接 return, 后面全是空检查")
	if tier <= 0:
		print("FAIL x1"); get_tree().quit(1); return

	var origin: Vector2 = syn.tentacle_pos("left", 0)

	# ── 摆敌人：全部沿 +X 方向, 只变距离与横向偏移 ──
	# 近处这个是【选靶目标】(最近且在射程内), 它定下 dir = +X
	var near_on := _dummy("right", origin + Vector2(200.0, 0.0))
	# 带宽内(横向 100 < 120) 且射程内 ⇒ 该中
	var in_band := _dummy("right", origin + Vector2(300.0, 100.0))
	# 带宽外(横向 160 > 120) 且射程内 ⇒ 不该中
	var out_band := _dummy("right", origin + Vector2(300.0, 160.0))
	# ★射程外(距离 = 射程 × 1.6)、但正对着 ⇒ 触手够不到, 不该中
	var far_on := _dummy("right", origin + Vector2(rng * 1.6, 0.0))

	var hp0 := {}
	for u in [near_on, in_band, out_band, far_on]:
		hp0[str(u.get("uid", u))] = float(u["hp"])

	var hits: int = _slap_and_land(syn, "left", 0, 1.0)
	_ok("①b ★分母: 拍击真的结算了(命中 %d 个)" % hits, hits > 0,
		"一个都没打中 ⇒ 后面三条是空检查")

	var d_near: float = float(near_on["hp"])
	var d_in: float = float(in_band["hp"])
	var d_out: float = float(out_band["hp"])
	var d_far: float = float(far_on["hp"])
	var hurt := func(u) -> bool: return float(u["hp"]) < 999999.0

	_ok("② ★射程内 + 带宽内(横向 100 < %.0f) 必须命中" % half,
		hurt.call(near_on) and hurt.call(in_band),
		"近处 hp=%.0f / 带内 hp=%.0f (999999 = 没挨打)" % [d_near, d_in])
	_ok("③ ★带宽外(横向 160 > %.0f) 必须不中" % half, not hurt.call(out_band),
		"带宽外的挨打了 hp=%.0f ⇒ 命中半宽比 %.0f 大" % [d_out, half])
	_ok("④ ★★射程外(%.0f 码 = 射程 %.0f 的 1.6 倍) 必须不中 —— 触手够不到的人不该挨打" % [rng * 1.6, rng],
		not hurt.call(far_on),
		"射程外 %.0f 码的敌人挨打了(hp=%.0f)。命中带向前【无限延伸】: " % [rng * 1.6, d_far]
		+ "`_slap` 只判 rel.dot(dir)>=0 与 |cross|<=%.0f, 没有长度上限。" % half
		+ "战场 %.0fx%.0f, 而射程只有 %.0f ⇒ 带子能横穿全场" % [_s.ARENA.size.x, _s.ARENA.size.y, rng])

	# ── ⑤ ★预警带 = 伤害带（长度必须一样）──
	# 这条是整个文件里最重要的一条: 预警区存在的唯一意义是"这里危险"。
	# 打得到却不画 = 骗玩家; 画了却打不到 = 白吓唬。两边**分别量真实对象**:
	#   · 伤害长度: 从 `_slap` 的行为反推 —— 沿 dir 逐步放一个敌人, 找出最远还会挨打的距离
	#   · 预警长度: 量 `warn_mi` 这个 MeshInstance3D 的**真实包围盒**, 不读常量
	# ⚠ 不许两边都读同一个 `attack_range_2d` —— 那是恒真式, 改坏了照样绿。
	var tv = _s._tentacle_vfx
	tv.ensure_forced("left", 1)
	await get_tree().process_frame
	# ★`_tents` 的键是【"side|idx" 复合字符串】, 不是 side ——
	#   我第一版按 `_tents["left"][0]` 取, 拿到 null, ⑤ 两条直接空红。探针打出来才知道。
	var t0 = tv._tents.get("left|0", null)
	var warn_len := -1.0
	if t0 != null:
		t0["aim"] = origin + Vector2(200.0, 0.0)     # 目标故意放得【很近】(200 << 射程)
		tv._telegraph_tick(t0, 1.0)
		await get_tree().process_frame
		var wmi = t0.get("warn_mi", null)
		if is_instance_valid(wmi) and wmi.mesh != null and wmi.mesh.get_surface_count() > 0:
			var aabb: AABB = (wmi.mesh as ArrayMesh).get_aabb()
			# 世界单位 → 码：与 root_pos/tentacle_pos 同一换算（_world_pos 的逆）
			warn_len = maxf(aabb.size.x, aabb.size.z) / _s.WS
	_ok("⑤a ★分母: 预警带真的建出来且量到了长度(实测 %.0f 码)" % warn_len, warn_len > 1.0,
		"没量到 —— 后面那条是空检查")
	# 伤害长度: 二分找"最远还会挨打的距离"
	var lo := 0.0
	var hi := rng * 3.0
	for _i in range(24):
		var mid: float = (lo + hi) * 0.5
		for u in _s._units.duplicate():
			if str(u.get("side", "")) == "right":
				_s._units.erase(u)
		var near2 := _dummy("right", origin + Vector2(60.0, 0.0))    # 保证选靶方向仍是 +X
		var probe := _dummy("right", origin + Vector2(mid, 0.0))
		_slap_and_land(syn, "left", 0, 1.0)
		if float(probe["hp"]) < 999999.0: lo = mid
		else: hi = mid
	var dmg_len: float = (lo + hi) * 0.5
	_ok("⑤b ★★预警带长度 == 伤害带长度（预警 %.0f 码 / 伤害 %.0f 码）" % [warn_len, dmg_len],
		absf(warn_len - dmg_len) <= 25.0,
		"差了 %.0f 码。打得到却不画 = 骗玩家; 画了打不到 = 白吓唬" % absf(warn_len - dmg_len))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 灵物拍击命中带" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

## 拍击一次并**推到视觉命中那一刻**。
## ★★ 2026-08-10 拍击改成【延后结算】(方案 A): 伤害不再在 `_slap()` 里立即打出,
##   而是等到触手真的拍到(T_WARN + T_REAR = 1.13 秒)才结算 ——
##   因为原来**伤害比视觉命中早 1.13 秒**, 预警圈彻底成了摆设。
##   所以这里不能再"调完就查血量" —— 要把待发队列推过那个延迟。
## ★不用 await/等帧: `_step_pending_shots(dt)` 是同步的, 一次喂够就触发 ⇒ 确定性、不依赖帧率。
func _slap_and_land(syn, side: String, idx: int, share: float) -> int:
	## ★先走完【出土】(T_EMERGE = 2.0 秒): ST_EMERGE / ST_RETRACT 期间
	##   `strike()` 会直接 return ⇒ 没有流水号、延后结算会被 `is_striking` 拦下。
	##   ★改之前伤害不管演出照打, 所以这个坑一直被盖着 ——
	##   现在伤害挂在演出上, "触手还没站稳就能打人"这件事自然就不成立了。
	## ★先确保这根触手真的存在 —— `_tents` 里没有它的话 `strike()` 直接 return。
	##   (改之前伤害不管有没有触手照打, 所以测试一直没建触手也能绿。
	##   真实对局里 `_tick` 是先 `ensure()` 再 `_slap()` 的, 所以不存在这种情况。)
	_s._tentacle_vfx.ensure_forced(side, idx + 1)
	for _e in range(30):
		_s._tentacle_vfx.tick(0.12)
	var n: int = syn._slap(side, idx, share)
	var d: float = _s._tentacle_vfx.hit_delay(share)
	## ★2026-08-22: 伤害改挂在触手自己的"梢端触地"标志上(原来走 _queue_shots 这条会漂的
	##   第二时钟, 实测 13% 的拍击完整演出零伤害)。⇒ 推进时间的手柄换成 tv.tick,
	##   小步喂(状态机要逐段过 WARN→REAR→SLAM, 一大步会跳过切换)。判据不变。
	if d > 0.0:
		var _n: int = maxi(1, int(ceil((d + 0.02) / 0.01)))
		for _i in range(_n):
			_s._tentacle_vfx.tick((d + 0.02) / float(_n))
	return n
