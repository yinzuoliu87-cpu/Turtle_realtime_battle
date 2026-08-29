extends Node
## verify_sword_084.gd — 手半剑 p2eq_084：近战有弹道 + 红闪电 + 两个新机制 (2026-08-29)
##
## ══════════════════════════════════════════════════════════════════════
##  由来（用户 2026-08-29）
## ══════════════════════════════════════════════════════════════════════
## 「手半剑近战携带时攻击时**没有任何弹道**，现在要加一个类似云顶之弈的火炮装备，
##   就是 S4 版本射程翻倍那个，打出去有红色闪电激光特效的，此外加个机制，
##   近战携带还会获得 3/6/10% 增伤，远程携带还会获得 3/6/10% 减伤，
##   远程提供的生命值加强为 300/700/3000」
## 「不要拿图片贴图敷衍我，**我要动画像素特效**」
##
## **「没有弹道」已确认是真的**：`_emit_basic()` 的分叉是 `if u["melee"]` 走瞬发；
## 而 084 近战携带**只改射程数值、故意不改 `melee` 标记**
## （`eq_blade_batch:561` 的注释：用户拍板改标记会连"近战最小射程钳制"等规则一起变）
## ⇒ 射程 450 码却走瞬发分支 ⇒ **450 码外挥空气**。
##
## ⇒ 修法把两件事分开：
##   · **机制**（不再挥空气）判据落在 **有效射程 ≥ `LONG_MELEE_RANGE`**，与 `melee` 标记解耦
##     —— 以后别的装备把近战拉远也自动有弹道，不用再改一次
##   · **外观**（红闪电）绑死在 **`_b84_mode == "melee"`**（这件装备的身份）
##     —— 别的东西把近战拉远时该有弹道，但不该射红闪电
##
## ══════════════════════════════════════════════════════════════════════
##  这条门禁守什么
## ══════════════════════════════════════════════════════════════════════
## ★判据落在**产品自己造出来的弹体节点**（`battle._projectiles` / `_world` 里的 Sprite3D），
##   不是"我插的标记被设过" (memory [[fb-gate-must-measure-requirement-not-my-hook]])。
## ★"动画像素特效"要**逐帧量**：贴图的 `hframes > 1` 且帧号**真的在变** ——
##   只断言"挂了多帧贴图"守不住（猎人箭矢就是挂了 4 帧却一帧没动过，静默了很久）。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_sword_084.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EqBladeBatch := preload("res://scripts/systems/equip/eq_blade_batch.gd")
const BasicConsts := preload("res://scripts/gamedata/basic_consts.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 手半剑 084 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── ① 数值（用户 2026-08-29 拍板）──
	_ok("★① 近战增伤 = 3/6/10%",
		str(EqBladeBatch.HH_MELEE_AMP) == "[0.03, 0.06, 0.1]", str(EqBladeBatch.HH_MELEE_AMP))
	_ok("★① 远程减伤 = 3/6/10%",
		str(EqBladeBatch.HH_RANGED_DR) == "[0.03, 0.06, 0.1]", str(EqBladeBatch.HH_RANGED_DR))
	## ★比数值不比字符串 —— 第一版拿 str() 比, 被 [300.0,…] vs [300,…] 判红
	##   (memory fb-verify-check-can-fail: 数值比对别比字符串)
	_ok("★① 远程生命值 = 300/700/3000（原 200/400/1000）",
		absf(float(EqBladeBatch.HH_RANGED_HP[0]) - 300.0) < 0.001
			and absf(float(EqBladeBatch.HH_RANGED_HP[1]) - 700.0) < 0.001
			and absf(float(EqBladeBatch.HH_RANGED_HP[2]) - 3000.0) < 0.001,
		str(EqBladeBatch.HH_RANGED_HP))
	_ok("★① 近战射程仍是 450 码", absf(EqBladeBatch.HH_MELEE_RANGE - 450.0) < 0.001)
	## 阈值必须在【正常近战龟的射程】与【084 的 450】之间, 否则要么误伤要么不生效
	_ok("★① 弹道阈值 %d 卡在正常近战(≤120)与 084(450)之间"
			% int(BasicConsts.LONG_MELEE_RANGE),
		BasicConsts.LONG_MELEE_RANGE > 120.0 and BasicConsts.LONG_MELEE_RANGE < 450.0)

	# ── ② ★★近战携带: 真的射出弹体了吗 ──
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-300, 0))
	u["no_move"] = true
	u["atk"] = 100.0
	_ok("★分母: 造出来的是【近战】龟(不然这条测的不是那个 bug)", bool(u.get("melee", false)))
	_s._equip_sys._blade_sys._spawn084(u, 2)          # 3★ 近战携带
	_ok("★★分母: 进了近战形态且射程真的变成 450",
		str(u.get("_b84_mode", "")) == "melee" and absf(float(u.get("atk_range", 0.0)) - 450.0) < 1.0,
		"mode=%s range=%.0f" % [str(u.get("_b84_mode", "")), float(u.get("atk_range", 0.0))])
	_ok("★★② 近战携带拿到 10% 增伤(3★)",
		absf(float(u.get("damage_amp", 0.0)) - 0.10) < 0.0001,
		"damage_amp=%.3f" % float(u.get("damage_amp", 0.0)))
	## ★幂等: 再装一次(先1★后3★那种顺序)不许叠成两份
	_s._equip_sys._blade_sys._spawn084(u, 2)
	_ok("★★② 重复施加不叠加(差量施加)",
		absf(float(u.get("damage_amp", 0.0)) - 0.10) < 0.0001,
		"damage_amp=%.3f" % float(u.get("damage_amp", 0.0)))

	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(100, 0))
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	foe["no_basic"] = true
	foe["no_move"] = true
	_s._units.clear()
	_s._units.append(u)
	_s._units.append(foe)
	_s._over = false

	var n0: int = _s._projectiles.size()
	_s._emit_basic(u, foe, 100, Color("#ff4444"), 0)
	var made: int = _s._projectiles.size() - n0
	_ok("★★② 近战携带普攻【射出了弹体】(修前是 0 = 挥空气)", made >= 1,
		"新增弹体 %d 个" % made)

	# ── ③ ★★弹体是【红色】的【多帧动画】──
	var node = null
	if made >= 1:
		node = (_s._projectiles[_s._projectiles.size() - 1] as Dictionary).get("node", null)
	_ok("★分母: 拿到弹体节点", node != null and node is Sprite3D)
	if node is Sprite3D:
		var sp: Sprite3D = node
		var tp := str(sp.texture.resource_path) if sp.texture != null else ""
		_ok("★★③ 弹体用的是红闪电那张图", tp.contains("bolt-084-lightning"), tp)
		_ok("★★③ 它是【多帧】的(用户: 我要动画像素特效, 不是一张静图)",
			int(sp.hframes) > 1, "hframes=%d" % int(sp.hframes))
		_ok("★③ 像素画要 NEAREST(LINEAR 会糊)",
			sp.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		## ★★帧号要**真的在变** —— 只断言"挂了多帧"守不住:
		##   猎人箭矢就是 `hframes=4` 却一帧没动过(闸只对手里剑开), 静默了很久。
		var f0: int = int(sp.frame)
		var seen: Dictionary = {}
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 700 and is_instance_valid(sp):
			seen[int(sp.frame)] = true
			await get_tree().process_frame
		_ok("★★③ 帧号真的在变(见过 %d 个不同帧号)" % seen.size(), seen.size() >= 2,
			"起始帧 %d · 见过 %s" % [f0, str(seen.keys())])

	# ── ④ 远程携带: 减伤 + 生命值 ──
	var r: Dictionary = _s._spawn._make_unit("hunter", "left", c + Vector2(-300, 120))
	r["no_move"] = true
	_ok("★分母: 造出来的是【远程】龟", not bool(r.get("melee", true)))
	var hp_before: float = float(r.get("maxHp", 0.0))
	_s._equip_sys._blade_sys._spawn084(r, 2)          # 3★ 远程携带
	_ok("★★④ 远程携带拿到 10% 减伤(3★)",
		absf(float(r.get("damage_reduction", 0.0)) - 0.10) < 0.0001,
		"damage_reduction=%.3f" % float(r.get("damage_reduction", 0.0)))
	var hp_gain: float = float(r.get("maxHp", 0.0)) - hp_before
	## 3★ 基数 3000 × 射程换算倍率(≥1) ⇒ 至少 3000
	_ok("★★④ 远程携带的生命值 ≥ 3000(基数已从 1000 提到 3000)",
		hp_gain >= 3000.0 - 1.0,
		"maxHp 涨了 %.0f (倍率 %.2f)" % [hp_gain, float(r.get("_b84_mult", 1.0))])

	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 16:
		print("  [FAIL] ★分母: 断言只有 %d 条(<16) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 手半剑 084" if _fail == 0 else "FAIL x%d — 手半剑 084" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
