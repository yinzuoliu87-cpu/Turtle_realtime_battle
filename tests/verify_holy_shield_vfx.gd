extends Node
## verify_holy_shield_vfx.gd — 095【圣光护盾】逐件重做门禁 (2026-08-09)
##
## 分工: 赠送/收回/不占容量那一半在 `tests/verify_holy_shield_grant.gd`;
##       三条主动(怒气/反击/收殓)的数值在 `tests/verify_shield_synergy.gd`;
##       **这一份管两件事**:
##         (A) 规格文案 ↔ 代码常量 ↔ 属性表 逐条对齐, 且**分清装备本体与盾羁绊**;
##         (B) 演出"看不看得出来" —— 判据全部落在能被量出来的真实对象上。
##
## ⚠ 全部**同步断言**(CLAUDE.md §3.5): 调完入口下一行就判, 不等 tween、不数帧。
##    演出层本来就不用 tween(生命周期由 `tick(delta)` 自推), 所以测试可以直接喂 delta。
##
## ★不许恒真: 期望值一律写死字面量(3 / 55 / 2 / 250 / 1.2 …), 不去读被测常量当期望。
##   每组带分母 —— N=0 是空检查不是通过。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_holy_shield_vfx.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const HSV := preload("res://scripts/scenes/battle/holy_shield_vfx.gd")
const EquipStatsS := preload("res://scripts/gamedata/equip_stats.gd")

const HOLY := "p2eq_095"
## 盾羁绊 9 档给【所有圣盾值】的加成。★它是**羁绊**的数, 不是这件装备的数。
const TIER3_BONUS := 1.2

var _n := 0
var _fail := 0
var _s = null
var _sys = null
var _vfx = null


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
	if gs != null:
		gs.test_mode = true
	print("=== 095 圣光护盾: 规格对账 + 演出层 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_sys = _s._shield_syn
	_vfx = _sys._holy_vfx
	_ok("★分母: 盾羁绊系统真的持有 HolyShieldVfx", _vfx != null)
	_ok("★分母: 世界节点在(没有它一个特效都建不出来)",
		_s._world != null and is_instance_valid(_s._world))

	_t_spec_numbers()
	_t_item_vs_synergy()
	_t_riposte_real_entry()
	_t_aegis_tracks_riposte_switch()
	_t_geometry()
	_t_holdfade()
	_t_textures()
	_t_clear()
	_t_wiring()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 095 圣光护盾演出层" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 干净合成单位(照 verify_shield_synergy 的做法): 走真 `_make_unit` 再把要控的字段覆盖掉。
## ★不能用 "basic" —— 小龟有【不屈】被动(按稀有度增伤), 会让"反击 2 点"变成别的数。
func _mk(side: String, ids: Array, hp: float = 4000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var off := Vector2(-200.0, 0.0) if side == "left" else Vector2(200.0, 0.0)
	var u: Dictionary = _s._spawn._make_unit("green", side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0; u["base_def"] = 0.0
	u["mr"] = 0.0; u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	var e: Array = []
	for i in ids:
		e.append({"id": str(i), "star": 1})
	u["equips"] = e
	u["eq_state"] = {}
	return u


## 摆一队并把盾档位直接钉住(不靠凑件数 —— 那是 verify_holy_shield_grant 的活)。
func _stage(tier: int) -> Array:
	var me := _mk("left", [HOLY])
	var foe := _mk("right", [])
	_s._units.clear()
	_s._units.append_array([me, foe])
	_s._synergy._by_side = {"left": {"盾": tier}, "right": {}}
	_vfx.clear()
	_sys._t_holy = 0.0
	me["_shield_rage"] = 0.0
	return [me, foe]


# ─────────────────────────────────────────────────────────────
# ① 规格文案 ↔ 代码常量 ↔ 属性表
#    规格(data/phase2-equipment.json · effectDesc1):
#      「每 3 秒为携带者生成 55 点圣光护盾值; 圣光护盾存在时,
#        反击敌人的每段伤害造成 2 点真实伤害。」  属性 +生命 250
# ─────────────────────────────────────────────────────────────
func _t_spec_numbers() -> void:
	print("── ① 规格 ↔ 代码 逐条 ──")
	_ok("① 周期 = 3 秒", absf(_sys.HOLY_PERIOD - 3.0) < 0.001, "实得 %.2f" % _sys.HOLY_PERIOD)
	_ok("① 每次 55 点", absf(_sys.HOLY_AMOUNT - 55.0) < 0.001, "实得 %.1f" % _sys.HOLY_AMOUNT)
	_ok("① 反击 2 点真伤(固定值)", absf(_sys.RIPOSTE_FLAT - 2.0) < 0.001, "实得 %.1f" % _sys.RIPOSTE_FLAT)
	# 属性表(真事实源 = EquipStats.STATS, 不是 json 的 baseStats1)
	var st = EquipStatsS.STATS.get(HOLY, null)
	_ok("★分母: EquipStats 有 095 的三档属性", st is Array and (st as Array).size() == 3)
	if st is Array and (st as Array).size() == 3:
		var all250 := true
		for i in range(3):
			if absf(float(((st as Array)[i] as Dictionary).get("hp", 0.0)) - 250.0) > 0.001:
				all250 = false
		_ok("① 属性 = +生命 250(三星同值, 它不参与合成)", all250,
			"实得 %s" % str(st))
	# 文案里的数字必须与常量一致 —— 文案漂了这条会红(代码是终审, 文案跟代码走)
	var desc := ""
	for e in DataRegistry.phase2_equipment:
		if str((e as Dictionary).get("id", "")) == HOLY:
			desc = str((e as Dictionary).get("effectDesc1", ""))
	_ok("★分母: 找得到 095 的 effectDesc1", desc != "", "「%s」" % desc)
	var nums: Array = []
	var cur := ""
	for ch in desc:
		if ch >= "0" and ch <= "9":
			cur += ch
		elif cur != "":
			nums.append(int(cur)); cur = ""
	if cur != "":
		nums.append(int(cur))
	_ok("① 文案里的三个数 = [3, 55, 2](周期/盾量/反击)", nums == [3, 55, 2], "实得 %s" % str(nums))


# ─────────────────────────────────────────────────────────────
# ② 装备本体 vs 盾羁绊: 哪个数是谁的
#    ★这一组存在的理由: 55 是【装备】的, ×1.2 是【羁绊 9 档】的。
#      把它们混成一个数(比如把 66 写进 HOLY_AMOUNT)以后就再也分不开了。
# ─────────────────────────────────────────────────────────────
func _t_item_vs_synergy() -> void:
	print("── ② 装备本体 55 / 羁绊 9 档 ×1.2 ──")
	var duo := _stage(1)
	var me: Dictionary = duo[0]
	_sys.tick(3.01)
	_ok("② 1 档(=送出这件的那一档): 一次补 55, 【没有】任何羁绊加成",
		absf(float(me["shield"]) - 55.0) < 0.01, "实得 %.1f" % float(me["shield"]))
	_ok("② holy_bonus(1 档) = 1.0", absf(_sys.holy_bonus(me) - 1.0) < 0.001,
		"实得 %.2f" % _sys.holy_bonus(me))

	duo = _stage(3)
	me = duo[0]
	_sys.tick(3.01)
	_ok("② 9 档: 55 × 1.2 = 66 —— 多出来的 11 点是【羁绊】的, 不是装备的",
		absf(float(me["shield"]) - 55.0 * TIER3_BONUS) < 0.01, "实得 %.1f" % float(me["shield"]))
	_ok("② holy_bonus(9 档) = 1.2", absf(_sys.holy_bonus(me) - TIER3_BONUS) < 0.001,
		"实得 %.2f" % _sys.holy_bonus(me))

	# 补盾那一下的演出: 光柱 + 光粒 + 盾板当场出现
	_ok("② 补盾 ⇒ 一根圣光柱", _vfx.alive_count("pillar") == 1,
		"实得 %d" % _vfx.alive_count("pillar"))
	_ok("② 补盾 ⇒ 5 粒上飘光屑", _vfx.alive_count("mote") == 5,
		"实得 %d" % _vfx.alive_count("mote"))
	_ok("★② 盾板**当场**就在(不等下一帧的 tick —— 补盾那一帧正是最该看到它的一帧)",
		_vfx.aegis_node_of(me) != null)


# ─────────────────────────────────────────────────────────────
# ③ 反击走【真入口】on_damaged, 且演出与伤害同帧
#    ★不调 _riposte —— 那是内部函数; 真实链路是 `_apply_damage_from → on_damaged → _riposte`。
#      直接调内部函数的门禁守不住"还有没有人调它"(memory [[fb-verify-must-run-the-real-path]])。
# ─────────────────────────────────────────────────────────────
func _t_riposte_real_entry() -> void:
	print("── ③ 反击: 真入口 + 演出与伤害同帧 ──")
	var duo := _stage(1)
	var me: Dictionary = duo[0]
	var foe: Dictionary = duo[1]
	me["shield"] = 100.0
	var hp0: float = float(foe["hp"])
	_sys.on_damaged(me, foe, 10)          # ← 真入口(挂在 _apply_damage_from 的承伤钩上)
	var dealt: float = hp0 - float(foe["hp"])
	_ok("③ on_damaged(有盾) ⇒ 攻击者掉 2 点真伤", absf(dealt - 2.0) < 0.01,
		"实得 %.1f" % dealt)
	_ok("★③ 同一次调用返回时演出就在了(光矢): 伤害不等演出到达",
		_vfx.alive_count("beam") == 1, "实得 %d" % _vfx.alive_count("beam"))
	_ok("★③ 同一次调用返回时演出就在了(圣罚印)",
		_vfx.alive_count("smite") == 1, "实得 %d" % _vfx.alive_count("smite"))

	# 反向对照: 没盾 ⇒ 不打也不画
	duo = _stage(1)
	me = duo[0]; foe = duo[1]
	me["shield"] = 0.0
	hp0 = float(foe["hp"])
	_sys.on_damaged(me, foe, 10)
	_ok("③ 对照: 没有护盾值 ⇒ 不反击(「圣光护盾存在时」)",
		absf(hp0 - float(foe["hp"])) < 0.01, "敌掉 %.1f" % (hp0 - float(foe["hp"])))
	_ok("③ 对照: 没有护盾值 ⇒ 也不画光矢/圣罚印",
		_vfx.alive_count("beam") == 0 and _vfx.alive_count("smite") == 0,
		"beam %d / smite %d" % [_vfx.alive_count("beam"), _vfx.alive_count("smite")])

	# 反向对照: 有盾但没装 095 ⇒ 不打也不画
	duo = _stage(1)
	me = duo[0]; foe = duo[1]
	me["equips"] = []
	me["shield"] = 100.0
	hp0 = float(foe["hp"])
	_sys.on_damaged(me, foe, 10)
	_ok("③ 对照: 有盾但【没装 095】⇒ 不反击(反击来自这件装备, 不是档位)",
		absf(hp0 - float(foe["hp"])) < 0.01, "敌掉 %.1f" % (hp0 - float(foe["hp"])))


# ─────────────────────────────────────────────────────────────
# ④ ★★核心可读性: 盾板在不在 ⇔ 会不会反击, 两者【永远同步】
#    这是这一件重做的整个意义 —— 玩家看不出自己现在会不会反击, 就等于没有这条效果。
# ─────────────────────────────────────────────────────────────
func _t_aegis_tracks_riposte_switch() -> void:
	print("── ④ 盾板 ⇔ 反击开关 同步 ──")
	var cases := [
		{"holy": true,  "shield": 80.0, "want": true,
		 "name": "④ 装了 095 且有盾 ⇒ 盾板在, 且会反击"},
		{"holy": true,  "shield": 0.0,  "want": false,
		 "name": "④ 装了 095 但盾见底 ⇒ 盾板撤掉, 也不反击"},
		{"holy": false, "shield": 80.0, "want": false,
		 "name": "④ 没装 095 就算有盾 ⇒ 没有盾板, 也不反击"},
	]
	var checked := 0
	for c in cases:
		var duo := _stage(1)
		var me: Dictionary = duo[0]
		var foe: Dictionary = duo[1]
		if not bool(c["holy"]):
			me["equips"] = []
		me["shield"] = float(c["shield"])
		# 先喂两帧让常驻层跟上, 再喂足收尾时长(0.26 秒)让该撤的真的撤掉
		for _i in range(3):
			_vfx.tick(0.12)
		var has_board: bool = _vfx.aegis_node_of(me) != null
		var hp0: float = float(foe["hp"])
		me["shield"] = float(c["shield"])      # 上面几帧不会动它, 保险起见复位
		_sys.on_damaged(me, foe, 10)
		var will_riposte: bool = (hp0 - float(foe["hp"])) > 0.5
		_ok(str(c["name"]), has_board == bool(c["want"]) and will_riposte == bool(c["want"]),
			"盾板 %s / 反击 %s" % [str(has_board), str(will_riposte)])
		checked += 1
	_ok("★分母: 三种组合都验过了", checked == 3, "实得 %d" % checked)


# ─────────────────────────────────────────────────────────────
# ⑤ 量【真实对象】的几何 —— 不在测试里把公式抄一遍
#    (memory [[fb-write-without-reader-and-fake-gates]]: 门禁模拟公式 ≠ 量真实对象)
# ─────────────────────────────────────────────────────────────
func _t_geometry() -> void:
	print("── ⑤ 几何: 量节点本身 ──")
	var duo := _stage(1)
	var me: Dictionary = duo[0]
	me["shield"] = 80.0
	_vfx.tick(0.20)
	var s: Sprite3D = _vfx.aegis_node_of(me)
	_ok("★分母: 拿到了盾板节点", s != null)
	if s == null:
		return
	_ok("⑤ 盾板是 4 帧精灵条(素材筛过帧: 生成的 9 帧后半段跑色)", s.hframes == 4,
		"实得 %d" % s.hframes)
	_ok("⑤ 像素风必须最近邻采样(糊了就不是像素画)",
		s.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "实得 %d" % s.texture_filter)
	_ok("⑤ 关深度测试(不然被龟身压掉)", s.no_depth_test)
	# 世界宽度 = pixel_size × 单帧宽 ÷ WS。★由节点反算, 期望值写死 33 码。
	var frame_w: float = float(s.texture.get_width()) / float(maxi(1, s.hframes))
	var yards: float = s.pixel_size * frame_w / float(_s.WS)
	_ok("⑤ 盾板宽 ≈ 33 码(一只龟约 44 码 ⇒ 举得起来又不糊住龟)",
		absf(yards - 33.0) < 3.5, "实得 %.1f 码" % yards)
	# 位置: 不许留在原点(只在 tick 里写位置的话第一帧会画在地图 (0,0,0))
	_ok("★⑤ 盾板出生就摆到位, 不在世界原点", s.position.length() > 0.5,
		"实得 %s" % str(s.position))
	# 高度: 与 _world_pos(锚点, 0.88) 逐分量一致
	var want: Vector3 = _s._world_pos(Vector2(me["pos"]) + Vector2(15.0, 0.0), 0.88)
	_ok("⑤ 盾板挂在胸口高度 0.88 米、朝敌一侧偏 15 码", s.position.distance_to(want) < 0.05,
		"实得 %s / 期望 %s" % [str(s.position), str(want)])

	# 光柱: 底端要落在盾板上, 不许从头贯到脚(贯到脚实拍读成"插了根杆子")
	_vfx.clear()
	_vfx.grant_burst(me, 55.0)
	var pils: Array = _vfx.fx_nodes("pillar")
	var pil: Sprite3D = pils[0] if pils.size() == 1 else null
	_ok("★分母: 拿到了唯一一根光柱节点(%d 个)" % pils.size(), pil != null)
	if pil != null:
		var h_m: float = pil.pixel_size * float(pil.texture.get_height())
		var base_y: float = pil.position.y - h_m * 0.5
		var ground_y: float = _s._world_pos(Vector2(me["pos"]), 0.0).y
		_ok("⑤ 光柱底端 ≈ 盾板高度 0.88 米(不是 0 —— 贯到脚就是一根杆子)",
			absf((base_y - ground_y) - 0.88) < 0.06, "实得 %.2f 米" % (base_y - ground_y))


# ─────────────────────────────────────────────────────────────
# ⑥ 淡出病: 短命特效不许一出生就掉
#    ★量的是**真实节点的 modulate.a**, 不是 _holdfade 这个纯函数 ——
#      纯函数写对了而调用方不用它, 照样是淡出病。
# ─────────────────────────────────────────────────────────────
func _t_holdfade() -> void:
	print("── ⑥ 淡出病(前半程必须满亮) ──")
	var duo := _stage(1)
	var me: Dictionary = duo[0]
	var foe: Dictionary = duo[1]
	me["shield"] = 80.0
	# ★分两趟量, 不是图省事: 光屑是**错开入场**的(最后一粒延迟 0.12 秒), 与"最短寿命 0.24 秒
	#   的光矢还没走到 37%"这两个条件在同一个时刻上冲突 —— 第一版一趟量, 结果把
	#   "还没出场的光屑 alpha=0" 读成了淡出病(假 FAIL)。
	# 趟 A: 光柱 / 光矢 / 圣罚印 —— 喂 0.09 秒(最短的光矢也才走到 37%)
	_vfx.clear()
	_vfx.grant_burst(me, 55.0)
	_vfx.riposte(me, foe, 2.0)
	_vfx.tick(0.09)
	var dim: Array = []
	var counted := 0
	# ★用本层自己的清单, 不遍历 _world —— queue_free 的节点要到帧末才消失,
	#   同步门禁遍历 _world 会把上一组撤掉的旧节点(已经在淡出)也数进来 ⇒ 假 FAIL。
	for kind in ["pillar", "beam", "smite"]:
		for ch in _vfx.fx_nodes(kind):
			counted += 1
			if (ch as Sprite3D).modulate.a < 0.999:
				dim.append("%s a=%.2f" % [kind, (ch as Sprite3D).modulate.a])
	_ok("★分母: 光柱/光矢/圣罚印 三样都在(应为 3)", counted == 3, "实得 %d" % counted)
	_ok("⑥ 走到寿命 37% 时光柱/光矢/圣罚印**没有一个**已经在淡出", dim.is_empty(),
		"变暗的: %s" % str(dim))
	# 趟 B: 光屑 —— 喂到 0.20 秒。★这个数是**两头夹出来的**, 不是随手取的:
	#   下限 0.12 秒(最后一粒的错开延迟, 早于它那粒还没出场 alpha=0);
	#   上限 0.234 秒(第一粒 0.45×0.52 的满亮段到头)。0.20 在两者之间, 五粒同时满亮。
	_vfx.clear()
	_vfx.grant_burst(me, 55.0)
	_vfx.tick(0.20)
	var dim2: Array = []
	var motes: Array = _vfx.fx_nodes("mote")
	for ch in motes:
		if (ch as Sprite3D).modulate.a < 0.999:
			dim2.append("a=%.2f" % (ch as Sprite3D).modulate.a)
	_ok("★分母: 5 粒光屑都在", motes.size() == 5, "实得 %d" % motes.size())
	_ok("⑥ 光屑过了错开延迟后也是满亮(不是一出生就掉)", dim2.is_empty(),
		"变暗的: %s" % str(dim2))
	# 收尾前把趟 B 的东西喂完, 免得漏进下一组
	_vfx.grant_burst(me, 55.0)
	_vfx.riposte(me, foe, 2.0)
	# 喂满寿命 ⇒ 全部自销(不许挂着不走)
	_vfx.tick(1.2)
	_ok("⑥ 喂满寿命后一次性节点全部自销",
		_vfx.alive_count("beam") == 0 and _vfx.alive_count("smite") == 0
			and _vfx.alive_count("pillar") == 0 and _vfx.alive_count("mote") == 0,
		"beam %d smite %d pillar %d mote %d" % [_vfx.alive_count("beam"),
			_vfx.alive_count("smite"), _vfx.alive_count("pillar"), _vfx.alive_count("mote")])


# ─────────────────────────────────────────────────────────────
# ⑦ 素材: 两张本件专用新图 + 三张程序化零素材
#    ★最后一条守的是实拍抓到的真毛病: 半透明的近白在黑底上合成出来【就是灰】——
#      第二版光柱实测 RGB(228,236,218)、饱和度 0.08, 台上读成"插了根铁杆"。
# ─────────────────────────────────────────────────────────────
func _t_textures() -> void:
	print("── ⑦ 素材与配色 ──")
	var ax: Texture2D = HSV.aegis_tex()
	var sx: Texture2D = HSV.smite_tex()
	_ok("★分母: 两张素材都载得到", ax != null and sx != null)
	if ax == null or sx == null:
		return
	_ok("⑦ 盾板 = 64×64 的 4 帧条(256×64)",
		ax.get_width() == 256 and ax.get_height() == 64,
		"实得 %dx%d" % [ax.get_width(), ax.get_height()])
	_ok("⑦ 圣罚印 = 64×64 的 9 帧条(576×64)",
		sx.get_width() == 576 and sx.get_height() == 64,
		"实得 %dx%d" % [sx.get_width(), sx.get_height()])
	_ok("⑦ 素材是本件专用的新图(路径带 eq095-)",
		ax.resource_path.find("eq095-holy-aegis") >= 0
			and sx.resource_path.find("eq095-holy-smite") >= 0,
		"%s / %s" % [ax.resource_path, sx.resource_path])
	_ok("⑦ 三张小件是程序化现算的(resource_path 是空串 = 不是从磁盘 load 的)",
		HSV.pillar_tex().resource_path == "" and HSV.mote_tex().resource_path == ""
			and HSV.beam_tex().resource_path == "",
		"%s|%s|%s" % [HSV.pillar_tex().resource_path, HSV.mote_tex().resource_path,
			HSV.beam_tex().resource_path])
	# ★量分布不量极值: 取 alpha > 0.5 的像素, 看饱和度的【中位数】
	for pair in [["光柱", HSV.pillar_tex()], ["光矢", HSV.beam_tex()], ["光屑", HSV.mote_tex()]]:
		var img: Image = (pair[1] as ImageTexture).get_image()
		var sats: Array = []
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c: Color = img.get_pixel(x, y)
				if c.a <= 0.5:
					continue
				var mx: float = maxf(c.r, maxf(c.g, c.b))
				var mn: float = minf(c.r, minf(c.g, c.b))
				sats.append(0.0 if mx <= 0.001 else (mx - mn) / mx)
		sats.sort()
		var med: float = 0.0 if sats.is_empty() else float(sats[sats.size() / 2])
		_ok("★分母: %s 取到 %d 个不透明像素" % [str(pair[0]), sats.size()], sats.size() >= 60)
		_ok("⑦ %s 不是【半透白】(饱和度中位数 > 0.30, 否则黑底上合成出来就是灰)" % str(pair[0]),
			med > 0.30, "实得 %.2f" % med)


# ─────────────────────────────────────────────────────────────
# ⑧ 撤场(换路时没人替它清 —— 它挂在 _world 上, 不是单位的子节点)
# ─────────────────────────────────────────────────────────────
func _t_clear() -> void:
	print("── ⑧ 撤场 ──")
	var duo := _stage(1)
	var me: Dictionary = duo[0]
	var foe: Dictionary = duo[1]
	me["shield"] = 80.0
	_vfx.tick(0.2)
	_vfx.grant_burst(me, 55.0)
	_vfx.riposte(me, foe, 2.0)
	var before: int = _vfx.alive_count()
	_ok("★分母: 撤场前场上有 %d 个本层节点" % before, before >= 8)
	var freed: int = _vfx.clear()
	_ok("⑧ clear() 报告拔掉的个数 = 撤场前的个数", freed == before,
		"freed %d / before %d" % [freed, before])
	_ok("⑧ clear() 之后一个不剩(含常驻盾板)",
		_vfx.alive_count() == 0 and _vfx.aegis_node_of(me) == null,
		"实得 %d" % _vfx.alive_count())


# ─────────────────────────────────────────────────────────────
# ⑨ 接线: 三个入口挂在【对的位置】
#    ★"函数存在"守不住"还有没有人调、调在哪一行"(memory [[fb-verify-must-run-the-real-path]])。
#      这一组读源码比行号 —— 顺序错了效果就是错的:
#        · tick 必须在 `_t_holy < HOLY_PERIOD` 的提前 return 之【前】(不然常驻盾板每 3 秒才动一帧)
#        · grant_burst 必须在 `_grant_shield` 之【后】(不然那一帧 shield 还是 0, 盾板不出现)
#        · riposte 必须在 `_apply_damage_from` 之【后】(演出跟伤害同帧, 且不抢在结算前面)
# ─────────────────────────────────────────────────────────────
func _t_wiring() -> void:
	print("── ⑨ 接线位置(读源码比行号) ──")
	var src := FileAccess.get_file_as_string("res://scripts/systems/equip/shield_synergy_system.gd")
	_ok("★分母: 读到了 shield_synergy_system.gd(%d 字符)" % src.length(), src.length() > 2000)
	var lines: PackedStringArray = src.split("\n")
	var ln_tick := -1
	var ln_period_ret := -1
	var ln_grant := -1
	var ln_burst := -1
	var ln_dmgfrom := -1
	var ln_riposte := -1
	var ln_clear_vfx := -1
	for i in range(lines.size()):
		var t: String = lines[i]
		# ★★只认【代码行】, 跳过注释 —— 第一版就栽在这: 锚点 `_t_holy < HOLY_PERIOD`
		#   先命中了 tick 头注里引用同一句话的那行注释(第 174 行), 于是"驱动在 return 之前"
		#   被判成红, 而代码其实是对的(182 < 184)。**读源码的门禁必须先滤掉注释。**
		if t.strip_edges().begins_with("#"):
			continue
		if ln_tick < 0 and t.find("_holy_vfx.tick(") >= 0:
			ln_tick = i
		if ln_period_ret < 0 and t.find("if _t_holy < HOLY_PERIOD:") >= 0:
			ln_period_ret = i
		if ln_grant < 0 and t.find("_grant_shield(u, amt)") >= 0:
			ln_grant = i
		if ln_burst < 0 and t.find("_holy_vfx.grant_burst(") >= 0:
			ln_burst = i
		if ln_dmgfrom < 0 and t.find("_apply_damage_from(u, src, int(RIPOSTE_FLAT)") >= 0:
			ln_dmgfrom = i
		if ln_riposte < 0 and t.find("_holy_vfx.riposte(") >= 0:
			ln_riposte = i
		if ln_clear_vfx < 0 and t.find("_holy_vfx.clear()") >= 0:
			ln_clear_vfx = i
	_ok("★分母: 六个锚点都找得到",
		ln_tick >= 0 and ln_period_ret >= 0 and ln_grant >= 0 and ln_burst >= 0
			and ln_dmgfrom >= 0 and ln_riposte >= 0 and ln_clear_vfx >= 0,
		"tick %d / ret %d / grant %d / burst %d / dmg %d / rip %d / clear %d" % [
			ln_tick, ln_period_ret, ln_grant, ln_burst, ln_dmgfrom, ln_riposte, ln_clear_vfx])
	_ok("★⑨ 每帧驱动在【3 秒提前 return 之前】(放后面 ⇒ 常驻盾板每 3 秒才动一帧)",
		ln_tick >= 0 and ln_period_ret >= 0 and ln_tick < ln_period_ret,
		"tick 行 %d / return 行 %d" % [ln_tick, ln_period_ret])
	_ok("⑨ grant_burst 在 _grant_shield 之后(否则那一帧 shield 还是 0, 盾板不出现)",
		ln_grant >= 0 and ln_burst > ln_grant, "grant %d / burst %d" % [ln_grant, ln_burst])
	_ok("⑨ riposte 演出在伤害结算之后(同帧, 且不抢在结算前面)",
		ln_dmgfrom >= 0 and ln_riposte > ln_dmgfrom,
		"dmg %d / rip %d" % [ln_dmgfrom, ln_riposte])
	# 换路撤场: dual_lane_flow 每次换路都调 ShieldSynergySystem.clear()
	var dl := FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	_ok("⑨ 换路真的会调到本系统的 clear()(它才会带走盾板)",
		dl.find("_shield_syn.clear()") >= 0)
