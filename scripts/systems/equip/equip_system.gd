class_name EquipSystem
extends RefCounted
## 装备效果系统(从 RealtimeBattle3DScene 抽出·2026-07-25)。持 battle 引用回调场景。
## 【装备与角色技能分开管理·用户定向】所有 _eq_/_tick_eq_ 效果在此; 类内名字不变, 外部名加 battle.

var battle
## on-hit 暴击态对账(仅供门禁读): gap=传进来的与全局不一致的次数(=缺口真实频率)
## nopass=有人调 on-hit 却没传 crit(将来新代码忘了传就会被抓)
var _eq_crit_gap := 0
var _eq_crit_nopass := 0
var _sigwave: SignalWaveSystem   # 信号放大器038 的弧形电磁波(2026-07-31 重做·单独成文件: 上帝文件已卡在 arch_budget 8600)
var _stats: EquipStatsApply   # 被动属性/flag 应用子系统(2026-07-26 从本文件分出·spawn期·区别于主动效果)
var _spirit_sys: EqSpiritBatch   # 灵物 5 件(060~064)用户重做版(2026-08-05·效果本体在 eq_spirit_batch.gd)
var _potion_sys: EqPotionBatch   # 药水 4 件(065~068)用户重做版(2026-08-05·效果本体在 eq_potion_batch.gd)
var _food_sys: EqFoodBatch   # 食物 4 件(069~072)用户重做版(2026-08-05·效果本体在 eq_food_batch.gd)
var _bow_sys: EqBowBatch   # 弓箭 4 件(073~076)用户重做版(2026-08-05·效果本体在 eq_bow_batch.gd·演出在 battle/bow_eq_vfx.gd)
# ── 批④(2026-08-06) 用户逐件重做的后 17 件 · 一类一个批系统 ────────────────────
#    ★统一接口(十个钩子: tick/tick_unit/on_spawn/on_basic/on_hit/on_damaged/
#      on_magic_hurt/on_death/on_mana_full/clear_all) —— 派发在本文件, 效果本体各自成文件。
#    ★这一批【一件都不用 EQ_PERIOD】: 077/079/080 从"每 8 秒放一次"改成了"登场召唤一个
#      持续存在的东西", 081/087/091/094 的节拍要么随星级变、要么是触发式, EQ_PERIOD 那张
#      "每 id 一个常数"的表装不下 ⇒ 全部自管计时(与灵物/食物两批同)。
var _gun_sys: EqGunBatch         # 枪 4 件(077~080)·eq_gun_batch.gd
var _blade_sys: EqBladeBatch     # 盾+剑 4 件(081~084)·eq_blade_batch.gd
var _gadget_sys: EqGadgetBatch   # 奇械 3 件(085~087)·eq_gadget_batch.gd
var _arcane_sys: EqArcaneBatch   # 法器 3 件(088~090)·eq_arcane_batch.gd
var _relic_sys: EqRelicBatch     # 遗物 2 件(091/094)·eq_relic_batch.gd
var _incense: IncenseStoneSystem # 093 香火石(跨对局养成·要落存档)·incense_stone_system.gd
## 092 剧毒飞行物(2026-08-05·遗物·2费): 常驻召唤飞行体 + 地面毒雾场 + 剧毒缓速叠层, 单独成文件。
## ★每帧驱动接在 RelicSynergySystem.tick()、撤场接在它的 clear() —— 理由见 eq_venom_drone.gd 文件头判断 ③。
const VENOM_DRONE := preload("res://scripts/systems/equip/eq_venom_drone.gd")
var _venom
var _eq_drone_halve: bool = false   # 无人机减半标记(随本系统)
## 古灵精怪枪(2026-08-31): FPGA板登场塞给敌人的"毒苹果"。
## ★归【装备层】所有而不是主场景 —— 它是装备效果, 按 CLAUDE.md「新代码放哪」该进 systems/equip;
##   而且主文件有架构预算(只减不增), 我第一版加在那里当场把预算撑红了。
var _gremlin: GremlinGun
## 096 小木斧(2026-08-31·三期): 斧头召唤物 + 通用主动 + 被动2 窃盾。
var _axe: AxeSystem
## 011 饮血护符坠(2026-09-10 重做): 连斩本体 + 斩痕演出。单独成文件 —— 见 eq_blood_combo.gd 文件头。
var _blood_sys: EqBloodCombo

func _init(b) -> void:
	battle = b
	_stats = EquipStatsApply.new(b)
	_sigwave = SignalWaveSystem.new(b)
	_spirit_sys = EqSpiritBatch.new(b)
	_potion_sys = EqPotionBatch.new(b)
	_food_sys = EqFoodBatch.new(b, self)
	_bow_sys = EqBowBatch.new(b)
	_venom = VENOM_DRONE.new(b)
	_gremlin = GremlinGun.new(b)
	_axe = AxeSystem.new(b)
	_gun_sys = EqGunBatch.new(b)
	_blade_sys = EqBladeBatch.new(b)
	_gadget_sys = EqGadgetBatch.new(b)
	_arcane_sys = EqArcaneBatch.new(b)
	_blood_sys = EqBloodCombo.new(b)
	_relic_sys = EqRelicBatch.new(b)
	_incense = IncenseStoneSystem.new(b)


## 批④ 的六个批系统, 按【本批装备 id → 系统】路由。派发点全都先查这张表再调统一钩子。
## ★不写成 `match` 是因为同一张表要被十个钩子共用 —— 抄十遍就是"手抄的副本必然落后"。
const B4_OWNER := {
	"p2eq_077": "gun", "p2eq_078": "gun", "p2eq_079": "gun", "p2eq_080": "gun",
	"p2eq_081": "blade", "p2eq_082": "blade", "p2eq_083": "blade", "p2eq_084": "blade",
	"p2eq_085": "gadget", "p2eq_086": "gadget", "p2eq_087": "gadget",
	"p2eq_088": "arcane", "p2eq_089": "arcane", "p2eq_090": "arcane",
	"p2eq_091": "relic", "p2eq_094": "relic",
	"p2eq_093": "incense",
}

## 取某件批④装备的宿主系统; 不是批④的件返回 null。
func _b4(eid: String):
	match B4_OWNER.get(eid, ""):
		"gun": return _gun_sys
		"blade": return _blade_sys
		"gadget": return _gadget_sys
		"arcane": return _arcane_sys
		"relic": return _relic_sys
		"incense": return _incense
	return null


## 批④ 的六个系统(供 tick / clear_all / 换路撤场遍历)。
func _b4_all() -> Array:
	return [_gun_sys, _blade_sys, _gadget_sys, _arcane_sys, _relic_sys, _incense]


## 批④ 专用的【DoT/真伤路】受伤钩 —— CLAUDE.md §3.3 的另一半。
##
## ★为什么不直接给 `_eq_on_target` 补全路: 那个钩子还挂着 013/014 受击硬化、
##   015 荆棘海胆反伤、冰封反制等**已上线**的装备。让它们从每一跳灼烧/中毒触发是
##   **行为变更** —— 会静默把那些装备的强度改掉, 而且没有任何门禁会红。
##   同一手法在 068 深海气压罐上已用过一次(battle_damage.gd 的窄口)。
##
## ★本批里谁需要吃全路(照 §0.5 规格):
##   · 081 藤编圆盾   充能条数的是"累计受到自身 N% 最大生命值的**伤害**" ⇒ 要
##   · 085 压电陶瓷片 "将**受到的伤害** 5/9/15% 转化为龟能"(用户明确: DoT 每跳算) ⇒ 要
##   · 087 盗令潜水钟 "**受到的伤害**先灌进压载舱" ⇒ 要
##   · 082 砗磲护心甲 "每次受到**一段攻击**"(用户明确: DoT 每跳**不算**) ⇒ **不要**
##
## ★口径标志 `u["_b4_dot"]`: 进这条路时置 true, 走 `_eq_on_target`(普攻/技能路)时置 false。
##   082 在自己的 `on_damaged` 里读它来排除 DoT。**不改 `on_damaged` 的签名** ——
##   五路并行实装中, 改签名等于同时动五个人正在写的文件。
func _b4_on_damaged_any(u: Dictionary, src, dmg: int) -> void:
	if u.get("equips", []).is_empty():
		return
	u["_b4_dot"] = true
	for e in u["equips"]:
		if not (e is Dictionary):
			continue
		var iid: String = str((e as Dictionary).get("id", ""))
		var sys = _b4(iid)
		if sys != null:
			sys.on_damaged(u, src, float(dmg), iid, _eq_si(int((e as Dictionary).get("star", 1))))
	u["_b4_dot"] = false

func _eq_on_basic_attack(u: Dictionary, tgt = null) -> void:   # 每普攻(不算多段): 008珊瑚刺计数 / 017不沉之锚普攻消耗充能锚击
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) == "p2eq_017":   # 不沉之锚: 每次普攻消耗1沉锚充能→击飞最前敌+眩晕(用户2026-07-02)
			var ast: Dictionary = u["eq_state"].get("p2eq_017", {})
			if int(ast.get("anchor_charges", 0)) > 0:
				var at = battle._targeting._nearest_enemy(u)
				if at != null:
					var si17: int = _eq_si(int(e.get("star", 1)))
					ast["anchor_charges"] = int(ast["anchor_charges"]) - 1
					u["anchor_swing_t"] = battle._t   # 本发普攻算"持有充能"→攻速×2 (用户2026-07-19)
					var adm: int = battle._resolve_dmg(u, [0.4, 0.6, 3.0][si17] * (u["def"] + u["mr"]) + at["maxHp"] * [0.06, 0.15, 0.70][si17], at, false)   # 用户2026-07-19: 原裸值不吃护甲=真伤, 改走护甲(物理必吃甲)
					battle._damage._apply_damage_from(u, at, adm, Color("#9be7ff"), 0.0, false, true)
					battle._damage._knockback(u, at, 60.0); battle._freeze(at, battle.CTRL_SEC)
					battle._skill_ring(at["pos"], Color(0.6, 0.85, 1.0, 0.6), 60.0)
					u["eq_state"]["p2eq_017"] = ast
		if str(e["id"]) == "p2eq_039":   # 竹制弓箭: 每第3段普攻消耗1次生长充能→射强化竹箭(用户2026-07-19)
			var b39: Dictionary = u["eq_state"].get("p2eq_039", {})
			b39["bamboo_hits"] = int(b39.get("bamboo_hits", 0)) + 1
			if int(b39["bamboo_hits"]) >= 3 and int(b39.get("bamboo_charges", 0)) > 0:
				var t39 = battle._targeting._nearest_enemy(u)
				if t39 != null:
					b39["bamboo_hits"] = 0
					b39["bamboo_charges"] = int(b39["bamboo_charges"]) - 1
					var si39: int = _eq_si(int(e.get("star", 1)))
					# 回血+永久成长延到绿球落回自己身上才生效(竹叶龟同款)
					battle._spawn_bamboo_arrow(u, t39, [25, 30, 35][si39] + int(u["maxHp"] / battle.HP_MULT * BAMBOO_ARROW_MAXHP_PCT), [50.0, 70.0, 90.0][si39])
			u["eq_state"]["p2eq_039"] = b39
		if str(e["id"]) == "p2eq_027" and tgt != null and tgt is Dictionary and tgt.get("alive", false):   # 电棍: 就绪→本次普攻消耗1层附魔法伤+眩晕(用户2026-07-03)
			var bst: Dictionary = u["eq_state"].get("p2eq_027", {})
			if bst.get("baton_ready", false) and int(bst.get("baton_charges", 0)) > 0:
				var si27: int = _eq_si(int(e.get("star", 1)))
				bst["baton_charges"] = int(bst["baton_charges"]) - 1
				bst["baton_ready"] = false; bst["baton_cd"] = 0.0
				u["eq_state"]["p2eq_027"] = bst
				battle._damage._apply_damage_from(u, tgt, battle._resolve_dmg(u, float([30, 40, 50][si27]), tgt, true), Color("#7ecbff"), 0.0, false, true)
				battle._freeze(tgt, [2.5, 2.5, 3.0][si27])   # 眩晕 1.5s(CTRL_SEC默认) → 2.5/2.5/3 按星级(用户2026-07-19)
				battle._vfx.baton_strike(tgt)   # 落雷劈在被打中的那一个身上(原来是一颗对称白色星爆, 读不出「电」)
		# ── 批④(2026-08-06) 后 17 件: 统一路由到各自的批系统 ──────────────────
		#    ★这里原来是 078「双管贝壳枪·普攻概率追加一发」。078 已被用户整条重做成
		#      【电鳗双管铳】(左右管每 2 秒交替), 触发时机从"普攻"变成"自管计时" ⇒
		#      旧分支整段删除, 不是搬家。别把它加回来 —— 加回来就是两套效果叠着生效。
		var _b4o = _b4(str(e["id"]))
		if _b4o != null:
			_b4o.on_basic(u, tgt, str(e["id"]), _eq_si(int(e.get("star", 1))))
		# ── 药水 3 件(2026-08-05 用户逐件重做·§0.5 定稿) ─────────────────────
		#    ★效果本体在 eq_potion_batch.gd, 这里只留一行分派(同批②的口径:
		#      tooltip_number_audit 认 `"id": _fn(` 这种分派并把函数定义处也当锚点)。
		match str(e["id"]):
			"p2eq_065": _potion_sys._eq_shark_oil(u, _eq_si(int(e.get("star", 1))))
			"p2eq_068": _potion_sys._eq_pressure_sip(u, _eq_si(int(e.get("star", 1))))
		if str(e["id"]) == "p2eq_067" and tgt != null and tgt is Dictionary and tgt.get("alive", false):
			_potion_sys._eq_poison_touch(u, tgt, _eq_si(int(e.get("star", 1))))
		# ── 弓箭 3 件(2026-08-05 用户逐件重做·§0.5 定稿) ─────────────────────
		#    ★三件的触发时机都是【普攻】不是【命中】(用户原文都写"每次普攻") ⇒ 挂这个钩,
		#      不挂 _eq_on_hit: 一次普攻只算一下, 多段技/DoT 不算。
		#    ★效果本体在 eq_bow_batch.gd, 这里只留一行分派。
		match str(e["id"]):
			"p2eq_073": _bow_sys.on_basic_073(u, _eq_si(int(e.get("star", 1))))
			"p2eq_074": _bow_sys.on_basic_074(u, tgt, _eq_si(int(e.get("star", 1))))
			"p2eq_076": _bow_sys.on_basic_076(u, tgt, _eq_si(int(e.get("star", 1))))
		# 珊瑚刺008: 旧「每5次普攻」计数器已删(与_tick_coral每9秒重复触发·用户2026-07-19)



func _eq_ice_fissure(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	## ★2026-09-13 删掉这里原有的 `battle._shield_bubble(u)`:
	##   它是 029 **自绘的一个护盾泡** —— 而 `_grant_shield` 里早就有【通用护盾罩】
	##   `_vfx.shield_shell`(2026-09-11 用户否掉地上金圈之后做的, 罩在单位身上)。
	##   两个叠着放 ⇒ 通用罩被自绘的球盖住。而那个球还同时违反两条硬约束:
	##     · 贴图是 `VfxTex._make_fire_glow_tex()` **程序生成的光球**(实拍是一个把龟整个
	##       吞掉的不透明米色实心球)
	##     · 靠 `tween_property(spr, "pixel_size", …)` **连续缩放像素贴图**(被否过的那个糊)
	##   memory [[fb-fix-the-shared-primitive-not-one-instance]] / [[fb-hand-rolled-copies-drift]]:
	##   共享原语到位之后, 单件的手抄副本就是【永远落后一次】的那一份, 该删不该留。
	battle._damage._grant_shield(u, [100.0, 160.0, 250.0][si])   # 释放即上盾一次(通用罩由 _grant_shield 自己画)
	var t = battle._targeting._nearest_enemy(u)
	if t == null:
		return
	var dir: Vector2 = (t["pos"] - u["pos"]).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	battle._anticipate(u)                                 # 蓄力砸地
	## ★蓄力从 tween 挪到游戏钟(2026-09-13): 同 028, 不挪的话**冰道根本不推出去**。
	battle._equip_tick_sys.schedule(IceSystem.FISSURE_WINDUP,
		battle._ice_sys._ice_fissure_go.bind(u, si, u["pos"], dir))

# 水晶碎片火花: 弹出+缓旋+淡出 (光束/引爆/扫射点缀)
# 030 单段水晶光束结算: 从携带者当前位置沿 dir 无限直线, 全线敌魔法伤+1层水晶
func _eq_crystal_line(u: Dictionary, si: int) -> void:   # 迷你水晶球A030: 【法力条集满】时朝最近敌方向连发2/2/3段贯穿光束(错峰0.2s)。★不是周期件: 030/031 都不在 _EQ_CUSTOM_IV / EQ_IV_BATCH1 里, 触发口是 fire_equip_effect(由 StaffSynergySystem 在法力满时调)
	if not u.get("alive", false): return
	var t4 = battle._targeting._nearest_enemy(u)
	if t4 == null: return
	var dir2: Vector2 = (t4["pos"] - u["pos"]).normalized()
	if dir2 == Vector2.ZERO: dir2 = Vector2.RIGHT
	## ★★2026-08-14 从 tween 改走 `_pending_shots`(sim 时钟)。
	##   原来用 `_reg_tween().tween_interval().tween_callback()` 排这 2/3 段 ——
	##   **tween 在无头下推不进**(CLAUDE.md §3.5), 所以门禁永远量不到这件装备的效果,
	##   `verify_staff_actives_fire` 只能把它登记进 TWEEN_BURIED 当已知缺口。
	##   `_pending_shots` 走的是战斗时钟, 无头下照常到点 ⇒ 判据可以落在真实伤害上。
	##   ★节拍与数值一个都没动: 仍是每段 0.2 秒、仍调同一个 `_crystal_line_seg`。
	## ★2026-07-27 那条旧注释仍然成立: `_crystal_line_seg` 住在 CrystalSystem(2026-07-25 抽出),
	##   写成 `battle._crystal_line_seg` 会每次触发刷 SCRIPT ERROR 且光束完全不结算。
	for _seg in range([2, 2, 3][si]):
		battle._pending_shots.append({"delay": float(_seg) * CrystalSystem.LINE_SEG_GAP, "src": u, "fn":
			battle._crystal_sys._crystal_line_seg.bind(u, si, dir2)})

# 031: 水晶射线360度扫一圈(1.5s), 射线扫到敌人即结算魔法伤+叠层
func _eq_crystal_sweep(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	var center: Vector2 = u["pos"]
	var reach: float = CrystalSystem.SWEEP_REACH
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD   # 加色发光(水晶能量)
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	im.set_meta("mat", mat)
	battle._world.add_child(im)
	var start_a: float = randf() * TAU
	var state: Dictionary = {"prev": start_a}
	battle._crystal_sys._crystal_spark(center, 1.1)
	## ★结算走 sim 时钟(2026-08-14): 原来这里是
	##   `tween_method(..., 1.5).set_trans(CUBIC).set_ease(EASE_IN_OUT)` ——
	##   **tween 在无头下推不动**, 门禁永远量不到这件的伤害(CI 上还因此翻车过一次)。
	##   缓动曲线在 `CrystalSystem.tick` 里照抄原式, 观感不变。
	battle._crystal_sys.sweep_begin(u, si, reach, state, im, imesh, mat, start_a)

# 032: 登场召唤亡灵骷髅 (双抗为 0, 靠 _dmg_cap_one 把任何一击钳成 1 = 近乎免疫; 存活 13/17/23s 自灭, 死亡 200 码内 8/13/20% 最大生命真伤)
func _eq_summon_turret(u: Dictionary, si: int) -> void:   # 穿甲遗弹058(重做): 登场召唤不可移动的炮台
	if not u.get("alive", false): return
	var tr = battle._spawn._spawn_summon(u, "turret", [500.0, 1000.0, 1800.0][si], [20.0, 30.0, 45.0][si],
		{"label": "炮台", "spr_id": "turret", "col_size": 44.0, "hp_w": 32.0,
		 "atk_interval": 1.0 / TURRET_ASPD, "atk_range": TURRET_RANGE, "move_spd": 0.0, "melee": false})
	if tr == null: return
	tr["eq_state"] = {}; tr["equips"] = []
	tr["_eq_turret"] = true
	tr["_turret_si"] = si
	tr["move_spd"] = 0.0; tr["no_move"] = true      # 移速为0
	tr["crit"] = 0.0; tr["armor_pen"] = 0.0
	u["_turret_ref"] = tr                            # 只用 is_same 比较, 绝不当Dict键/深比较
	# 登场演出: 蓝白部署环 + 起降形变
	battle._splash_ring_bold(tr["pos"], Color(0.42, 0.82, 1.0), 110.0)
	battle._skill_ring(tr["pos"], Color(0.5, 0.88, 1.0, 0.7), 62.0)
	if is_instance_valid(tr["sprite"]):
		var bs: Vector3 = tr["sprite"].scale
		tr["sprite"].scale = Vector3(bs.x * 1.3, 0.05, bs.z)
		var dtw = battle._reg_tween()
		dtw.tween_property(tr["sprite"], "scale", bs, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _tick_eq_turret(u: Dictionary, delta: float) -> void:   # 058: 炮台双抗随携带者存活 / 携带者在400码内得攻速 / 锁定红线
	var tr = u.get("_turret_ref", null)
	if not (tr is Dictionary):
		return
	if not tr.get("alive", false):
		u["_turret_aspd_mult"] = 1.0
		battle._update_turret_line(tr)
		return
	var si: int = int(u.get("_turret_si", 0))
	var res: float = ([70.0, 85.0, 100.0][si] if u.get("alive", false) else 0.0)   # 携带者阵亡→双抗归零
	if absf(float(tr.get("base_def", -1.0)) - res) > 0.01:
		tr["base_def"] = res; tr["base_mr"] = res
		battle._recalc_stats(tr)
	var near: bool = u.get("alive", false) and (u["pos"] - tr["pos"]).length() <= TURRET_BUFF_R
	u["_turret_aspd_mult"] = (1.0 + [0.20, 0.30, 0.40][si]) if near else 1.0   # 直接赋值(不累加·不会泄漏)
	battle._update_turret_line(tr)

func _eq_summon_skeleton(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	# 亡灵骷髅移速=近战斗士档110(用户2026-07-28移速定位化: 原 130 比全表任何龟都快)
	# ★2026-08-01 用户重定义: 血 16/31/55 · 攻 3/5/8 · 双抗 0 · 受任何伤害(含真伤)恒为 1 · 存活 13/17/23 秒。
	#   ★血【不乘 HP_MULT】: 用户给的是"拥有 16/31/55 最大生命值", 那是游戏里能看见的最终值。
	#     旧写法 [19,21,25]×3 = 57/63/75, 属于 CLAUDE.md §3.1 那类"多乘一次"的旧账 —— 顺手清掉。
	#   ★双抗 20000 → 0: 免伤改由 _dmg_cap_one 走减伤收口实现。用双抗堆到 20000 的老办法【拦不住真伤】,
	#     而用户点名"包括真实伤害"。两者并存还会让"受 1 点"变成"受 0 点"(被抗性吃光后再钳)。
	var sk = battle._spawn._spawn_summon(u, "skeleton", [16.0, 31.0, 55.0][si], [3.0, 5.0, 8.0][si], {"label": "亡灵骷髅", "spr_id": "skeleton", "col_size": 32.0, "hp_w": 22.0, "atk_interval": 1.0 / 1.2, "atk_range": 70.0, "melee": true, "move_spd": 110.0})
	if sk == null: return
	sk["base_def"] = 0.0; sk["base_mr"] = 0.0; sk["def"] = 0.0; sk["mr"] = 0.0
	sk["_dmg_cap_one"] = true             # 收到的任何攻击(含真伤)降为 1 —— 闸在 _mitigate_incoming 末尾, 两条伤害路径共用
	sk["summon_life"] = [13.0, 17.0, 23.0][si]
	sk["boom_pct_true"] = [0.08, 0.13, 0.20][si]
	sk["boom_radius"] = 200.0
	battle._skill_ring(sk["pos"], Color(0.4, 1.0, 0.55, 0.6), 40.0)
	for k in range(5):
		battle._bone_speck(sk["pos"] + Vector2(randf_range(-24, 24), randf_range(-24, 24)))
	if is_instance_valid(sk["sprite"]):
		var base_sc: Vector3 = sk["sprite"].scale
		sk["sprite"].scale = Vector3(base_sc.x, 0.05, base_sc.z)
		var tw = battle._reg_tween()
		tw.tween_property(sk["sprite"], "scale", base_sc, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 批① 周期类新装备(2026-08-04)的触发间隔(秒)。
## ★为什么另开一张表而不是往主场景的 `_EQ_CUSTOM_IV` 里加:
##   那张表住在 RealtimeBattle3DScene.gd —— 上帝文件, 且【间隔本身就是装备效果的一部分】,
##   放在效果代码旁边比放在主场景里更贴。两张表【只影响"多久触发一次"】,
##   分发口仍然只有 `fire_equip_effect` 一个(方案书 §1.3 铁律: 不许再造周期分发)。
## ★法器三件(088/089/090)【不在表里】—— 它们的触发时机是"法力条满", 由 StaffSynergySystem
##   走同一个 `fire_equip_effect`。给它们排周期就会变成"既定时又法力满"两套行为。
const EQ_IV_BATCH1 := {
	# ★p2eq_062 原来在这里(旧「雾行海葵」每 2.5 秒叠雾隐)。2026-08-05 用户把 062 整条重做成
	#   【螳螂虾钳】(闪避后蓄一发强化普攻), 它不再是周期类 ⇒ 从这张表里摘掉。
	#   摘掉而不是留个 0: 留 0 会让 `_tick_eq_intervals` 每帧多查一次永远不成立的分支。
	# ★食物三件(069/070/072)原来也在这里(旧"每 2.5 秒回血 / +最大生命 / 全队回血")。
	#   2026-08-05 用户把食物四件整条重做(三块糖糕 / on-hit+灰条 / 变身礼盒),
	#   全部不再是周期类 ⇒ 一并摘掉。效果本体在 eq_food_batch.gd, 走每帧 `_eq_tick` 的常驻守卫。
	"p2eq_067": VIAL_IV,   # 毒药瓶(药水·4费): 每几秒朝敌人最密集处投一个瓶子(用户规格「每 6 秒」)
	# ── 弓箭(2026-08-05·§0.5 定稿)。效果本体在 eq_bow_batch.gd ──
	#   ★四件里只有 075 是【周期到点触发一次】这个形状。073 的攻速 buff 到期与
	#   076 的 0.25 秒逐发连射都要【比 0.25 秒更细的精度】, 走 EqBowBatch.tick() 每帧推进
	#   (自带 t_next 累加器, 帧率无关) —— 给它们排周期反而把精度降到 0.25 秒。
	"p2eq_075": EqBowBatch.RAIN_IV,   # 银色箭袋: 每 6 秒一轮箭雨(用户原文「每 6 秒」·2026-08-20 更名: 本注释原写「测距绳结」, 与 json 的名字对不上)
	# ★★批④(2026-08-06)把 077/079/080/081/087/091/094 七件【全部从这张表摘掉】——
	#   摘掉不是"改间隔", 是这七件的形状变了, EQ_PERIOD 这张"每 id 一个常数"的表装不下:
	#     · 077 铜管手铳 / 079 珊瑚急救塔 / 080 打捞旋翼机 —— 从"每 8 秒放一次"改成
	#       【登场召唤一个持续存在的召唤物】(小手枪 / 医疗炮台 / 直升机), 它们各有各的射速,
	#       其中 079 的炮台攻速还要【实时跟随携带者】⇒ 只能每帧推进。
	#     · 081 藤编圆盾 —— 从"每 2.5 秒套盾"改成【挨够 40/35/30% 最大生命才举盾】, 触发式。
	#     · 087 盗令潜水钟 —— 偷技能间隔【随星级变】(15/10/4 秒), 一个常数放不下;
	#       压载舱另有 2 秒抽水节拍, 两个节拍并存。
	#     · 091 远古龟甲片 —— 节拍从 2.5 秒改成 0.25 秒(且 <25% 血要翻 6 倍), 自管累加器更准。
	#     · 094 祖龟碑 —— 改成【阵亡触发】, 根本不是周期件。
	#   ⚠ 留个 0 会让 `_tick_eq_intervals` 每帧多查一次永远不成立的分支 —— 所以是删行不是置零。
	#   七件的驱动全部改走批系统的 `tick` / `tick_unit`(见本文件 `_b4_all` 与 `_eq_tick`)。
}


# 亡灵爆: 绿冲击环 + 绿辉爆闪 + 骨渣四射 (骷髅自灭/被杀 + 海螺变形共用基元)
func _tick_eq_intervals(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	## 040 FPGA板【登场】: 首帧把枪塞给对方 1/2/3 个敌人(照 058/032 的 pending 模式)。
	## ★放这儿而不是主场景的 `_tick_unit` —— 这个函数本来就是每单位每帧调的,
	##   借它的车不用给上帝文件加行(架构预算只减不增, 我第一版加在那边当场红)。
	if u.get("_gremlin_pending", false):
		u["_gremlin_pending"] = false
		_eq_fpga_hand_out_guns(u, int(u.get("_gremlin_si", 0)))
	## 096 小木斧【登场】: 首帧召唤斧头(同 058/032/040 的 pending 模式)。
	if u.get("_axe_pending", false):
		u["_axe_pending"] = false
		_axe.summon(u)
	## 096: 斧头攒满龟能就放主动(回血+护盾)。放这儿同理 —— 借每帧的车, 不给上帝文件加行。
	if u.has("_axe_ref"):
		_axe.tick(u, delta)
	for e in u["equips"]:
		var iid: String = str(e["id"])
		var iv: float = float(battle._EQ_CUSTOM_IV.get(iid, 0.0))
		if iv <= 0.0:
			iv = float(EQ_IV_BATCH1.get(iid, 0.0))
		if iv <= 0.0: continue
		var si: int = _eq_si(int(e.get("star", 1)))
		if iid == "p2eq_037": battle._ensure_candle(u)   # 蜡烛从开局就悬在头顶(不等首次tick)
		var stt: Dictionary = u["eq_state"].get(iid, {})
		stt["iv_t"] = float(stt.get("iv_t", 0.0)) + delta
		if float(stt["iv_t"]) >= iv:
			stt["iv_t"] = float(stt["iv_t"]) - iv
			# ★盾羁绊 9 档要认"这次护盾/治疗是哪件装备给的"(_holy_convert 读 _cur_eq_item,
			#   且它自己只认【盾类】装备)。原来这条路没标 → 藤编圆盾 081 拿不到圣光转化。
			battle._cur_eq_item = iid
			fire_equip_effect(u, iid, int(e.get("star", 1)), stt)
			battle._cur_eq_item = ""   # 用完立刻清: 不清会让紧随其后的护盾/治疗被误判成这件装备给的
		u["eq_state"][iid] = stt

# 涟漪回血特效(AI生成动画): 青绿涟漪水波躺平贴地, 帧播一次扩散淡出. 用于涟漪药剂042每个受益友军
func _eq_crossbow_volley(u: Dictionary, si: int) -> void:   # 连发弩049: 每8秒朝最远敌方向依次射1/2/3发, 命中沿途首敌(可被前排挡), 按已损血加伤
	if not u.get("alive", false): return
	var far49 := _eq_farthest_enemies(u, false)
	if far49.is_empty(): return
	var dir49: Vector2 = (far49[0]["pos"] - u["pos"]).normalized()
	var fire49 := func():
		if not u.get("alive", false): return
		var ft49 = _eq_first_in_line(u, dir49, 42.0)
		if ft49 == null: return
		var lost49: float = clampf((1.0 - ft49["hp"] / ft49["maxHp"]) / XBOW_LOST_FULL, 0.0, 1.0)
		battle._muzzle_flash(u["pos"], dir49, Color("#d8f0a8"))
		battle._spawn_eq_bolt(u, ft49, battle._atk_dmg(u, lerpf(XBOW_MIN_COEF, XBOW_MAX_COEF, lost49), ft49), "res://assets/sprites/vfx/crossbow-bolt.png", Color("#eaffd0"))
	battle._queue_shots([1, 2, 3][si], XBOW_GAP, fire49, u, "p2eq_049")

func _eq_gatling_burst(u: Dictionary, si: int) -> void:   # 幽灵加特林050: 每8秒连打20/30/60发随机分布+永久减甲(单目标累计上限)
	if not u.get("alive", false): return
	var g_shred: float = [1.0, 2.0, 3.0][si]
	var g_cap: float = [15.0, 25.0, 40.0][si]
	var g_mul: float = [0.1, 0.12, 0.14][si]
	var fire50 := func():
		if not u.get("alive", false): return
		var es50 = battle._targeting._pick_enemies_of(u)
		if es50.is_empty(): return
		var o50 = es50[battle._battle_rng.randi() % es50.size()]
		battle._muzzle_flash(u["pos"], (o50["pos"] - u["pos"]), Color("#d0ffff"))
		battle._spawn_eq_bolt(u, o50, battle._atk_dmg(u, g_mul, o50), "res://assets/sprites/vfx/bullet.png", Color("#d0ffff"), false, 0, 0.02)
		var g_acc: float = float(o50.get("gatling_shred_acc", 0.0))
		if g_acc < g_cap:
			var g_dec: float = minf(g_shred, g_cap - g_acc)
			o50["base_def"] = maxf(0.0, o50["base_def"] - g_dec); o50["gatling_shred_acc"] = g_acc + g_dec; battle._recalc_stats(o50)
	battle._queue_shots([20, 30, 60][si], 0.03, fire50, u, "p2eq_050")

func _eq_laser_pistol(u: Dictionary, si: int) -> void:   # 激光手枪051: 每8秒穿透红激光, 首敌满伤+流血, 身后敌半伤半流血
	if not u.get("alive", false): return
	var dir4: Vector2 = (battle._targeting._nearest_enemy(u)["pos"] - u["pos"]).normalized() if battle._targeting._nearest_enemy(u) != null else Vector2.RIGHT
	var first = _eq_first_in_line(u, dir4, PISTOL_LASER_BAND)
	if first != null:
		var endp51: Vector2 = u["pos"] + dir4 * 2600.0   # 无限穿透: 光束画到场外(伤害判定 battle._on_line 本就无距离上限, 原340码只是视觉长度→表现短于实际打击范围·用户2026-07-19"改为无限穿透")
		battle._muzzle_flash(u["pos"], dir4, Color("#ff5a72"))
		battle._laser_beam(u["pos"], endp51, Color(1.0, 0.24, 0.36, 0.85), 0.22, 0.22)   # 红辉(宽)
		battle._laser_beam(u["pos"], endp51, Color(1.0, 0.92, 0.94, 0.95), 0.07, 0.14)   # 白核(细)
		battle._damage._apply_damage_from(u, first, battle._atk_dmg(u, [1.5, 2.0, 2.8][si], first), Color("#ff8aa0"), 0.0, false, true)
		battle._damage._apply_dot_stacks(first, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si])), u)
		battle._vfx._hit_spark(first)
		for o in battle._targeting._enemies_of(u):
			if not is_same(o, first) and battle._on_line(first["pos"], dir4, o["pos"], PISTOL_LASER_BAND):
				battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, [1.5, 2.0, 2.8][si] * PISTOL_LASER_FALLOFF, o), Color("#ff8aa0"), 0.0, false, true)
				battle._damage._apply_dot_stacks(o, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si] * PISTOL_LASER_FALLOFF)), u)   # 身后50%流血

func _eq_shotgun_blast(u: Dictionary, si: int) -> void:   # 霰弹贝古053: 朝最近敌扇形散开, 每颗弹珠沿自己的直线飞, 撞到第一个敌人才结算伤害并消失; 被8发及以上命中→眩晕
	if not u.get("alive", false): return
	var t53 = battle._targeting._nearest_enemy(u)
	var dir53: Vector2 = (t53["pos"] - u["pos"]).normalized() if t53 != null else Vector2.RIGHT
	battle._muzzle_flash(u["pos"], dir53, Color("#ffe0a0"))
	battle._skill_ring(u["pos"] + dir53 * 22.0, Color(1.0, 0.85, 0.4, 0.7), 26.0)
	var n53: int = [12, 14, 18][si]
	var step53: float = deg_to_rad(battle.SHOTGUN_PELLET_DEG)
	var touched: Array = []
	var maxdur: float = 0.0
	for k in range(n53):
		var off53: float = (float(k) - float(n53 - 1) * 0.5) * step53   # 均匀分布在中线两侧
		var d53: Vector2 = dir53.rotated(off53)
		var hit53 = _eq_first_in_line(u, d53, 40.0)                     # 这条线上最近的敌人=挡住这颗弹珠的那个
		var endp: Vector2 = (hit53["pos"] if hit53 != null else u["pos"] + d53 * 1800.0)   # 没挡住→无限飞出场外
		var dur53: float = clampf(u["pos"].distance_to(endp) / 1500.0, 0.10, 0.75)         # 恒定弹速
		maxdur = maxf(maxdur, dur53)
		if hit53 == null:
			battle._ballistics._shotgun_pellet(u["pos"], endp, Color(1.0, 0.86, 0.5, 0.95), dur53)
			continue
		if not battle._arr_has_unit(touched, hit53): touched.append(hit53)
		var _tg: Dictionary = hit53
		battle._ballistics._shotgun_pellet(u["pos"], endp, Color(1.0, 0.86, 0.5, 0.95), dur53, func() -> void:
			if not _tg.get("alive", false): return
			battle._damage._apply_damage_from(u, _tg, battle._atk_dmg(u, SHOTGUN_COEF, _tg), Color("#ffd07a"), 0.0, false, true)
			_tg["_sg_hits"] = int(_tg.get("_sg_hits", 0)) + 1)
	# 全部弹珠落地后再判眩晕(命中计数记在单位自身字段 —— 不拿单位字典当Dict键, 见 2026-07-19 卡死教训)
	if touched.is_empty(): return
	battle._pending_shots.append({"delay": maxdur + 0.06, "src": u, "fn": func() -> void:
		for o in touched:
			if int(o.get("_sg_hits", 0)) >= SHOTGUN_STUN_HITS and o.get("alive", false): battle._freeze(o, battle.CTRL_SEC)
			o.erase("_sg_hits")})

func _eq_pistol_volley(u: Dictionary, si: int) -> void:   # 黄铜手铳048: 每8秒依次射4/5/6发, 每发命中直线首敌(错峰: 枪口闪+子弹+火花)
	if not u.get("alive", false): return
	var t48 = battle._targeting._nearest_enemy(u)
	var dir48: Vector2 = (t48["pos"] - u["pos"]).normalized() if t48 != null else Vector2.RIGHT
	var mul48: float = [0.5, 0.54, 0.6][si]
	var fire48 := func():
		if not u.get("alive", false): return
		var ft48 = _eq_first_in_line(u, dir48, 36.0)
		if ft48 == null: return
		battle._muzzle_flash(u["pos"], dir48, Color("#ffe08a"))
		battle._spawn_eq_bolt(u, ft48, battle._atk_dmg(u, mul48, ft48), "res://assets/sprites/vfx/bullet.png", Color("#fff0b0"), false, 0, 0.026)
	battle._queue_shots([4, 5, 6][si], 0.08, fire48, u, "p2eq_048")

func _eq_ripple_tick(u: Dictionary, si: int) -> void:
	var low042 = null; var lv042 := INF
	if si == 2:
		for o in battle._targeting._allies_of(u):
			var p042: float = CombatMath.hp_frac(o["hp"], o["maxHp"])
			if p042 < lv042: lv042 = p042; low042 = o
	for o in battle._targeting._allies_of(u):
		var pct042: float = [0.03, 0.06, 0.10][si]
		if si == 2 and is_same(o, low042): pct042 *= 2.0
		var amt42: float = (o["maxHp"] - o["hp"]) * pct042
		if amt42 >= 1.0:
			battle._damage._heal(o, amt42)
			battle._ripple_heal_vfx(o["pos"], 105.0)   # AI生成涟漪回血动画

func _eq_revolver_tick(u: Dictionary, si: int, stt: Dictionary) -> void:
	if int(stt.get("revolver_bullets", 0)) > 0:
		var es3 = battle._targeting._pick_enemies_of(u)
		if not es3.is_empty():
			stt["revolver_bullets"] = int(stt["revolver_bullets"]) - 1
			var o = es3[battle._battle_rng.randi() % es3.size()]
			battle._muzzle_flash(u["pos"], (o["pos"] - u["pos"]), Color("#ffe08a"))
			battle._spawn_eq_bolt(u, o, battle._resolve_dmg(u, u["atk"] * [3.0, 5.0, 9.0][si] + [150.0, 310.0, 1200.0][si], o, false), "res://assets/sprites/vfx/bullet.png", Color("#ffe6a8"), false, 0, 0.034)   # 左轮重弹(真子弹, 大一号)

# 蛋糕蜡烛037: 头顶悬浮真蜡烛精灵(带火苗辉光), 随相位 熄灭/微弱/燃烧 亮暗变化; 持续存在直到携带者死
func _eq_candle_tick(u: Dictionary, si: int, stt: Dictionary) -> void:
	battle._ensure_candle(u)
	var c = u.get("_candle_spr", null)
	var ph: int = int(stt.get("candle", 0))
	stt["candle"] = (ph + 1) % CANDLE_PHASES
	if ph == 0:   # 熄灭: 蜡烛变暗(火苗弱下去, 无效果)
		if c != null and is_instance_valid(c):
			battle._reg_tween().tween_property(c, "modulate", Color(0.5, 0.5, 0.58, 1.0), 0.35)
	elif ph == 1:   # 微弱: 蜡烛点亮 + 250码光圈 + 圈内友军5s逐渐回血
		if c != null and is_instance_valid(c):
			battle._reg_tween().tween_property(c, "modulate", Color(1, 1, 1, 1), 0.35)
		var hv37: float = [20, 30, 44][si] + u["atk"] * [0.5, 0.7, 1.0][si]
		battle._heal_circle_vfx(u["pos"], CANDLE_HEAL_R, CANDLE_IV)   # AI生成回血阵动画
		u["candle_hot_rate"] = hv37 / CANDLE_IV
		u["candle_hot_until"] = battle._t + CANDLE_IV
		for a37 in battle._targeting._allies_of(u, false):
			if a37["pos"].distance_to(u["pos"]) <= CANDLE_HEAL_R:
				a37["candle_hot_rate"] = (hv37 * CANDLE_ALLY_HALF) / CANDLE_IV
				a37["candle_hot_until"] = battle._t + CANDLE_IV
	elif ph == 2:   # 燃烧: 火苗爆燃(蜡烛过亮+弹一下) + 原地爆炸, 500码内敌各受魔法伤+灼烧
		if c != null and is_instance_valid(c):
			var ct = battle._reg_tween(); ct.set_parallel(true)
			ct.tween_property(c, "modulate", Color(1.4, 1.15, 0.85, 1.0), 0.12)
			ct.tween_property(c, "scale", Vector3.ONE * 1.3, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			ct.chain().tween_property(c, "scale", Vector3.ONE, 0.25)
		battle._boom_wave(u["pos"], 260.0)   # AI生成爆炸波动画(原地大爆炸)
		battle._shake(0.06)
		var dmg37: float = float([20, 30, 44][si]) + u["atk"] * [0.5, 0.7, 1.0][si]
		for o in battle._targeting._enemies_of(u):
			if o["pos"].distance_to(u["pos"]) <= CANDLE_BURN_R:   # 499→500(用户2026-07-19)
				battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, dmg37, o, true), Color("#ffb066"), 0.0, false, true)   # 魔法伤(蓝字), 非真伤
				battle._damage._apply_dot_stacks(o, "burn", [20, 30, 40][si], u)
				battle._boom_wave(o["pos"], 110.0)   # 每个被波及敌小爆

## (已删 _eq_signal_tick —— 信号放大器 2026-07-31 效果重做后它是死代码:
##  原来是"每 6 秒随机一段 3.5 秒增伤", 现在改成"普攻叠层 + 每 5 层放弧形波"(SignalWaveSystem)。
##  ★死代码留着会被门禁的"函数存在"断言保护住, 也可能被 VFXPREVIEW 指过去 = 无效目视验证。)
# 信号脉冲(038): 头顶弹出青蓝 signal-wave 广播图标(升起放大淡出, 2个错峰=脉冲广播) + 脚下青光环
## ★★2026-08-22 文案根除: FPGA板(040) 这一组原来全是函数体里的裸字面量,
##   而 `phase2-equipment.json` 的 effectDesc1 又手写了一遍(15 个数, 全库最多的一段)。
## ★数组常量会被 `{C:}` 渲染成 "1/2/4"(三档写法) —— 正好是文案要的形状。
## 【053 霰弹贝古】扇形弹珠, 每颗撞到第一个敌人才结算。
## 【009 宽刃弯刀】攒刃能 → 满值斩出环形扇区(不是整块扇形, 是 500~800 的**带**)。
## 【037 蛋糕蜡烛】三阶段循环: 熄灭 → 微弱(回血) → 燃烧(爆燃)。
const BROADSWORD_REACH := 2000.0  # 007 锈蚀阔剑: 剑气墙扫多远(码)·有效与特效同距
## ── 007 锈蚀阔剑的三件真素材(2026-09-08 从程序生成换成 Blender 烤·rust 锁定板) ──
## ★★换掉的三样都是 001/003/004 同族的老毛病, 实拍确认:
##   ① `VfxTex._make_vblade_texture()` 的起手剑 = 贴在龟身上一道**白划痕**
##   ② `VfxTex._make_bladewall_texture()` + LINEAR 的剑气墙 = 一道**模糊的橙褐弧**
##   ③ 沿途 `_splash_ring_bold` 撒的**一串橙色圆环** = 通病「无含义圆环」
## ★外加一条新的:【名实不符】—— 它叫「锈蚀阔剑」而演出是炽焰赤金。全部改走 rust 板。
const BSW_SWORD_TEX := "res://assets/sprites/vfx/eq007-broadsword.png"   # 8 向阔剑(劈砍靠选帧)
const BSW_WALL_TEX := "res://assets/sprites/vfx/eq007-bladewall.png"     # 8 向 x 4 帧 剑气墙
const BSW_SCRAPE_TEX := "res://assets/sprites/vfx/eq007-scrape.png"      # 5 帧 地面刮痕
const BSW_DIRS := 8
const BSW_WALL_FRAMES := 4
const BSW_SCRAPE_FRAMES := 5
const BSW_SWORD_PX := 0.052       # 阔剑: 44px x 0.052 = 2.3 米(比 006 那把 1.76 米更有分量)
const BSW_WALL_PX := 0.095        # 剑气墙: 42px x 0.095 = 4.0 米高 = 龟(2.0m)的两倍, 才像一堵墙不像一根木头
const BSW_SCRAPE_PX := 0.055      # 刮痕: 43px x 0.055 = 2.4 米长
const BSW_CHOP_STEP := 0.045      # 劈砍每格停多久(游戏秒) —— 与 006 同一条: 走 _wait_sim 不走 tween
## 劈砍的弧: 从"高举"(左上 135°)扫到"下劈"(右下 315°), 经 90/45/0 共 5 格。
## ★方向表的角度是**屏幕角**, 与 _sword_fly_frame 同一套。
const BSW_CHOP_FROM_R := 3        # 敌在右: 从左上 135° 抡到右下 315°
const BSW_CHOP_FROM_L := 1        # 敌在左: 镜像, 从右上 45° 抡到左下 225°
const BSW_CHOP_ARC := 4           # 抡过 4 格(半圈)
## 【043 海浪护符】浪墙从携带者【身后】多远处涌起(码)。
const WAVE_BACK := 400.0
const CANDLE_PHASES := 3       # 几个阶段
const CANDLE_IV := 5.0         # 每几秒切一次(主场景 _EQ_CUSTOM_IV 引用本常量)·也是回血铺开的秒数
const CANDLE_HEAL_R := 250.0   # 微弱阶段: 友军回血光圈半径(码)
const CANDLE_ALLY_HALF := 0.5  # 圈内友军按【半数】回复
const CANDLE_BURN_R := 500.0   # 燃烧阶段: 爆燃半径(码)
## 【004 暴君之牙】斩杀线随暴击率抬高; 处决后按有没有龟能给不同奖励。
const FANG_IV := 6.0            # 每几秒射一颗毒牙(主场景 _EQ_CUSTOM_IV 引用本常量)
const FANG_LIFESTEAL := 1.00    # 毒牙回复 = 造成伤害 ×
const FANG_EXEC_ENERGY := 20.0  # 处决后回龟能(有龟能系统的单位)
const FANG_EXEC_HEAL := 40.0    # 没有龟能系统的改回血
## 【041 退潮浊液】登场若干秒后涨潮(临时加成), 到期退潮还原。
const TIDE_DELAY := 5.0     # 登场几秒后涨潮
const TIDE_SIZE_UP := 0.30  # 涨潮期体积 +
const TIDE_RANGE_UP := 50.0 # 涨潮期射程 +(码)
## 【013 炙烤海胆】受击叠硬化, 满层给一次会衰减的护盾。
const URCHIN_CAP := 20        # 硬化层上限(014 是 25, 见 EquipTickSystem.FORTRESS_CAP)
const URCHIN_DECAY := 10.0    # 海胆护盾在几秒内线性衰减完
## 【071 炼乳罐】奶油盾破 → 范围魔法 + 给持有者一串永久加成。
const CREAM_BURST_R := 300.0  # 盾破的伤害半径(码)
const CREAM_RESIST := 10.0    # 之后 +双抗
const CREAM_RANGE := 50.0     # 之后 +射程(码)
## 【023 灼热火珊瑚】命中攒法力, 法力满自动挥一道缓移的扇形火焰波。
## 【067 毒药瓶】每几秒朝敌人最密集处投一个瓶子(用户规格「每 6 秒」)。
## 【033 复活海螺】小虫诞生时随机带装备的**费用池**。
const CONCH_COST_MIN := 4         # 池子 = 这两个费用的装备
const CONCH_COST_MAX := 5
const VIAL_IV := 6.0              # 真值在 EQ_IV_BATCH1, 那里引用本常量
const CORAL_MANA_PER_HIT := 10.0  # 每段攻击命中给自己多少法力
const CORAL_ARC_DEG := 60.0       # 火焰波扇面全角(度)·判定用半角
const CORAL_TRAVEL := 550.0       # 火焰波向前推进多远(码)
const CORAL_WINDUP := 0.4         # 蓄力多久(秒·游戏钟)
const DRAGON_WINDUP := 0.55       # 024 龙蛋前摇(秒·游戏钟)
const CHAIN_HOP_GAP := 0.2        # 026 连锁闪电逐跳错峰(秒·游戏钟)
const CORAL_SPEED := 320.0        # 波前推进速度(码/秒·游戏钟) ⇒ 550 码走 1.72 秒
const CORAL_BAND := 65.0          # 波前判定带半宽(码) —— 演出的火簇就摆在这条带上
const CORAL_BURN := [40, 60, 90]  # 每星级施加的灼烧层数(用户2026-07-19: 原固定60不吃星级)
## ── 火焰波的火簇素材(tools/blender_firecrest.py 烤, truefire 调色板) ──
const CORAL_CREST_TEX := "res://assets/sprites/vfx/fire-crest.png"
const CORAL_CREST_FRAMES := 8
const CORAL_CREST_CELL := 28
const CORAL_CREST_FPS := 12.0
## ★格子从 40 缩到 28: 40 texel(1.70 m)的火簇沿弧排开读成**一堵火墙/一条火蛇**, 不是「一道波」。
##   缩簇**只能重烤成小格**, 不能改 pixel_size —— pixel_size 必须钉死 0.0426(1 texel : 1 屏幕像素)。
const CORAL_CREST_YARDS := 49.7   # 28 texel × 0.0426 m ÷ WS = 1.19 m(龟高 2.0 m)
## ★实际画幅(逐帧量的): 8 帧平均 18.9 texel 宽 ⇒ 33.5 码。摆间距用它, 不用格宽。
const CORAL_CREST_ART_YARDS := 33.5
const CORAL_CREST_H := 0.596      # 贴图中心 = 半格(28/2 × 0.0426) ⇒ 火底齐地(022 那条教训)
## ★★径向排数: 判定带是 **±CORAL_BAND = ±65 码(共 130 码深)**, 而一簇只有 49.7 码宽
##   ⇒ 只摆一排的话, 站在波前前后 25~65 码的敌人**会被烧到但那里没有火**(只覆盖 38%)。
##   用户 2026-09-13:「**演出得贴合实际伤害范围和判定啊**」⇒ 沿径向铺满整条带。
##   4 排 × 间距 32.5 码 ⇒ 覆盖 -65~+65 码, 正好是判定带; 间距 < 一簇宽(49.7)
##   ⇒ 相邻排互相盖住一截, 读成**一条厚带**而不是三道并排的波(3 排时就是三道)。
const CORAL_CREST_ROWS := 4
const CORAL_CREST_MAX := 20       # 最多摆几簇(护栏: 弧长随距离线性涨)
var _firecrest_tex: Texture2D = null
## 【051 激光手枪】无限穿透的直线激光, 首个吃满、身后的减半。
const PISTOL_LASER_BAND := 50.0   # 判定带半宽(码)
const PISTOL_LASER_FALLOFF := 0.5 # 首个之后的敌人受到的比例
## 【052 左轮手枪】自带弹药, 敌人阵亡补弹(有上限), 打空停火。
const REVOLVER_AMMO := 6      # 初始弹数 = 上限(同一个数)
const REVOLVER_IV := 4.0      # 每几秒射一发(主场景 _EQ_CUSTOM_IV 引用本常量)
const BLADE_FULL := 100.0        # 刃能满值
const BLADE_AOE_FACTOR := 0.5    # 范围技能充能减半
const BLADE_R_IN := 500.0        # 扇形带内半径(码)
const BLADE_R_OUT := 800.0       # 扇形带外半径(码)
const BLADE_ARC_DEG := 60.0      # 扇面全角(度)·判定用半角 = 它的一半
const BLADE_SEEK := 2000.0       # 沿瞄准方向自选释放点的最大偏移(码)
## 009「月之刃」的两张素材: `tools/gen_moonslash.py` 烤 → `tools/pixelize_sheet.py` 的 `steel` 锁定板。
##
## ★★这一版是**照着上一代实拍 100 帧逐帧重写的**(docs/studies/20260909-009旧特效逐帧.md)。
##   我上一版(三条同心弧 + 一弯月牙)被用户否掉, 原因不是"不好看", 是我**把结构删了**。
##   逐帧看完才发现上一代好在四件事, 我一件没留 ——
##     ① 预警是**一片区域**(半透/脉动/不遮挡单位), 一眼说清"这一整片要挨打";
##        三条细弧只说了边界在哪, 面积感为零, 而且三条同心弧是标准的**声波图形**。
##     ② 斩痕**叠在还亮着的预警上**沿带心劈开 ⇒ 读作"在这片区域里劈了一刀";
##        我做成"预警收掉 → 月牙出现", 因果链当场断掉。
##     ③ 白光是**热核 + 冷边**(有温度层次), 不是一块纯白。
##     ④ 0.56 秒里 alpha 脉动两个来回, 有呼吸感。
##   ⇒ 本版**结构与节奏原样保留**, 只换表面。上一代真正该修的只有五条, 全是表面:
##     消散变灰块 / 软边无 NEAREST / 靠 rotation 转贴图 / 芥末黄名实不符 / 图标是直剑。
const MOON_BAND_TEX := "res://assets/sprites/vfx/eq009-band.png"     # 16 向 × 1 帧 预警区(填充)
const MOON_SLASH_TEX := "res://assets/sprites/vfx/eq009-slash.png"   # 16 向 × 5 帧 斩痕
const MOON_DIRS := 16
const MOON_SLASH_FRAMES := 5
const MOON_CELL := 192           # 每格边长(像素)
## 画布中心 = 释放点 + 瞄准方向 × 带心半径。扇区对称于瞄准轴, 跟着轴平移之后
## ±420 码就框得下(整圆盘要 ±800) ⇒ 同样的格子数换来 3.8 倍的像素密度。
const MOON_ANCHOR := (BLADE_R_IN + BLADE_R_OUT) * 0.5
## 每格覆盖 2 × 0.525 × BLADE_R_OUT = 840 码; 840 × WS(0.024) = 20.16 米 / 192 px = 0.105。
## ★这个数不是"看着合适"挑的, 是被【像素密度】逼出来的: 渲整圆盘那版是 0.40 米/像素,
##   而 006 地缝 0.045、007 剑气墙 0.095 —— 009 会比它们粗一个数量级, 上屏是大色块。
##   门禁 verify_eq_wide_blade 把这条关系焊死(改 CELL 或 R_OUT 不同步改这里就红)。
const MOON_PIXEL_SIZE := 0.105
## 画布半宽(码)。生成器里是 `VIEW = 0.525` 占 R_OUT 的比例 ⇒ 0.525 × 800 = 420。
## ★门禁要靠它反算「释放点落在格内哪个像素」来量方向, 所以必须和生成器是同一个数,
##   不能两边各写各的(手抄的副本必然落后)。
const MOON_VIEW := 0.525 * BLADE_R_OUT
## 预警总时长与上一代一致(0.56 秒), 但**逐格走游戏时钟**而不是 tween ——
## tween 走未钳制的真实 delta, 与量它的时刻戳不是同一条时钟, 实拍会量出假时长(v0.19.345 那一课)。
const MOON_TEL_STEPS := 14       # 14 格 × 0.04 = 0.56 秒
const MOON_TEL_STEP := 0.04
const MOON_TEL_A := 0.44         # 预警 alpha 中位; 峰 0.58 / 谷 0.30, 在 0.56 秒里走两个来回
const MOON_TEL_SWING := 0.14
const MOON_TEL_RISE := 0.12      # 前 12% 从 0 淡入(上一代就是从 alpha 0 淡入的, 不是一出生就满)
const MOON_SLASH_STEP := 0.11    # 斩痕 5 帧 × 0.11 = 0.55 秒(与上一代一致)
## 【049 连发弩】朝最远敌连射, 按目标【已损】生命插值加伤。
## 【022 余烬燃油瓶】定时抛火瓶, 命中点上「真火」。
const EMBER_IV := 8.0            # 每几秒抛一个火瓶(主场景 _EQ_CUSTOM_IV 引用本常量)
const EMBER_TRUEFIRE_SEC := 5.0  # 真火持续(秒)·期间该目标的灼烧改判真实伤害
## 【042 涟漪药剂】定时给全队按【已损生命】回复。
const RIPPLE_IV := 8.0           # 每几秒回一次(主场景 _EQ_CUSTOM_IV 引用本常量)
## 【048 黄铜手铳】定时连射, 每发只打沿途第一个敌人。
const HANDGUN_IV := 8.0          # 每几秒一轮(主场景 _EQ_CUSTOM_IV 引用本常量)
## 【050 幽灵加特林】定时打一大把随机分布的子弹, 命中永久减甲。
const GATLING_IV := 8.0          # 每几秒一轮(主场景 _EQ_CUSTOM_IV 引用本常量)
## 【051 激光手枪】定时打一道无限穿透的直线激光。
const PISTOL_IV := 8.0           # 每几秒一道(主场景 _EQ_CUSTOM_IV 引用本常量)
## 【057 狙击长管】定时狙最残的敌人, 击杀就重新蓄力再来一枪。
const SNIPER_IV := 8.0           # 每几秒一轮(主场景 _EQ_CUSTOM_IV 引用本常量)
const SNIPER_MAX_CHAIN := 12     # 一轮内最多连狙几枪(防连狙无限递归)
const XBOW_IV := 8.0             # 每几秒一轮(主场景 _EQ_CUSTOM_IV 引用本常量)
const XBOW_GAP := 0.12           # 同轮两发的间隔(秒)
const XBOW_MIN_COEF := 0.8       # 满血时 ×ATK
const XBOW_MAX_COEF := 1.3       # 已损到位时 ×ATK
const XBOW_LOST_FULL := 0.30     # 已损这么多生命就吃满加伤
const SHOTGUN_IV := 8.0           # 每几秒一次齐射(主场景 _EQ_CUSTOM_IV 引用本常量)
const SHOTGUN_COEF := 0.22        # 每颗弹珠 ×ATK 物理
const SHOTGUN_STUN_HITS := 8      # 同一次齐射被这么多颗及以上命中 → 眩晕
const FPGA_IV := 6.0             # 每几秒抽一次(真值在主场景 _EQ_CUSTOM_IV, 那里引用本常量)
## FPGA板登场塞给敌人的枪数(逐星·用户 2026-08-31「随机1/2/3个敌人」)
const FPGA_GUNS := [1, 2, 3]
const FPGA_PICKS := [1, 2, 4]    # 逐星: 每次抽几个 2-bit 状态(可重复)
const FPGA_00_HEAL_PCT := 0.05   # 00: 回复最大生命 ×
const FPGA_00_RESIST := 12       # 00: 累计 + 护甲与魔抗
const FPGA_01_ATK := 15          # 01: 累计 + 攻击力
const FPGA_01_LIFESTEAL := 0.07  # 01: 累计 + 生命偷取
const FPGA_BUFF_SEC := 3.5       # 10/11 的持续秒数
const FPGA_10_AMP := 0.15        # 10: 增伤(放大自身造成的所有伤害)
const FPGA_11_DR := 0.25         # 11: 受到伤害减免(真实伤害除外)

## FPGA板【登场】: 给**对方**随机 1/2/3 个敌人各一把古灵精怪枪(用户 2026-08-31 新增)。
## ★这是【新增】的一条效果, 原来那条"每 N 秒抽 2-bit 状态给自己上 buff"一条没动。
## ★挑人是**不重复**的 —— 需求说"1/2/3 个敌人", 同一个人塞两把不算两个敌人。
##   (敌人不够时有几个给几个; 返回真给出去的把数, 门禁拿它当分母。)
## ★用 `battle._battle_rng` 而不是裸 randi —— 确定性门禁(rng_discipline)守着这条。
func _eq_fpga_hand_out_guns(u: Dictionary, si: int) -> int:
	var want: int = FPGA_GUNS[si]
	var foes: Array = []
	var my_side: String = str(u.get("side", ""))
	for o in battle._units:
		if o is Dictionary and o.get("alive", false) and str(o.get("side", "")) != my_side 				and not o.get("_isEgg", false):
			foes.append(o)
	if foes.is_empty():
		return 0
	var given: int = 0
	while given < want and not foes.is_empty():
		var k: int = battle._battle_rng.randi() % foes.size()
		_gremlin.give(foes[k])
		## ★★「**扔**给目标一把古灵精怪枪」—— 需求原话里的动作。
		##   之前这条路径**一个 vfx 调用都没有**: 属性静悄悄加上去, 玩家看不到发生过什么
		##   (2026-09-01 逐句核对原话时抓到, 第 2 句)。
		##   ★演出在结算【之后】—— give() 已经同步做完, 这条 tween 推不动也不影响数值。
		battle._vfx._throw_item(u, foes[k], "gremlin-gun.png", "古灵精怪枪", Color("#8ae06a"))
		foes.remove_at(k)          # ★不重复: 挑过就拿掉
		given += 1
	return given


func _eq_fpga_tick(u: Dictionary, si: int) -> void:
	battle._skill_ring(u["pos"], Color(0.4, 0.9, 1.0, 0.42), 46.0)
	var codes := ["00", "01", "10", "11"]
	var ccols := [Color("#7ad0ff"), Color("#a0ff8a"), Color("#ffd05a"), Color("#ff8ad0")]
	var n: int = FPGA_PICKS[si]
	for k in range(n):
		var pick: int = battle._battle_rng.randi() % 4
		var xoff: float = (float(k) - float(n - 1) / 2.0) * 34.0
		battle._vfx._float_text(u["pos"] + Vector2(xoff, -72.0), codes[pick], ccols[pick])   # 二进制码头顶跳
		match pick:
			0: battle._damage._heal(u, u["maxHp"] * FPGA_00_HEAL_PCT); u["base_def"] += FPGA_00_RESIST; u["base_mr"] += FPGA_00_RESIST; battle._recalc_stats(u)   # 用户2026-07-19: +2 → +12
			1: u["base_atk"] += FPGA_01_ATK; u["lifesteal"] += FPGA_01_LIFESTEAL; battle._recalc_stats(u)                            # 用户2026-07-19: +5/+4% → +15/+7%
			2:
				u["damage_amp"] = float(u.get("damage_amp", 0.0)) + FPGA_10_AMP   # 10: 真·增伤(放大所有伤害·用户2026-07-19"amp要"); 原 battle._damage._buff(atk,15%) 只放大吃ATK的段, 而040自己不给攻击力
				battle._pending_shots.append({"delay": FPGA_BUFF_SEC, "fn": func(): u["damage_amp"] = maxf(0.0, float(u.get("damage_amp", 0.0)) - FPGA_10_AMP), "src": u})
			3:
				u["damage_reduction"] = float(u.get("damage_reduction", 0.0)) + FPGA_11_DR   # 11: 受到伤害-25%(真伤除外·用户2026-07-19: 原误做+25%护甲对魔/真伤无效→改真减伤)
				battle._pending_shots.append({"delay": FPGA_BUFF_SEC, "fn": func(): u["damage_reduction"] = maxf(0.0, float(u.get("damage_reduction", 0.0)) - FPGA_11_DR), "src": u})


func _eq_ebb_surge(u: Dictionary, hp_add: float, atk_add: float, dur: float) -> void:   # 退潮浊液041: 涨潮期开始
	if not u.get("alive", false) or u.get("_ebb_on", false): return
	u["_ebb_on"] = true
	u["maxHp"] += hp_add; u["hp"] += hp_add
	u["base_atk"] = float(u.get("base_atk", 0.0)) + atk_add
	u["atk_range"] = float(u.get("atk_range", 70.0)) + TIDE_RANGE_UP
	u["size_mult"] = float(u.get("size_mult", 1.0)) * (1.0 + TIDE_SIZE_UP)      # 体积+30%(走size_mult, 每帧juice从base起算不会覆盖)
	battle._recalc_stats(u)
	battle._ebb_tide_fx(u, true)
	battle._vfx._float_text(u["pos"] + Vector2(0, -70), "涨潮", Color("#5fe0d0"))
	battle._pending_shots.append({"delay": dur, "fn": func(): _eq_ebb_recede(u, hp_add, atk_add), "src": u})

func _eq_ebb_recede(u: Dictionary, hp_add: float, atk_add: float) -> void:   # 退潮浊液041: 到期还原
	if not u.get("_ebb_on", false): return
	u["_ebb_on"] = false
	u["maxHp"] = maxf(1.0, float(u["maxHp"]) - hp_add)
	u["hp"] = minf(float(u["hp"]), float(u["maxHp"]))          # 退潮不致死, 只削到新上限
	u["base_atk"] = maxf(0.0, float(u.get("base_atk", 0.0)) - atk_add)
	u["atk_range"] = maxf(10.0, float(u.get("atk_range", 70.0)) - TIDE_RANGE_UP)
	u["size_mult"] = maxf(0.01, float(u.get("size_mult", 1.0)) / (1.0 + TIDE_SIZE_UP))
	battle._recalc_stats(u)
	if u.get("alive", false):
		battle._ebb_tide_fx(u, false)
		battle._vfx._float_text(u["pos"] + Vector2(0, -70), "退潮", Color("#8fb8c8"))

## 020 哑铃: 【瞬间】+1 锻炼层(maxHp, 局内每场重置) → 当场掷哑铃击退。
## ★★2026-09-12 用户:「**020现在不要有锻炼阶段，直接投掷哑铃了**」
##   原来这里是: 置 `_slam`(锁 AI/普攻/移动/龟能充能) → 3 下蹲起(3×0.3s) → 加层 →
##   蓄力 0.35s → 投掷, 一共 **1.25 秒**。1:1 逐帧量过: 从触发到哑铃出现整整
##   **1.03 秒八帧完全没有画面**, 龟只是站着不动 —— 文案写「原地锻炼」, 画面读成「卡住了」。
## ★他同时拍板「**留数值, 只删那段站桩**」⇒ 锻炼层与 +40/75/110 最大生命**原样保留**,
##   只是改成瞬间生效。哑铃伤害 = 5/7/10% 自身最大生命值, 吃的就是这个生命 ⇒ 动它就是动数值。
## ★副作用(已知并接受): 不再锁普攻/移动/充能 ⇒ 携带者在这 1.25 秒里照常输出, 这是净加强。
## ★另一个收益: 这条路径**不再有 await** —— 结算不再挂在演出上
##   (CLAUDE.md §3.5: 一个测数值的用例不该依赖任何动画跑完)。
func _eq_dumbbell_routine(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	var stt: Dictionary = u["eq_state"].get("p2eq_020", {})   # 锻炼层(eq_state局内计数, 每场战斗重置)
	stt["exercise"] = int(stt.get("exercise", 0)) + 1
	u["eq_state"]["p2eq_020"] = stt
	var gain: float = [40.0, 75.0, 110.0][si]   # 锻炼层+maxHp&当前生命(用户2026-07-19: 20/25/30→40/75/110)。★不乘HP_MULT: 装备hp已是最终值(见L45规则), 原来乘了→实发120/225/330=文案的3倍
	u["maxHp"] += gain; u["hp"] += gain
	battle._skill_ring(u["pos"], Color(0.8, 0.9, 1.0, 0.42), 48.0)   # 锻炼强化光(瞬间, 不再有站桩)
	var t = battle._targeting._nearest_enemy(u)
	if t == null: return
	battle._anticipate(u); battle._shake(battle.JUICE_SHAKE_HEAVY)   # 投掷起手(瞬间形变, 不再是 1.25 秒站桩)
	var dmg: int = maxi(1, int(u["maxHp"] / battle.HP_MULT * [0.05, 0.07, 0.10][si]))
	battle._throw_dumbbell(u, t, dmg)

func _eq_fuel_throw(u: Dictionary, si: int) -> void:   # 余烬燃油瓶022: 每8秒→短蓄力→抛物线掷出火瓶(翻滚·余烬拖尾)→碎裂溅火+灼烧+真火5秒
	if not u.get("alive", false): return
	if battle._targeting._nearest_enemy(u) == null: return
	battle._anticipate(u)   # 短蓄力
	await battle._wait_sim(0.3)
	if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 free), 回来必须重新确认
	if not is_instance_valid(self) or not u.get("alive", false): return
	var t = battle._targeting._nearest_enemy(u)
	if t == null: return
	var from2d: Vector2 = u["pos"]
	var to2d: Vector2 = t["pos"]
	var spr := Sprite3D.new()
	spr.texture = load("res://assets/sprites/equip/ember-flask.png")   # 真瓶子立绘当投掷物(原来是一团光球)
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # ★翻滚要真转; BILLBOARD会吃掉roll(001飞斩的教训)
	spr.shaded = false; spr.transparent = true
	spr.no_depth_test = true; spr.render_priority = 5
	spr.pixel_size = (42.0 * battle.WS) / float(maxi(1, spr.texture.get_height()))
	spr.position = battle._world_pos(from2d, 1.15)
	battle._world.add_child(spr)
	var dist: float = from2d.distance_to(to2d)
	var tw = battle._reg_tween()
	tw.tween_method(battle._fuel_flask_step.bind(spr, from2d, to2d, clampf(dist / 900.0, 0.55, 1.5)), 0.0, 1.0, clampf(dist / 620.0, 0.45, 1.05))
	tw.tween_callback(battle._fuel_bottle_hit.bind(spr, u, t, si))

# 028 冰霜冻露瓶: 蓄力→抛物线缓慢扔冰瓶→砸敌魔法伤+冰寒+冰爆
func _eq_ice_throw(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	if battle._targeting._nearest_enemy(u) == null: return
	battle._anticipate(u)
	## ★前摇从 tween 挪到游戏钟(2026-09-13): tween 走**未钳制的真实 delta, 无头下推不动**
	##   (§3.5) ⇒ 前摇永远走不完, **瓶子根本不出手**。与 024/025/026/029 同一条病,
	##   走同一个共享原语(memory [[fb-fix-the-shared-primitive-not-one-instance]])。
	battle._equip_tick_sys.schedule(IceSystem.VIAL_WINDUP,
		battle._ice_sys._ice_throw_go.bind(u, si))

func _eq_broadsword(u: Dictionary, si: int) -> void:   # 锈蚀阔剑007: 高举→下劈→剑气墙沿dir扫2000码·命中给盾
	var flat: int = [20, 35, 60][si]
	var sc: float = [0.5, 0.8, 1.1][si]
	var shp: float = [0.5, 0.75, 1.0][si]
	var t = battle._targeting._nearest_enemy(u)
	var dir: Vector2 = ((t["pos"] - u["pos"]).normalized() if t != null else Vector2.RIGHT)
	if dir.length() < 0.1: dir = Vector2.RIGHT
	## ★锚点在施法那一刻定死(同 006): 整套演出跨 3 秒而携带者一直在走,
	##   每段现读 u["pos"] 会让"劈下去的地方"和"剑气出发的地方"对不上。
	var anchor: Vector2 = u["pos"]
	var front: Vector2 = anchor + dir * 55.0
	battle._anticipate(u); battle._shake(battle.JUICE_SHAKE_HEAVY)

	# ① 起手: 阔剑高举。★换真素材 + **抡砍靠选帧, 贴图不旋转**
	#    (改造前是 `_make_vblade_texture()` 程序生成 + `rotation.z` 自由旋转,
	#     实拍是贴在龟身上的一道白划痕; 像素风只能 90° 无损旋转)。
	var right: bool = dir.x >= 0.0
	var chop_from: int = BSW_CHOP_FROM_R if right else BSW_CHOP_FROM_L
	var chop_arc: int = (-BSW_CHOP_ARC) if right else BSW_CHOP_ARC
	var sword := Sprite3D.new()
	sword.texture = _bsw_sword_tex()
	sword.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sword.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sword.shaded = false; sword.transparent = true
	sword.pixel_size = BSW_SWORD_PX
	sword.frame = 0
	sword.hframes = BSW_DIRS; sword.vframes = 1     # ★改 hframes 前先归零(setter 会校验当前 frame)
	sword.frame = chop_from
	sword.modulate = Color(1.0, 1.0, 1.0, 0.0)
	sword.position = battle._world_pos(front, 2.4)  # 举过头顶
	battle._world.add_child(sword)
	var gt: Tween = battle._reg_tween()
	gt.tween_property(sword, "modulate:a", 1.0, 0.22)
	await battle._wait_sim(0.55)
	if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 free), 回来必须重新确认
	if not u.get("alive", false):
		if is_instance_valid(sword): sword.queue_free()
		return

	# ② 下劈: 逐格抡过半圈, 同时落到地面高度。
	#    ★走 `_wait_sim` 不走 tween —— tween 走未钳制真实 delta, 与实拍的游戏时钟对不上
	#    (v0.19.345 在 006 上量出来过: 0.15 秒的转向实拍只占 24ms)。
	for step in range(1, BSW_CHOP_ARC + 1):
		await battle._wait_sim(BSW_CHOP_STEP)
		if not is_instance_valid(battle): return
		if not is_instance_valid(sword): break
		var k: float = float(step) / float(BSW_CHOP_ARC)
		sword.frame = posmod(chop_from + int(round(float(chop_arc) * k)), BSW_DIRS)
		sword.position = battle._world_pos(front, lerpf(2.4, 0.8, k))
	if not u.get("alive", false):
		if is_instance_valid(sword): sword.queue_free()
		return
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._splash_ring_bold(front, Color(0.80, 0.52, 0.28, 0.92), 130.0)   # 劈地冲击环(硬边像素环·锈色)
	if is_instance_valid(sword):
		var sf: Tween = battle._reg_tween()
		sf.tween_property(sword, "modulate:a", 0.0, 0.16); sf.tween_callback(sword.queue_free)

	# ③ 剑气墙沿 dir 扫 BROADSWORD_REACH 码。
	#    ★换真素材 + NEAREST + **8 向选帧**, 不再用 `camera_basis × roll` 手动转 basis。
	var dirf: int = _screen_dir_frame(dir, BSW_DIRS)
	var qi := Sprite3D.new()
	qi.texture = _bsw_wall_tex()
	qi.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	qi.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	qi.shaded = false; qi.transparent = true
	qi.pixel_size = BSW_WALL_PX
	qi.frame = 0
	qi.hframes = BSW_DIRS; qi.vframes = BSW_WALL_FRAMES
	qi.frame = dirf
	battle._world.add_child(qi)
	var reach := BROADSWORD_REACH
	var traveled := 0.0
	var trail_next := 0.0
	var anim := 0.0
	var hit: Array = []
	while is_instance_valid(battle) and traveled < reach and is_instance_valid(qi) and is_instance_valid(self):
		await battle.get_tree().process_frame
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		if not u.get("alive", false): break
		var dt: float = battle.get_process_delta_time()
		traveled += 820.0 * dt
		var pos: Vector2 = anchor + dir * (55.0 + traveled)
		qi.position = battle._world_pos(pos, 1.6)
		## 翻涌: 4 帧循环。★行数 = 动画帧, 列 = 方向 ⇒ frame = 行*列数 + 列。
		anim += dt * 14.0
		qi.frame = int(posmod(anim, float(BSW_WALL_FRAMES))) * BSW_DIRS + dirf
		if traveled >= trail_next:   # 沿途留【被犁开的刮痕】, 不再是一串圆环
			trail_next += 240.0
			_bsw_scrape(pos, dir)
		for o in battle._targeting._enemies_of(u):
			if not o.get("alive", false): continue
			var seen := false
			for h in hit:
				if is_same(h, o): seen = true; break   # ★引用比较(is_same)·不用 o in hit(字典内容哈希=053卡死同类坑)
			if seen: continue
			if (o["pos"] - front).dot(dir) <= traveled and battle._on_line(front, dir, o["pos"], 95.0):
				hit.append(o)
				var dd: int = battle._resolve_dmg(u, u["atk"] * sc + float(flat), o, false)
				battle._damage._apply_damage_from(u, o, dd, Color("#dfe8ff"), 0.0, false, true)
				battle._damage._grant_shield(u, dd * shp)             # 命中一个即给盾(用户)
				battle._vfx._hit_spark(o)
	if is_instance_valid(qi):
		var ft: Tween = battle._reg_tween()
		ft.tween_property(qi, "modulate:a", 0.0, 0.2); ft.tween_callback(qi.queue_free)


## 地面刮痕: 剑气墙擦过留下的一道沟。逐帧展开再淡掉。
## ★★这是替掉「沿途撒一串 `_splash_ring_bold` 圆环」的 —— 圆环说明不了任何事
##   (memory fb-vfx-defect-families 的"无含义圆环与白球")。沟说明"这里被扫过了"。
## ★贴地放, 沿行进方向。展开走 `_wait_sim` 不走 tween(同 006 转平那条)。
func _bsw_scrape(at: Vector2, dir: Vector2) -> void:
	var sp := Sprite3D.new()
	sp.texture = _bsw_scrape_tex()
	sp.frame = 0
	sp.hframes = BSW_SCRAPE_FRAMES; sp.vframes = 1
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.axis = Vector3.AXIS_Y                       # 贴地
	sp.no_depth_test = true                        # 恒画在地板之上(同 _splash_ring_bold)
	sp.render_priority = 5
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false; sp.transparent = true
	sp.pixel_size = BSW_SCRAPE_PX
	sp.rotation = Vector3(0.0, -atan2(dir.y, dir.x), 0.0)
	sp.position = battle._world_pos(at, 0.06)
	battle._world.add_child(sp)
	for f in range(1, BSW_SCRAPE_FRAMES):
		await battle._wait_sim(0.035)
		if not is_instance_valid(battle) or not is_instance_valid(sp): return
		sp.frame = f
	var ft: Tween = battle._reg_tween()
	ft.tween_interval(0.5)
	ft.tween_property(sp, "modulate:a", 0.0, 0.45)
	ft.tween_callback(sp.queue_free)

## ── 006 千刃风暴的两个素材件(2026-09-07 从程序生成换成 Blender 真素材) ──
var _sword_up: Texture2D = null
var _sword_fly: Texture2D = null
var _ground_slit: Texture2D = null
const SWORD_TEX_PATH := "res://assets/sprites/vfx/eq006-sword.png"
## 飞行姿态方向表(8 向)。★用户 2026-09-08 实拍后问「剑飞的时候是竖着的？」——
##   第一版整段冲刺剑都是**立着平移**过去的。一把在空中平移的剑没有任何理由保持刃朝上,
##   这与「不能凭空没有逻辑出现」是同一类问题。⇒ 立起来那一下改成蓄力, 发射瞬间转成刃朝前。
## ★为什么是方向表: 像素风只能 90° 无损旋转, 45° 一转就糊(001 飞斩 / 004 毒牙同一条)。
##   角度由 Blender 在渲染时转好(tools/blender_sword.py --dirs 8), 运行时只选帧。
const SWORD_FLY_TEX_PATH := "res://assets/sprites/vfx/eq006-sword-fly.png"
const SWORD_FLY_DIRS := 8
## 飞行姿态表里"朝上"那一格 = 立姿的同一个朝向(90°)。转平就是从它开始逐格转过去。
const SWORD_UP_FRAME := 2
## 转平【每格停多久】(游戏秒)。3 个姿态 ⇒ 立→斜→横共约 0.10 秒 ≈ 60fps 下 6 帧。
## ★★为什么按"每格"而不是"总时长": 弧长不一样(朝左右 2 步、朝上下 4 步),
##   按总时长分的话朝上下时每格只剩一半, 会快到看不出转过。
## ★★★为什么**不用 tween**: tween 走【未钳制的真实 delta】, 而战斗时钟 `_t` 走钳制后的
##   (CLAUDE.md §3.5.1)。截图时一帧的真实耗时远大于游戏时钟推进量 ⇒ tween 跑飞:
##   实拍(12ms 一档)量到整个转平只占 ~24ms 游戏时间, 而我设的是 0.15 秒。
##   改走 `_wait_sim` 之后, **演出的口径和量它的口径是同一条时钟**, 实拍量到多少就是多少。
const SWORD_TURN_STEP := 0.05
const SWORD_FLY_H := 1.0          # 飞行高度(米) —— 龟立绘 2.0 米, 所以是胸高
## 场地 y 轴投到屏幕的压缩系数。战斗相机 pos(0,28,22) look_at(0,0.6,0) ⇒ 俯角 ≈51°。
## ★8 个方向每格 45°, 对这个系数**很不敏感**(0.78 与 1.0 算出来的角落在同一格),
##   但仍焊了一条门禁量真实投影比 —— 相机哪天改了要有人知道。
const SWORD_SCREEN_SQUASH := 0.78
const SLIT_TEX_PATH := "res://assets/sprites/vfx/eq006-groundslit.png"
const GROUND_SLIT_FRAMES := 6   # 地缝裂开的帧数(tools/blender_groundslit.py 渲)
const SWORD_CELL := 48          # 剑贴图单元格边长(像素) —— 遮罩式"升起"要按它算
const SWORD_TIP_ROW := 2        # 剑尖所在行(上面两行是空白余量) —— 遮罩高度不能小于它
## ★★这两个 pixel_size 是**成对**的, 别单独调其中一个:
##   缝是预兆、剑是正主, 预兆一旦比正主大就抢镜(0.075 那版缝长 3.1 米 vs 剑 1.7 米,
##   实拍里七个大灰盘子把剑完全盖住)。verify_sword_storm_chain 焊着 缝长 ≤ 剑高×1.2。
const SLIT_PIXEL_SIZE := 0.045    # 缝: 42 像素 × 0.045 = 1.89 米长
const SWORD_PIXEL_SIZE := 0.040   # 剑: 44 像素 × 0.040 = 1.76 米高(龟立绘 2.0 米)
const SWORD_RANK_N := 7           # 剑阵把数 = 地缝道数(预兆自带信息量: 数量与位置都是真的)
const SWORD_RANK_GAP := 85.0      # 相邻两把的横向间距(码)
const SWORD_SPAWN_BACK := 130.0   # 剑阵在携带者【身后】多远出生(码)
## 冲之前整排先往后收一步的落点。★冲刺循环的起点必须**也**用它, 两处写死同一个数
##   就会漂(我第一版写了两个 -175, 改一个另一个不动 ⇒ 冲刺第一帧瞬移)。
const SWORD_BRACE_BACK := 175.0

func _sword_up_tex() -> Texture2D:
	if _sword_up == null:
		_sword_up = load(SWORD_TEX_PATH)
	return _sword_up

func _ground_slit_tex() -> Texture2D:
	if _ground_slit == null:
		_ground_slit = load(SLIT_TEX_PATH)
	return _ground_slit


var _bsw_sword: Texture2D = null
var _bsw_wall: Texture2D = null
var _bsw_scrape_t: Texture2D = null

func _bsw_sword_tex() -> Texture2D:
	if _bsw_sword == null:
		_bsw_sword = load(BSW_SWORD_TEX)
	return _bsw_sword

func _bsw_wall_tex() -> Texture2D:
	if _bsw_wall == null:
		_bsw_wall = load(BSW_WALL_TEX)
	return _bsw_wall

func _bsw_scrape_tex() -> Texture2D:
	if _bsw_scrape_t == null:
		_bsw_scrape_t = load(BSW_SCRAPE_TEX)
	return _bsw_scrape_t

func _sword_fly_tex() -> Texture2D:
	if _sword_fly == null:
		_sword_fly = load(SWORD_FLY_TEX_PATH)
	return _sword_fly

## 行进方向 → 飞行姿态帧下标。★量的是【屏幕投影角】不是场地角:
##   场地 y 轴被相机俯角压掉一截, 直接拿场地角选帧, 斜着飞时剑的朝向会偏。
##   屏幕 y 向下、场地 y 也向下 ⇒ 数学角要取负。
func _sword_fly_frame(dir: Vector2) -> int:
	return _screen_dir_frame(dir, SWORD_FLY_DIRS)

## 场地方向 → 【屏幕投影角】的第几格。006 与 007 共用这一份, 别各抄一份
## (memory fb-hand-rolled-copies-drift: 手抄的副本必然落后)。
## ★量的是屏幕投影角不是场地角: 相机俯角 ≈51°, 场地 y 投到屏幕要乘 SWORD_SCREEN_SQUASH。
##   屏幕 y 向下、场地 y 也向下 ⇒ 数学角取负。
func _screen_dir_frame(dir: Vector2, n: int) -> int:
	if dir.length() < 0.001 or n <= 0:
		return 0
	var ang: float = atan2(-dir.y * SWORD_SCREEN_SQUASH, dir.x)
	var idx: int = int(round(ang / (TAU / float(n))))
	return posmod(idx, n)

## 场地方向 → 【贴地素材】的第几格。给 `axis = AXIS_Y`(躺在地上)的 Sprite3D 用。
## ★★别和上面那个 `_screen_dir_frame` 搞混, 两者的口径是**相反**的:
##   · 立着的 billboard(006 飞剑 / 007 剑气墙): 贴图始终正对相机, 所以要按**屏幕投影角**选帧,
##     场地 y 得乘俯角压缩系数、还要取负(屏幕 y 向下而数学角向上)。
##   · 躺在地上的贴图(009 的预警刻痕与月刃): 它跟地面一起被相机投影, **贴图的 u/v 就是场地的 x/y**,
##     所以直接拿场地角、而且 y **不取负**(素材是按"场地 y 向下"烤的, 见 gen_moonslash.py 的注释)。
##   抄错任何一处都会让八格整体偏, 而且肉眼看不出来 —— 007 的剑气墙就一致偏了 175°,
##   是逐格量才发现的(memory fb-verify-check-can-fail 第 6 条)。
func _ground_dir_frame(dir: Vector2, n: int) -> int:
	if dir.length() < 0.001 or n <= 0:
		return 0
	return posmod(int(round(atan2(dir.y, dir.x) / (TAU / float(n)))), n)

## a → b 的【最短有向步数】(可负)。平局(正好半圈)取负 = 顺时针,
## 因为立姿朝上、目标多半在左右, 顺时针那半圈更像"把剑压下来"。
func _frame_arc(a: int, b: int) -> int:
	var d: int = posmod(b - a, SWORD_FLY_DIRS)
	return d if d < SWORD_FLY_DIRS / 2 else d - SWORD_FLY_DIRS

## 转平的一步: t ∈ [0,1] → 沿 arc 逐格转。
## ★★从 tween 里抽成具名函数(CLAUDE.md §3.5 海盗钩索): 无头 CI 推不动 tween,
##   埋在 tween 里就没法验"转平到底是不是瞬间的"。演出调它, 门禁也直接调它。
func sword_turn(spr: Sprite3D, from_f: int, arc: int, t: float) -> void:
	if not is_instance_valid(spr):
		return
	spr.frame = posmod(from_f + int(round(float(arc) * clampf(t, 0.0, 1.0))), SWORD_FLY_DIRS)

## 剑"从地里长出来"的一步: 只画贴图最上 rows 行, 并把这段的【下沿钉在地面】。
## ★★按 CLAUDE.md §3.5(海盗钩索)从 tween 里抽出来: 无头 CI 推不动 tween,
##   逻辑埋在 tween 末尾就等于门禁永远验不到 —— 演出调它, 门禁也直接调它。
## ★不变量: `offset.y * 2 == region_rect.size.y`。它就是"下沿钉地"这句话本身;
##   一旦有人改回"整把剑从 y=-0.25 平移上来", 这条当场红。
func sword_reveal(spr: Sprite3D, rows: float) -> void:
	if not is_instance_valid(spr):
		return
	var hi: int = clampi(int(round(rows)), SWORD_TIP_ROW + 1, SWORD_CELL)
	spr.region_rect = Rect2(0.0, 0.0, float(SWORD_CELL), float(hi))
	spr.offset = Vector2(0.0, float(hi) * 0.5)

## 地缝收尾: 淡出交给 tween(纯观感), **真正的 free 走 `_wait_sim` 主链**。
## ★同上一条: 把 queue_free 埋在 tween 末尾, "有开就有合"这条就没法验。
func _close_slits(slits: Array) -> void:
	for sl in slits:
		if is_instance_valid(sl):
			var t: Tween = battle._reg_tween()
			t.tween_interval(0.30)
			t.tween_property(sl, "modulate:a", 0.0, 0.22)
	await battle._wait_sim(0.62)
	if not is_instance_valid(battle):
		return
	for sl2 in slits:
		if is_instance_valid(sl2):
			(sl2 as Node).queue_free()

func _eq_sword_storm(u: Dictionary, si: int) -> void:   # 千刃风暴(用户改造): 蓄力→身后召一排剑→剑阵前移穿过全体敌
	var flat: int = [70, 100, 400][si]
	var sc: float = [0.8, 1.3, 4.0][si]
	var t = battle._targeting._nearest_enemy(u)
	var dir: Vector2 = ((t["pos"] - u["pos"]).normalized() if t != null else Vector2.RIGHT)
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var ang: float = -atan2(dir.y, dir.x)
	## ★★【锚点在施法那一刻定死】。整套演出跨 3 秒, 而携带者这期间是在走路的:
	##   原来每一段都现读 `u["pos"]`, 于是地缝开在 A 点、0.45 秒后剑从 B 点冒出来
	##   —— 实测差 1.19 米(≈50 码), **剑根本不是从我裂开的那道缝里出来的**。
	##   这正是"不能凭空出现"要防的那件事: 因和果对不上位置, 因果链就断了。
	##   (verify_sword_storm_chain 的第 ② 条就是逐把量这个距离, 阈值 0.06 米。)
	var anchor: Vector2 = u["pos"]
	battle._anticipate(u); battle._shake(battle.JUICE_SHAKE_HEAVY)
	## ★★★蓄力 = 【地面在剑的出生点上裂开 7 道口子】(2026-09-07 用户:「你不能凭空没有逻辑出现」)
	##   改造前两版都错: 原版是 `_make_fire_glow_tex()` 的纯软球(模糊灰云),
	##   我第一次改成一颗八向星 —— 用户直接指出**没解决问题**: 星和球一样是"通用闪光",
	##   既不说明技能要干什么, 自己也照样是凭空出现的。
	##   ⇒ 要的是【因果链】: 地面裂开 → 剑从缝里升起来 → 剑阵前推。
	##     缝的位置与数量**就是**剑阵的位置与数量 ⇒ 预兆自带信息量(对手能读出"会被扫到哪")。
	var n := SWORD_RANK_N
	var slits: Array = []
	for k in range(n):
		var soff: float = (float(k) - float(n - 1) / 2.0) * SWORD_RANK_GAP
		var sl := Sprite3D.new()
		sl.texture = _ground_slit_tex()
		sl.hframes = GROUND_SLIT_FRAMES
		sl.frame = 0
		sl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sl.axis = Vector3.AXIS_Y          # 贴地
		sl.no_depth_test = true           # 恒画在地板之上(同 _splash_ring_bold)
		sl.render_priority = 5
		sl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sl.shaded = false; sl.transparent = true
		## ★★缝的世界长度必须≈剑高, 不能比剑还大。0.075 那版单元格 3.6 米、缝长 3.1 米,
		##   而剑只有 1.7 米 —— **预兆比正主还大一倍**, 实拍里七个大灰盘子把剑完全盖过去。
		##   0.045 ⇒ 缝长 42px × 0.045 = 1.89 米, 与剑高 1.76 米配对。
		sl.pixel_size = SLIT_PIXEL_SIZE
		## 缝【沿剑的行进方向】开 —— 剑从缝里冲出来, 缝当然顺着它冲的方向。
		sl.rotation = Vector3(0.0, ang, 0.0)
		sl.position = battle._world_pos(anchor - dir * SWORD_SPAWN_BACK + perp * soff, 0.06)
		battle._world.add_child(sl)
		slits.append(sl)
		var slr := sl
		var slt: Tween = battle._reg_tween()
		## 逐帧"裂开", 错峰 0.03 秒 —— 与后面剑的错峰同一个节奏
		slt.tween_method(func(f: float) -> void:
			if not is_instance_valid(slr):
				return
			slr.frame = clampi(int(f), 0, GROUND_SLIT_FRAMES - 1),
			0.0, float(GROUND_SLIT_FRAMES), 0.40)
	await battle._wait_sim(0.45)
	if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 free), 回来必须重新确认
	if not u.get("alive", false): return
	var swords: Array = []
	for k in range(n):   # 从每道地缝里【长出来】一把剑: 剑尖先冒头, 逐步露出整把
		var off: float = (float(k) - float(n - 1) / 2.0) * SWORD_RANK_GAP
		var sp := Sprite3D.new()
		## ★★剑【立起来】, 不再贴地(2026-09-07 实拍 48 帧后改)。
		##   贴地(`axis = AXIS_Y`)那版在俯角 51° 的相机下被压掉 37%, 七把剑读成七条斜杠;
		##   而且四方向表的剑尖**四个方向全被画布平切**(逐行量: 刃恒宽 6px 直到护手)。
		##   立起来之后正对相机 ⇒ 方向由"剑阵往哪推"表达, 贴图只要一帧, 也不再需要方向表。
		##   (见 tools/blender_sword.py 头注)
		sp.texture = _sword_up_tex()
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # 与全项目单位立绘同一套
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.shaded = false; sp.transparent = true; sp.pixel_size = SWORD_PIXEL_SIZE
		## ★★"从地里升起来"用【遮罩】不用位移, 也不用缩放:
		##   `region_rect` 只画贴图最上 h 行, `offset = h/2` 把这段的**下沿钉在地面**。
		##   于是剑尖高度 = (h - 剑尖行) × pixel_size, h 从 3 涨到 48 就是剑从地里顶出来。
		##   为什么不位移: 展示台没有地板遮挡, 埋在地下的部分照样画得出来 ⇒ 看着是"整把剑往上飘"。
		##   为什么不缩放: 像素风只能整数倍缩放, 非整数缩放会把像素网格打烂(001/004 同一条)。
		sp.region_enabled = true
		sword_reveal(sp, float(SWORD_TIP_ROW + 1))          # 出生: 只露剑尖
		sp.position = battle._world_pos(anchor - dir * SWORD_SPAWN_BACK + perp * off, 0.0)
		sp.modulate = Color(0.85, 0.9, 1.0, 1.0)
		battle._world.add_child(sp)
		var spr0: Sprite3D = sp
		var st: Tween = battle._reg_tween()
		st.tween_interval(float(k) * 0.03)   # 错峰: 从中间往两边依次顶出来
		st.tween_method(func(h: float) -> void:
			sword_reveal(spr0, h),
			float(SWORD_TIP_ROW + 1), float(SWORD_CELL), 0.30)
		swords.append(sp)
	_close_slits(slits)   # 缝在剑升起来之后合上 —— 有开就要有合, 不能一直裂着
	await battle._wait_sim(0.42)   # 等一排剑生成完
	if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 free), 回来必须重新确认
	if not u.get("alive", false): return
	## ★★"预备"改成【整排往后收一步再冲】 —— 位移, 不是缩放。
	##   改造前是 tween `rotation:y` 转向(自由旋转打烂像素网格), 我上一版换成 scale 弹一下,
	##   1.18 倍**同样是非整数缩放**, 同一条禁忌只是换了个属性。
	##   往后收一步既是纯平移(像素安全), 本身也有因果: 冲之前先蓄一下。
	for bi in range(swords.size()):
		var spr = swords[bi]
		if is_instance_valid(spr):
			var boff: float = (float(bi) - float(n - 1) / 2.0) * SWORD_RANK_GAP
			var tw2: Tween = battle._reg_tween()
			tw2.tween_property(spr, "position",
				battle._world_pos(anchor - dir * SWORD_BRACE_BACK + perp * boff, 0.0), 0.16
				).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await battle._wait_sim(0.34)
	if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 free), 回来必须重新确认
	if not u.get("alive", false): return
	## ★★【转平 = 发射】(2026-09-08 用户拍板)。用户看完上一版实拍问「剑飞的时候是竖着的？」
	##   —— 是的, 整段冲刺剑都立着平移。一把在空中平移的剑没有任何理由保持刃朝上。
	##   ⇒ 立起来那一下变成蓄力, 这里**唰地转成刃朝前**并抬到胸高, 然后才射出去。
	##   转向靠【选帧】不靠转 node: 像素风 45° 旋转会把网格打烂(001/004 同一条)。
	var fly_frame: int = _sword_fly_frame(dir)
	## ★★【逐格转, 不是一帧跳过去】(2026-09-08 用户第二问:「怎么转，你是瞬间吗」)。
	##   第一版这里是 `sf.frame = fly_frame` 一次赋值 —— 立姿 90° 到水平 0° 一帧跳完。
	##   而方向表里**本来就有 45° 那一格**, 白跳的。现在从"朝上"那格出发逐格转到目标格。
	var arc: int = _frame_arc(SWORD_UP_FRAME, fly_frame)
	## 出生高度: 立姿是"下沿钉地"(offset=半格), 飞行姿态以自身为中心 ⇒
	## 换算过来中心要在半格高, 才不会在换装那一瞬间往下掉半把剑。
	var swap_h: float = float(SWORD_CELL) * SWORD_PIXEL_SIZE * 0.5
	for spr3 in swords:
		if is_instance_valid(spr3):
			var sf: Sprite3D = spr3
			sf.texture = _sword_fly_tex()
			sf.region_enabled = false        # 结束"从地里长出来"的遮罩, 回到整张贴图
			sf.frame = 0                     # ★改 hframes 前先归零: setter 会拿新乘积校验当前 frame
			sf.hframes = SWORD_FLY_DIRS
			sf.vframes = 1
			sf.offset = Vector2.ZERO         # 飞行姿态以自身为中心, 不再把下沿钉地
			sf.position.y = swap_h           # 同上: 抵掉 offset 变化, 视觉上原地不动
			sword_turn(sf, SWORD_UP_FRAME, arc, 0.0)   # 起手 = 立姿那一格, 与上一拍无缝
			var lt: Tween = battle._reg_tween()
			lt.tween_property(sf, "position:y", SWORD_FLY_H,
				SWORD_TURN_STEP * float(maxi(1, absi(arc)))
				).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	## 逐格转, **走游戏时钟**(见 SWORD_TURN_STEP 头注)。第 0 格上面已经摆好了。
	for step in range(1, absi(arc) + 1):
		await battle._wait_sim(SWORD_TURN_STEP)
		if not is_instance_valid(battle): return
		if not u.get("alive", false): return
		for spr4 in swords:
			if is_instance_valid(spr4):
				sword_turn(spr4, SWORD_UP_FRAME, arc, float(step) / float(maxi(1, absi(arc))))
	await battle._wait_sim(SWORD_TURN_STEP)   # 转到位再停一格, 让"刃朝前"这一下看得见
	if not is_instance_valid(battle): return
	if not u.get("alive", false): return
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	var reach := 1050.0
	var traveled := 0.0
	var hit: Array = []
	## ★起点跟着上面"往后收一步"走, 不能还写 -SWORD_SPAWN_BACK —— 否则冲刺第一帧会瞬移回去一格。
	var start_along := -SWORD_BRACE_BACK
	while is_instance_valid(battle) and traveled < reach and is_instance_valid(self):
		await battle.get_tree().process_frame
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		traveled += 650.0 * battle.get_process_delta_time()   # 剑速(用户:慢点)
		var front_along: float = start_along + traveled
		for i in range(swords.size()):
			var sp = swords[i]
			if is_instance_valid(sp):
				var off2: float = (float(i) - float(n - 1) / 2.0) * SWORD_RANK_GAP
				sp.position = battle._world_pos(anchor + dir * front_along + perp * off2, SWORD_FLY_H)
				## ★最终朝向【不留在 tween 里】: 冲刺每帧钉一次。
				##   转平的过程是 tween 演的, 但"飞的时候刃朝前"这个**结果**不该依赖它跑完
				##   (tween 被打断 ⇒ 剑朝上飞 = 用户 2026-09-08 报的那个问题)。
				## ⚠ 这一行**没有断言单独守着**: 变异掉它, 转平的 tween 也会落到同一格 ⇒ 门禁不红。
				##   已在 verify_sword_storm_chain 头注按"显式登记缺口"记在案。
				(sp as Sprite3D).frame = fly_frame
		for o in battle._targeting._enemies_of(u):
			if battle._arr_has_unit(hit, o) or not o.get("alive", false): continue
			if (o["pos"] - anchor).dot(dir) <= front_along:
				hit.append(o)
				battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, u["atk"] * sc + float(flat), o, false), Color("#dfe8ff"), 0.0, false, true)
				## ★命中反馈从"白圆环"换成【钢碰壳的火花】(2026-09-07)。
				##   圆环是我记过的通病之一("无含义圆环与白球"): 一把立着的剑扫过去,
				##   地上凭空冒一个圈说明不了任何事; 火花才是这件事本身的结果。
				battle._vfx._hit_spark(o)
	for sp2 in swords:
		if is_instance_valid(sp2):
			var ft = battle._reg_tween()
			ft.tween_property(sp2, "modulate:a", 0.0, 0.14)
			ft.tween_callback(sp2.queue_free)

# ---- 暴君之牙p2eq_004 主动: 剧毒獠牙(参考LoL蛇女Cassiopeia E「双生毒牙」·用户2026-07-19) ----
func _eq_tyrantfang_tick(u: Dictionary, si: int) -> void:   # 每6秒(经_EQ_CUSTOM_IV)射毒牙: 魔法伤1/1.8/4×ATK + 回复100%造成伤害(削弱·用户2026-07-23, 原2/3/7)
	var t = battle._targeting._nearest_enemy(u)
	if t == null: return
	battle._ballistics._fire_venom_fang(u, t, [1.0, 1.8, 4.0][si] * float(u.get("atk", 0.0)))

# 给单位"+N点龟能": 实时版龟能=冷却充能同一事实, 折算 N×0.075 秒扣掉所有技能剩余冷却.
func _eq_grant_energy(u: Dictionary, amount: float) -> void:   # 给龟能=存"龟能银行"(溢出留到下次不浪费, 用户: 贝母021)
	if amount <= 0.0:
		return
	u["energy_bank"] = float(u.get("energy_bank", 0.0)) + amount
	battle._apply_energy_bank(u)

# 娜美式潮浪(海浪护符043): 朝敌人2D方向的对角潮浪 — 从敌人反方向(身后)400码涌起 → 沿"朝敌人"方向慢速推过全场 → 连续宽浪墙(垂直于行进方向铺开)翻涌 → 命中击飞(用户2026-07-04: 全场横扫+2D对角朝敌)
func _eq_water_wave(u: Dictionary, si: int) -> void:
	var enemies = battle._targeting._enemies_of(u)
	var allies = battle._targeting._allies_of(u)
	var ec: Vector2 = u["pos"] + Vector2(500.0, 0.0)   # 敌人质心(默认右)
	if not enemies.is_empty():
		ec = Vector2.ZERO
		for e in enemies: ec += e["pos"]
		ec /= float(enemies.size())
	var dvec: Vector2 = ec - u["pos"]
	var dir: Vector2 = Vector2.RIGHT if dvec.length() < 1.0 else dvec.normalized()   # 浪行进方向=朝敌人(2D可对角)
	var perp: Vector2 = Vector2(-dir.y, dir.x)          # 浪墙铺开方向(垂直于行进)
	var startc: Vector2 = u["pos"] - dir * WAVE_BACK    # 敌人反方向(身后)涌起
	var maxfwd: float = 0.0; var pmin: float = INF; var pmax: float = -INF
	for o in allies + enemies:
		maxfwd = maxf(maxfwd, (o["pos"] - startc).dot(dir))       # 沿行进方向最远单位
		var pp: float = (o["pos"] - u["pos"]).dot(perp)           # 沿浪墙方向的跨度
		pmin = minf(pmin, pp); pmax = maxf(pmax, pp)
	if pmin > pmax: pmin = -150.0; pmax = 150.0
	var tdist: float = maxfwd + 320.0                   # 推过最远单位再多320
	var windup: float = 0.5
	var travel: float = 2.0                             # 慢速(用户)
	battle._anticipate(u)
	battle._water_charge_windup(u, windup)
	battle._spawn_tidal_wave(startc, dir, perp, pmin - 75.0, pmax + 75.0, tdist, windup, travel)
	for o in allies:
		var oo: Dictionary = o
		var fwd: float = clampf((o["pos"] - startc).dot(dir), 0.0, tdist)
		var d: float = windup + fwd / tdist * travel
		var fn := func():
			if not oo.get("alive", false): return
			battle._damage._grant_shield(oo, [40.0, 95.0, 120.0][si])
			oo["base_def"] += [2, 3, 5][si]; oo["base_mr"] += [2, 3, 5][si]; battle._recalc_stats(oo)
			battle._water_splash(oo["pos"], true)
		battle._pending_shots.append({"delay": d, "fn": fn, "src": u})
	for o in enemies:
		var oo2: Dictionary = o
		var fwd2: float = clampf((o["pos"] - startc).dot(dir), 0.0, tdist)
		var d2: float = windup + fwd2 / tdist * travel
		var fn2 := func():
			if not oo2.get("alive", false): return
			battle._damage._apply_damage_from(u, oo2, battle._resolve_dmg(u, float([60, 110, 200][si]), oo2, true), Color("#9be7ff"), 0.0, false, true)   # 魔法伤(蓝字)
			oo2["base_def"] = maxf(0.0, oo2["base_def"] - [2, 3, 5][si]); oo2["base_mr"] = maxf(0.0, oo2["base_mr"] - [2, 3, 5][si]); battle._recalc_stats(oo2)
			battle._water_splash(oo2["pos"], false)
			battle._knock_up(oo2, oo2["pos"] - dir * 60.0, 6.5)   # 娜美式击飞: 顺浪方向往前推(非直上)
			battle._vfx._hit_spark(oo2)
		battle._pending_shots.append({"delay": d2, "fn": fn2, "src": u})

# 潮浪墙: 沿perp(垂直行进)铺一排大浪crest拼成连续宽墙, 整墙从startc沿dir推进tdist; 翻涌帧循环
# 开战: 全装备纯属性 + 永久 flag 加到携带者 (在 spawn 被动之后, 让属性叠上不被覆盖).
# ── 工具 ──
# ── 工具 ──
func _eq_si(star: int) -> int:
	return clampi(star, 1, 3) - 1

func _eq_first_in_line(u: Dictionary, dir: Vector2, width: float):
	var best = null; var bd := INF
	for o in battle._targeting._pick_enemies_of(u):
		if battle._on_line(u["pos"], dir, o["pos"], width):
			var dd: float = (o["pos"] - u["pos"]).length_squared()
			if dd < bd: bd = dd; best = o
	return best

func _eq_farthest_enemies(u: Dictionary, half: bool) -> Array:
	var es = battle._targeting._enemies_of(u)
	es.sort_custom(func(a, b): return (a["pos"] - u["pos"]).length_squared() > (b["pos"] - u["pos"]).length_squared())
	if half:
		return es.slice(0, maxi(1, es.size() / 2))
	return es

# 某一方是否有存活单位携带某装备 (飞镖靶子标记用)
func _eq_charge(stt: Dictionary, key: String, amt: float, cap: float, on_full: Callable) -> void:
	var a: float = (amt * 0.5 if _eq_drone_halve else amt)   # 浮游炮触发→充能减半
	var v: float = float(stt.get(key, 0.0)) + a
	if v >= cap:
		stt[key] = v - cap
		on_full.call()
	else:
		stt[key] = v

# ============================================================================
#  on-hit (每段命中后, attacker 视角)
# ============================================================================
# ============================================================================
#  on-hit (每段命中后, attacker 视角)
# ============================================================================
## ── 飞镖056(用户 2026-07-30 新效果) ──
## 【058 穿甲遗弹】登场召唤的不可移动炮台。
## ★攻速存**次/秒**(文案说的就是这个), 代码要的间隔由它现推 —— 别存间隔再让文案换算。
const TURRET_ASPD := 0.5          # 攻速(次/秒) ⇒ atk_interval = 1 / 它
const TURRET_RANGE := 2000.0      # 射程(码)·全场
const TURRET_BUFF_R := 400.0      # 携带者在此范围内 → 自身获得攻速加成(码)
## 【033 复活海螺】3★ 变虫之后的自我分裂(小虫自己的周期, 不走携带者的 eq_tick)。
const WORM_SPLIT_IV := 2.5        # 每几秒在空位分裂一只
const WORM_CAP := 4               # 场上小虫上限
const WORM_ASPD := 0.65           # 小虫攻速(次/秒) ⇒ atk_interval = 1 / 它
const DART_EVERY := 5              # 每 5 下普攻强化一次
const DART_BLEED_COEF := 0.1       # 飞镖命中施加的流血层数 = ×ATK
## 【003 锋利鲨齿】每段伤害命中后向目标周围溅射。
const SHARKTOOTH_SPLASH_R := 200.0 # 溅射半径(码)·判定与冲击环同一个数
## 【039 竹制弓箭】强化竹箭与它带回的生命球。
## ★这个百分比乘的是 `maxHp / HP_MULT`(CLAUDE.md §3.1) —— 只抽百分比, 不动那个除法。
const BAMBOO_ARROW_MAXHP_PCT := 0.06
const DART_KNOCKUP_SEC := 1.0      # 强化那一击把目标击飞 1 秒(= 位移 + 同时长 stun)
## ⚠ 这个数【不产生位移】: 它传给 `_knockback` 的第三参, 而那个参数在 battle_damage.gd 里
##   叫 `_dist` 且从不被读 —— 真实位移由 battle.KNOCK_VY / KNOCK_PUSH 决定。留着只是占位。
## DART_KNOCKUP_DIST 已删(2026-08-20): 它传给 `_knockback` 的第三参, 而那个参数从不被读 ——
## 一个"看起来能调、实际调了没反应"的常量比没有更坏。击飞位移由 KNOCK_PUSH 决定。


## ── 荆棘海胆015(用户 2026-07-30 效果重做) ──
## 原来: 每次反伤直接给攻击者 2/2.5/3 层流血。
## 现在: 反伤【累计】到阈值 → ①给自己护盾 ②强化下一次普攻(命中施加大量流血)。
## ★阈值随星级【递减】(300→270→230) = 星级越高触发越快, 与"加强"方向一致。
const THORN_REFLECT := [0.12, 0.25, 0.40]     # 反伤比例(原 0.10/0.17/0.25)
const THORN_THRESHOLD := [300.0, 270.0, 230.0]  # 每累计反伤这么多点触发一次
const THORN_SHIELD := [50.0, 70.0, 200.0]     # 触发时给自己的护盾
const THORN_BLEED := [30, 50, 90]             # 强化的那一击命中时施加的流血层数


## 复活海螺033: 小虫诞生时【带 3 件随机装备】(用户 2026-07-30)。
##
## ★星级按【携带者的星级】走 1/2/3 —— 与本项目所有"1/2/3"三档值同一口径。
## ★池子 = 费用 4 或 5 的装备(DataRegistry 的 cost 字段)。允许重复抽(池子只有十几件,
##   强制不重复会在小池子里失败; 而且"随机 3 件"没说不许重复)。
## ★用 battle._battle_rng 抽 —— 裸 randi() 会破坏确定性(rng_discipline 门禁会红)。
func _conch_grant_equips(worm: Dictionary, si: int) -> void:
	var pool: Array = []
	for it in DataRegistry.phase2_equipment:
		var c: int = int(it.get("cost", 0))
		if c == CONCH_COST_MIN or c == CONCH_COST_MAX:
			pool.append(str(it.get("id", "")))
	if pool.is_empty():
		push_warning("[复活海螺] 4/5 费装备池为空 —— 小虫不带装备(不静默塞别的费用)")
		return
	var star: int = [1, 2, 3][si]   # ★写成三元数组而不是 si+1: 文案里的"1/2/3星"要能在代码里找到同样的数组(tooltip_number_audit)
	for _i in range(3):
		var eid: String = str(pool[battle._battle_rng.randi() % pool.size()])
		worm["equips"].append({"id": eid, "star": star})
		# ★装备要真的生效必须走这两步(spawn 期的既有做法, 见 EquipStatsApply):
		#   ①属性(hp/atk/护甲…) ②flag/初始状态(eq_state 里的层数、阈值等)
		_stats._eq_apply_one_stats(worm, eid, star)
		_stats._eq_apply_flags(worm, eid, star)


## ★这里原来是 `const TIDE_MAX_LAYERS := 5`(注释写"方案书: 最多 5 层")。删了, 两个理由:
##   ① 零引用 —— 全仓 grep 只有它自己那一行, 没有任何消费者。
##   ② 值是错的 —— 083 的真上限是 **20**(eq_blade_batch.gd:38/:84「层数上限 20 是硬顶」,
##      data/phase2-equipment.json 也写 20)。留着一个没人读、数还反的常量, 下一个人照它改代码就出事。
##   本文件下方 083 的 on-hit 注释里已经写着"至多 20 层", 事实源在 eq_blade_batch.gd。


## 批② 的【本次伤害 +N%】/【额外真实伤害】统一投递口。
##
## ★★为什么走 `_apply_damage`(DoT/真伤那条路)而不是 `_apply_damage_from`(普攻/技能那条路)
##   —— 这两条路各自扣盾扣血(CLAUDE.md §3.3), 选哪条是有后果的:
##   · on-hit 拿到的 `dmg` 已经是【减伤之后】的数(battle_damage.gd 在 `_mitigate_incoming`
##     之后才调 on-hit)。再走一遍普通伤害就被护甲吃第二遍 —— 文案写"+22%"实发只剩十几点。
##     `bucket="tru"` 跳过减伤, 正好只补上"这一击多打了 N%"这一段。
##   · `_apply_damage` 这条路【结构上就不回钩 on-hit】(它根本没有那段代码), 比靠
##     `from_equip=true` 这个开关更硬 —— 073/075/083 都是"命中→加伤"型, 回钩就是无限自激。
##   · 它也不会再掷一次暴击 / 不会再掷一次闪避 / 不触发反伤链 / 不吃攻击方的
##     猎物增伤·小龟不屈·龟壳复制那三个乘子 —— 那些乘子已经乘进 `dmg` 里了, 再乘就是算两遍。
## ⚠ 诚实记录, 仍有两处二阶重复(不动中央管线就消不掉):
##   ① 决胜增伤 `_sd_amp` 两条路都乘, 所以加成段也会再吃一次;
##   ② 受害者侧的易伤(腐蚀/易碎/猎龟令…)对本段照吃一次。
##   两者都是"全场统一的乘子", 与本批哪一件装备无关。
func _eq_bonus_hit(src: Dictionary, tgt: Dictionary, amount: float, col: Color) -> int:
	if amount < 1.0 or not src.get("alive", false) or not tgt.get("alive", false):
		return 0
	var d: int = maxi(1, int(round(amount)))
	battle._damage._apply_damage(tgt, d, col, src, "tru")
	return d


## `crit`: **攻击方这一发**是否暴击, 由 `_apply_damage_from` 在掷骰当时快照后传进来。
## 传参而不是读全局 —— 见下面 `was_crit` 处的长注释(那个已登记缺口就是这样闭掉的)。
func _eq_on_hit(src: Dictionary, tgt: Dictionary, dmg: int, basic: bool = false, crit = null) -> void:
	if src.get("equips", []).is_empty():
		return
	# AoE 判定(启发式): 同帧内 src 命中≥2个不同目标 → 范围技能 (供 002 等"范围减半"用; 首个目标算单体)
	var _fr: int = Engine.get_process_frames()
	if int(src.get("_onhit_fr", -1)) != _fr:
		src["_onhit_fr"] = _fr; src["_onhit_tgts"] = []
	var _otl: Array = src["_onhit_tgts"]
	if not battle._arr_has_unit(_otl, tgt): _otl.append(tgt)
	var is_aoe: bool = _otl.size() >= 2
	# ★暴击态快照(批② 074 骨簇箭袋 / 076 腐蚀重弩要用)。
	#   `battle._last_atk_crit` 是【全局·最近一次暴击掷骰】, 而下面的循环里别的装备会调
	#   `_atk_dmg`/`_resolve_dmg`(005 双生匕首就是)把它改写 ⇒ 必须在进循环【之前】抓一次。
	#   ★★2026-08-22 这个缺口已闭: 原注释写的「要根治得给 on-hit 加一个入参
	#     (= 改 battle_damage.gd 的中央管线签名)」现在就是这么做的 —— `_apply_damage_from`
	#     在**掷骰那一刻**把 `was_crit` 快照下来(它自己第 252 行早就抓了), 直接传进来。
	#     缺口原文: 从掷骰到调 on-hit 之间, 若【防守方】带反伤(荆棘海胆/石头)或
	#     凤凰熔岩盾/闪电雷盾, 那几段反击也走 raw 掷骰, 会把全局改成"反击那发是否暴击"。
	#     实测频率见 `_eq_crit_gap`(仅 DMGSENTINEL 记账), 门禁 verify_dmg_type_sentinel 盯着。
	#   `crit == null` 只可能来自将来新写的调用方忘了传 —— 那时退回旧行为并记一笔。
	if crit == null:
		_eq_crit_nopass += 1
	elif bool(crit) != bool(battle._last_atk_crit):
		_eq_crit_gap += 1
	var was_crit: bool = bool(crit) if crit != null else bool(battle._last_atk_crit)
	for e in src["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		battle._cur_eq_item = iid   # 盾羁绊9档要认"这次护盾/治疗是哪件装备给的"(用完在函数末尾清)
		var stt: Dictionary = src["eq_state"].get(iid, {})
		# ── 批④(2026-08-06) 统一路由: 放在 match 之前而不是当成 match 的一条臂 ──
		#    十七件分属六个系统, 写成 match 臂就要把十七个 id 抄进【每一个钩子】的 match 里
		#    (十个钩子 × 十七行), 那正是"手抄的副本必然落后"。这里查一次 B4_OWNER 表就够。
		var _b4h = _b4(iid)
		if _b4h != null:
			_b4h.on_hit(src, tgt, float(dmg), iid, si)
		match iid:
			"p2eq_004":   # 暴君之牙: 处决<斩杀线敌 (削弱·用户2026-07-23: 斩杀线 4/6/12% ×(1+暴击率), 原 5/7/10%+10/15/40%×暴击)
				var line: float = [0.04, 0.06, 0.12][si] * (1.0 + float(src["crit"]))
				if tgt["alive"] and not tgt.get("eq_exec_immune", false) and tgt["hp"] < tgt["maxHp"] * line:
					var was: bool = tgt["alive"]
					battle._vfx._float_text(tgt["pos"], "-999999", battle._VC.color_of(battle._VC.cls_for("damage", "true", true)), true, "damage", "true")   # 处决=固定跳-999999真伤大字(实际伤害=剩余血, 用户)
					tgt["hp"] = 0.0
					if was: battle._kill(tgt, src)
			"p2eq_038":   # 信号放大器(用户2026-07-30 效果重做): 每次普攻叠一层放大; 每满 5 层放一道弧形电磁波
				if not basic: continue   # ★规格是【普攻】—— 技能不触发(2026-08-11)
				# ★整套(层数/增伤/攻速/发波/张角递增/魔抗穿透)在 SignalWaveSystem。
				#   原来的实现是"每 6 秒随机一段 3.5 秒增伤", 已整个替换。
				_sigwave.on_hit(src, tgt, si, stt)
				src["eq_state"][iid] = stt
			"p2eq_056":   # 飞镖(用户2026-07-30): 每 5 下普攻, 下一击强化 → 击飞目标 1 秒
				if not basic: continue   # ★规格是【普攻】—— 技能不触发(2026-08-11)
				# ★计数【每 5 下触发一次】—— 用取模而不是"攒到 5 再清零", 两者等价但取模不会
				#   因为中途有别的分支 return 而漏清。第 5/10/15… 下命中即触发。
				var dh: int = int(stt.get("dart_hits", 0)) + 1
				stt["dart_hits"] = dh
				src["eq_state"][iid] = stt
				if dh % DART_EVERY == 0 and tgt.get("alive", false):
					# ★本项目没有独立的"击飞"函数 —— 击飞 = _knockback(位移+抛物演出) + stun_until(期间不能动不能打)。
					#   我一开始写了 _knockup 并用 has_method 兜底 —— 那是【假设 API 存在】, 查了才知道只有 _knockback。
					battle._damage._knockback(src, tgt, 0.0)   # 第三参被忽略, 见 battle_damage._knockback 头注
					tgt["stun_until"] = maxf(float(tgt.get("stun_until", 0.0)), battle._t + DART_KNOCKUP_SEC)
					tgt["_dart_kb_n"] = int(tgt.get("_dart_kb_n", 0)) + 1   # 同步触发证据(供门禁)
					battle._skill_ring(tgt["pos"], Color(1.0, 0.85, 0.4, 0.8), 52.0)
			"p2eq_015":   # 荆棘海胆: 消费"强化下一次普攻" → 命中施加大量流血(用户2026-07-30 重做)
				if not basic: continue   # ★规格是【普攻】—— 技能不触发(2026-08-11)
				# ★强化是【攒着的次数】而不是布尔 —— 一发巨额反伤可能一次攒出好几次,
				#   用布尔会把多出来的吞掉。每次普攻消费一层。
				var emp: int = int(stt.get("thorn_empower", 0))
				if emp > 0 and tgt.get("alive", false):
					stt["thorn_empower"] = emp - 1
					src["eq_state"][iid] = stt
					battle._damage._apply_dot_stacks(tgt, "bleed", THORN_BLEED[si], src)
					battle._skill_ring(tgt["pos"], Color(0.9, 0.35, 0.35, 0.75), 46.0)
			"p2eq_002":   # 辣椒: **只有携带者的普攻**命中才施加流血层 (3★流血层数天然可叠)
				## ★★2026-08-31 用户改需求:「效果变为携带者的普攻施加流血而不是每段伤害了」。
				##   `basic` 这个闸是 `_eq_on_hit` **本来就带的**(battle_damage.gd:447 传进来),
				##   所以不用换钩子, 加一句判断即可。
				## ★同时【删掉】原来那支 `(0.5 if is_aoe else 1.0)` 减半 —— 用户拍板 (a):
				##   只吃普攻之后"范围技能触发的流血"根本不再发生, 那句就是死条款。
				## ★系数**原样不动**(用户:「不用补」) —— 这是一次明知的净削弱:
				##   技能段 / DoT 段 / 追击段从此都不再叠流血。别顺手往上调。
				if not basic:
					return
				var bs: int = maxi(1, roundi([0.075, 0.1, 0.15][si] * src["atk"]))
				battle._damage._apply_dot_stacks(tgt, "bleed", battle._cyeq_n(bs), src)
			"p2eq_003":   # 锋利鲨齿: 溅射200码内敌 + 醒目双层冲击环(no_depth_test防地板盖)+每敌立式火花(用户2026-07-19)
				var frac: float = [0.15, 0.28, 0.50][si]
				battle._splash_ring_bold(tgt["pos"], Color(1.0, 0.80, 0.36, 0.95), SHARKTOOTH_SPLASH_R)   # 醒目双环从命中点扩到200码·恒画在地板之上
				for o in battle._targeting._enemies_of(src):
					if not is_same(o, tgt) and (o["pos"] - tgt["pos"]).length() <= SHARKTOOTH_SPLASH_R:
						battle._damage._apply_damage_from(src, o, maxi(1, int(dmg * frac)), Color("#ffd07a"), 0.0, false, true)
						battle._vfx._hit_spark(o)   # 每个被溅射敌人身上一记立式火花(胸高billboard·地板高度盖不住)
			"p2eq_005":   # 双生匕首: 命中概率追加一刀双生刺击
				if battle._battle_rng.randf() < [0.5, 0.75, 1.0][si]:
					battle._damage._apply_damage_from(src, tgt, battle._atk_dmg(src, [0.7, 0.8, 1.0][si], tgt), Color("#ff4444"), 0.0, false, true)
					battle._vfx.twin_strike(tgt["pos"])   # ★追加刺击要看得见(2026-09-07: 实拍确认原本零演出)
			"p2eq_023":   # 灼热火珊瑚(被动): 每段额外灼烧 + 充能
				## ★★2026-08-31 用户:「炽热火珊瑚改为每段普攻施加灼烧和获得法力而不是每段伤害」
				##   拍板【灼烧与法力两个都收】⇒ 闸放最前, 非普攻两样都不给。
				## ★`basic` 是 `_eq_on_hit` 本来就带的参数(battle_damage.gd:447 传进来), 不用换钩子。
				## ★系数原样不动(用户「不要补」) —— 特意没沿用上一轮辣椒的答案、单独问过一遍。
				## ⚠ 这【不等于】"技能不再涨法力": 法器法力还有另外三路(每 2.5 秒回充 /
				##   造成伤害 ×0.1 / 受伤 ×0.1), 其中"造成伤害"那一路不分普攻技能。
				##   本次收掉的只是 023 这份【定额】。
				if not basic:
					return
				var burn: int = maxi(1, roundi([2.0, 5.0, 8.0][si] + [0.07, 0.11, 0.15][si] * src["atk"]))
				battle._damage._apply_dot_stacks(tgt, "burn", battle._cyeq_n(burn), src)
				## 被动的第二半: 每段命中 +10 **法器法力**(文案逐字:「并获得10点法力」)。
				## ★2026-08-12 从它自己的 `fire_mana` 条改过来 —— 法器只有一条法力条,
				##   主动(火焰波)由法力满触发, 见 fire_equip_effect 的 "p2eq_023" 分支。
				##   add_mana 自带 `_staff_busy` 闸 ⇒ 火焰波打出的灼烧不会回充法力(防连放)。
				battle._staff_syn.add_mana(src, CORAL_MANA_PER_HIT)
			"p2eq_009":   # 宽刃弯刀: 充刃能, 满100→直线伤害
				_eq_charge(stt, "blade_energy", [20.0, 20.0, 25.0][si] * (BLADE_AOE_FACTOR if is_aoe else 1.0), BLADE_FULL, func(): _eq_wide_blade(src, tgt, si))
			"p2eq_026":   # 雷电法杖(被动): 每段伤害为【法器法力条】充能 15(用户 2026-08-12 削弱: 原 25)
				## ★★2026-08-31 用户:「雷电法杖也是改为普攻获得法力」—— 同 023 一道闸。
				##   充能量原样不动(用户「不要补」)。技能伤害仍会经"造成伤害×0.1"那一路涨法力,
				##   本次收掉的只是本件的【定额】。
				if not basic:
					return
				## ★2026-08-12 从它自己的 `thunder` 条改过来 —— 法器只有一条法力条,
				##   主动(连锁闪电)由法力满触发, 见 fire_equip_effect 的 "p2eq_026" 分支。
				##   文案原文就是「每段伤害充能25点;充能满100点时…」, 代码原来另开了一条条子。
				battle._staff_syn.add_mana(src, THUNDER_MANA_PER_HIT)
			"p2eq_029":   # 冰封水母: 概率额外魔伤+冻结, 冻结→自护盾
					pass
			"p2eq_054":   # 瞄准镜: 必中→命中时目标身上一瞬锁定框(表现无视闪避)
				battle._reticle_flash(tgt, Color("#ff6a5a"))
			"p2eq_055":   # 靶向器: 效果已整条替换为【钩索炸弹】(用户2026-08-01), 触发在 _tick_targeter, 命中不再处理
				# ★这里【曾经】是旧效果"命中标记目标 +20% 受伤 5 秒"(写 tgt["eq_marked_until"])。
				#   删掉之后 eq_marked_until 就【零写入】了 —— _mitigate_incoming:4393 那个 ×1.2 的读者
				#   从此恒不成立(死代码, 但留着无害: 它是通用易伤字段, 将来别的效果可以直接写它)。
				#   ★要加新的易伤来源就写 eq_marked_until; 别在这里把旧效果加回来 —— 会和新效果叠着生效。
				pass
			# ══ 批②(2026-08-05) 命中类新装备 · 按类型分组 ═════════════════════
			#    ★效果体一律【外迁成具名函数】(定义在文件末尾的批②段), 这里只留一行分派:
			#      ① tooltip_number_audit 认 `"id": _fn(` 这种分派 → 把函数定义处也当锚点,
			#         数值数组写在函数体里才不会被判"远处命中";
			#      ② 把 40 行效果码塞进 match 会把【已有的 023/026 数组】挤出它们自己的
			#         ±2500 字符锚点窗口 —— 实测确实挤出去了(1545→4046), 那是纯误报但会红门禁。
			# 药水 —— ★067 已由用户整条重做成【毒药瓶】(2026-08-05 §0.5): 效果改成
			#   "每 6 秒投瓶 + 普攻叠中毒 + 中毒者治疗/护盾减半", 落点是【周期】与【普攻】两个钩子,
			#   on-hit 上不再有它。别把旧的"打猎物额外真伤"加回来。
			# 弓箭 —— ★073/074/076 已由用户整条重做(2026-08-05 §0.5): 触发时机从【命中】改成
			#   【普攻】(原文都写"每次普攻") ⇒ 落点搬去 _eq_on_basic_attack, on-hit 上不再有它们。
			#   别把旧的"打健康目标加伤 / 暴击追真伤 / 暴击喂腐蚀"加回来 —— 会和新效果叠着生效。
			#   留在 on-hit 的只有 075 的【距离增伤】: 它是"携带者对该目标"的通用增伤, 本就按次命中算。
			"p2eq_075": _bow_sys.on_hit_075(src, tgt, dmg, si)
			# ★批④(2026-08-06)的 on-hit 不写在这个 match 里 —— 见 match 之前那三行统一路由。
			#   这里原来是 `"p2eq_083": _eq_tide_rapier(...)`(旧「连续命中同一目标 +4/7/11%
			#   伤害·最多 5 层」)。083 已被用户整条重做成【潮汐细剑】(至多 20 层, 每层
			#   1/1.5/2% 增伤 + 0.5% 吸血, 且剑士追打计入) ⇒ 旧函数作废、不是搬家。
			# ══ 灵物 3 件(2026-08-05 用户逐件重做·§0.5 定稿) ═════════════════
			#    ★效果本体在 scripts/systems/equip/eq_spirit_batch.gd; 分派仍写成
			#      `"id": _fn(` 形状 —— tooltip_number_audit 靠它把效果函数定义处也当锚点。
			"p2eq_061": _spirit_sys._eq_drill_snail(src, tgt, si, basic)   # ★basic 在函数内闸(【普攻】规格·2026-08-11); 单行保审计锚点形状
			"p2eq_062": _spirit_sys._eq_mantis_strike(src, tgt, dmg, si, basic)   # ★basic 在函数内闸(【普攻】规格·2026-08-11); 单行保审计锚点形状
			"p2eq_063": _spirit_sys._eq_whale_ring(src, tgt, si, basic)   # ★basic 在函数内闸(【普攻】规格·2026-08-11); 单行保审计锚点形状
			# 食物(本体在 eq_food_batch.gd)
			"p2eq_070": _food_sys._eq_ballast_brick(src, tgt, si, basic)   # ★普攻规格·闸在函数内(v0.19.100 六件漏了它, 070 补验收时抓到)
		src["eq_state"][iid] = stt
	battle._cur_eq_item = ""   # ★分发结束立刻清: 不清的话紧随其后的 _grant_shield/_heal(比如盾羁绊冲击波)
							   #   会被误判成"这件装备给的"而白拿 9 档的 20% 转化(实测: 护盾 11 变成 13)

# 雷电法杖 026: 连锁闪电
# 雷电法杖 026: 连锁闪电
func _eq_chain_lightning(u: Dictionary, si: int) -> void:
	## ★连锁是【逐跳单体指向】(每一跳锁一个具体目标) ⇒ 走 §PICK-TARGET 闸, 不锁训龟大师
	##   (用户 2026-08-12 实测点名:「像闪电连锁等不可以锁」)。
	var enemies = battle._targeting._pick_enemies_of(u)
	if enemies.is_empty():
		return
	var hops: int = [4, 5, 6][si]
	var dmg: int = [40, 60, 90][si]
	# 目标序列: 首个随机, 之后每跳=离当前最近(优先未命中; 无未命中则跳已命中, 排除刚打的→两目标间来回弹)
	var seq: Array = []
	var hit: Array = []  # ★2026-07-10 闪退真因: 不能拿【单位字典】当 Dictionary 的 key —— Godot 会对 key 求哈希, 单位字典里有 summons/summon_owner 等互相引用的结构 → recursive_hash 无限递归 → 每次查表刷一条 ERROR: Max recursion reached。改用 Array(.has 走 == 不哈希)。
	var first = enemies[battle._battle_rng.randi() % enemies.size()]
	seq.append(first); hit.append(first)
	var cur = first
	for h in range(hops - 1):
		var cpos: Vector2 = cur["pos"]
		var best_new = null; var bd_new := INF
		var best_any = null; var bd_any := INF
		for o in enemies:
			if is_same(o, cur):
				continue
			var d: float = o["pos"].distance_squared_to(cpos)
			if d < bd_any: bd_any = d; best_any = o
			if not battle._arr_has_unit(hit, o) and d < bd_new: bd_new = d; best_new = o
		var nxt = best_new if best_new != null else best_any
		if nxt == null:
			break
		seq.append(nxt); hit.append(nxt); cur = nxt
	# 逐跳错峰(0.2s): 画锯齿弧+命中爆闪+魔法伤害
	var prev_pos: Vector2 = u["pos"]
	for i in range(seq.size()):
		var tgt = seq[i]
		## ★★2026-09-13: 原来是 `tween_interval(i*0.2)` 逐跳错峰 —— tween 走未钳制真实 delta,
		##   无头下推不动(§3.5) ⇒ **第 2 跳以后根本不落**。改用共享原语(游戏钟)。
		battle._equip_tick_sys.schedule(float(i) * CHAIN_HOP_GAP,
			battle._chain_segment.bind(u, prev_pos, tgt, dmg))
		prev_pos = tgt["pos"]

## ═══════════════════════════════════════════════════════════════════════════
##  【010 激光长刃】整套 —— 2026-09-10 照着现状实拍 100 帧重做
##  (逐帧凭据: docs/studies/20260910-010激光长刃现状逐帧.md; 方案书: docs/plans/20260910-010激光长刃整套重做.md)
##
##  ★重做前逐帧看出来的六条真毛病, 每条对应下面一处:
##    ① 出手没有预备动作(帧 0-3 全黑, 帧 4 直接满屏红) ⇒ _anticipate + 重震屏, 斩击第 0 帧就满范围。
##       ★★**不是加预警**(用户 2026-09-10:「不应该有预警啊」)。我上一版按 009 的套路给它加了
##       0.30 秒预警扇形 —— 那是把 009 评审得出的规矩(预警范围 == 伤害范围)当成通用设计法则,
##       去套一件**文案里根本没有预警**的装备。010 是每隔一次攻击间隔就斩一次的节奏技,
##       加预警 = 每 1.25 秒闪一片红网点还把出手推迟 0.30 秒。门禁 ⑩b 把这条钉死。
##    ② 素材不是像素画(595/2623/2762/21296 色) ⇒ 四张全部重做(tools/gen_laserfan.py)。
##    ③ 像素密度随射程漂到 0.408 米/像素 ⇒ R_TEX 53 → 108, 一律细一倍。
##    ④ 后两帧平均 alpha 只有 56/255, 黑地上读成暗棕爪痕 ⇒ 消散靠碎开, 颜色全程满亮。
##    ⑤ `rotation = Vector3(0, -base_ang, 0)` 自由角旋转 ⇒ 16 向烤进素材, 运行时 rotation 恒 0。
##    ⑥ 气波画 125 码、判定 160 码 ⇒ 条宽由 LASER_CHOP_HALF_W 一个常量同时喂绘制与判定。
## ═══════════════════════════════════════════════════════════════════════════
## 扇面全角。★代码里多处都用**半角**, 所以存全角、半角推导 ——
##   否则改扇面要记得改好几个 60.0, 而文案说的是 120°。
const LASER_ARC_DEG := 120.0
const LASER_HALF_DEG := LASER_ARC_DEG / 2.0
## 【026 雷电法杖】每段伤害给【法器法力条】充多少(用户 2026-08-12 削弱: 原 25)。
const THUNDER_MANA_PER_HIT := 15.0
const LASER_MELEE_BONUS := 250.0   # 激光长刃 010: 近战携带者额外 +250 码半径(用户 2026-08-01)

const LASER_SLASH_TEX := "res://assets/sprites/vfx/eq010-slash.png"  # 扇形斩: 16 向 × 5 帧
const LASER_WAVE_TEX := "res://assets/sprites/vfx/eq010-wave.png"    # 竖劈冲击波: 16 向 × 4 帧
const LASER_CHOP_TEX := "res://assets/sprites/vfx/eq010-chop.png"    # 竖劈落刃: 1 向 × 5 帧
const LASER_DIRS := 16
const LASER_SLASH_FRAMES := 5
const LASER_WAVE_FRAMES := 4
const LASER_CHOP_FRAMES := 5
## 扇形半径在纹理里占多少像素(必须与 tools/gen_laserfan.py 的 R_TEX 一致)。
## `pixel_size = rng × WS / LASER_R_TEX` ⇒ 半径画多远就打多远。
const LASER_R_TEX := 108.0
## 波前半宽在纹理里占多少像素(必须与 tools/gen_laserfan.py 的 BAR_HW_TEX 一致)。
const LASER_WAVE_HW_TEX := 19.0
## ★★竖劈判定半宽(码) —— **同一个常量**同时喂 `laser_chop_slab` 与贴图缩放。
##   旧版这里是写死的 `80.0` 传给 `_on_line`(判定 160 码宽), 而贴图 3.0 米 = 125 码,
##   画 125 打 160、差 22%: 通病「画出来的和打到的不是一回事」。
const LASER_CHOP_HALF_W := 80.0
const LASER_CHOP_SPEED := 550.0    # 波前推进速度(码/秒) —— 与旧版同(用户认可那个手感)
const LASER_SLASH_STEP := 0.05     # 斩击 5 帧 × 0.05 = 0.25 游戏秒
## 波前每步的游戏时长。★★**必须是 SIM_DT(1/60) 的整数倍**: `_wait_sim` 只能停在 sim 步边界上,
##   写 0.035 会被向上取到 3 个 sim 步 = 0.05 秒 ⇒ 波前实际只跑 19.25/0.05 = 385 码/秒,
##   而常量写着 550 —— 又一次「画的推进和打的推进不是一回事」。取 2 个 sim 步 ⇒ 实测速度就是 550。
const LASER_CHOP_STEP := 2.0 / 60.0


## ═══ 可量部分: 纯几何 + 同步结算, **不依赖任何演出 tween** ═══
## (CLAUDE.md §3.5: 一个测"数值对不对"的用例, 不该依赖任何演出 tween 跑完。
##  演出调它们, 门禁也直接调它们 —— 与 009 的 blade_hit_test / blade_release_point 同一套。)

func laser_alive_enemies(src: Dictionary) -> Array:
	var out: Array = []
	for o in battle._targeting._enemies_of(src):
		if o.get("alive", false): out.append(o)
	return out


## 谁被【顶点 org / 朝向 dir / 半径 rng / 全角 LASER_ARC_DEG】的扇形罩住。
## 判定与演出共用同一个 org/dir/rng ⇒ 画到哪就打到哪。
func laser_fan_hits(org: Vector2, dir: Vector2, rng: float, enemies: Array) -> Array:
	var cos_half: float = cos(deg_to_rad(LASER_HALF_DEG))
	var out: Array = []
	for o in enemies:
		var rel: Vector2 = o["pos"] - org
		var d: float = rel.length()
		if d > rng: continue
		if dir.dot(rel / maxf(1.0, d)) < cos_half: continue
		out.append(o)
	return out


## 3★ 半径: 射程 ×2, 近战再 +250(文案原话)。
## ★加在 ×2 **之后** = 对最终半径的加法, 不被 3★ 倍率放大(否则近战 3★ 会变成 +500)。
func laser_fan_range(u: Dictionary, si: int) -> float:
	var rng: float = battle._eff_range(u) * (2.0 if si == 2 else 1.0)
	if bool(u.get("melee", false)):
		rng += LASER_MELEE_BONUS
	return rng


## 一次全额伤害(扇形斩与竖劈波用的是**同一份**公式 —— 文案「各造成一次全额伤害」)。
func laser_hit_dmg(u: Dictionary, si: int, o: Dictionary) -> int:
	return battle._resolve_dmg(u, u["atk"] * [0.6, 1.0, 8.0][si] + [15.0, 32.0, 200.0][si], o, false)


## 扇形斩的**同步结算**: 判定 → 伤害 → 按总伤回血。返回被打到的敌人。
## ★门禁直接调它验数值; 演出在斩击第 0 帧调它 ⇒ 两边永远是同一份账。
func laser_fan_strike(u: Dictionary, si: int, org: Vector2, dir: Vector2, rng: float) -> Array:
	var hits: Array = laser_fan_hits(org, dir, rng, laser_alive_enemies(u))
	var tot: int = 0
	for o in hits:
		var dd: int = laser_hit_dmg(u, si, o)
		battle._damage._apply_damage_from(u, o, dd, Color("#9bf0ff"), 0.0, false, true)
		tot += dd
	if tot > 0: battle._damage._heal(u, tot * [0.35, 0.8, 1.0][si])
	return hits


## 竖劈走廊里, 沿推进方向落在 [d0, d1) 这一格的敌人 —— 即**波前这一步扫过的那一片**。
## ★半宽用 LASER_CHOP_HALF_W(与贴图同一个常量), 不再写死 80.0。
func laser_chop_slab(org: Vector2, dir: Vector2, d0: float, d1: float, enemies: Array) -> Array:
	var out: Array = []
	for o in enemies:
		var rel: Vector2 = o["pos"] - org
		var along: float = rel.dot(dir)
		if along < d0 or along >= d1: continue
		if (rel - dir * along).length() > LASER_CHOP_HALF_W: continue
		out.append(o)
	return out


## 竖劈能推多远(码)。★★**就是扇形半径本身**(用户 2026-09-10 拍板:「让竖劈跟上扇形」)。
##   改之前这里是 `_eff_range(u) * 2.0` —— 不吃 3★ 的 ×2、也不吃近战 +250,
##   于是小龟 3★ 扇形罩 450 码而波只推 200 码: **打 200 码开外那个孤零零的敌人时波够不着他**。
##   (这个落差是重做前就有的, 旧代码同样是 `base_range * 2.0`, 不是这一轮引入的。)
##   ⇒ 现在直接**调 `laser_fan_range` 本人**, 不再各算一份 —— 画到哪、扇到哪、波就推到哪,
##   三个数只有一个来源(手抄的副本必然落后, memory `fb-hand-rolled-copies-drift`)。
func laser_chop_reach(u: Dictionary, si: int) -> float:
	return laser_fan_range(u, si)


## 第 k 档方向对应的**单位向量** —— 与 `_ground_dir_frame` 严格互逆。
## ★两者必须是同一套口径: 判定用它返回的向量, 贴图用 k 号格, 于是"画的"和"打的"永远同一个方向。
func _laser_dir_of(k: int) -> Vector2:
	var a: float = TAU * float(posmod(k, LASER_DIRS)) / float(LASER_DIRS)
	return Vector2(cos(a), sin(a))


## 扇形斩的贴地精灵。★顶点就在格心 ⇒ `position` 直接是释放点, **没有任何锚点偏移**。
## ★`rotation` 恒 0: 方向是烤进素材的第 dirf 格, 不是转贴图 —— 贴地精灵被任意角旋转会重采样,
##   像素网格当场碎(旧版 `rotation = Vector3(0, -base_ang, 0)` 就是这个毛病)。
func _laser_sprite(tex_path: String, vframes: int, dirf: int, f: int, org: Vector2, rng: float, h: float) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = load(tex_path)
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画必须 NEAREST, 否则缩放糊成一团
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.axis = Vector3.AXIS_Y                                    # ★AXIS_Y 本身就是平铺, 不要再加 rotation.x
	sp.shaded = false
	sp.transparent = true
	sp.pixel_size = rng * battle.WS / LASER_R_TEX               # 半径画多远就打多远
	sp.hframes = LASER_DIRS
	sp.vframes = vframes
	sp.frame = f * LASER_DIRS + dirf
	sp.position = battle._world_pos(org, h)
	return sp


## 竖劈冲击波的波前: **世界尺寸固定**(与射程无关) ⇒ 像素密度恒定, 宽度就是判定宽度。
## 这是**一个会动的精灵**, 每一步把它挪到当前推进距离上 —— 文案原话「沿直线推进」。
func _laser_wave_sprite(dirf: int, at: Vector2, h: float) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = load(LASER_WAVE_TEX)
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.axis = Vector3.AXIS_Y
	sp.shaded = false
	sp.transparent = true
	sp.pixel_size = LASER_CHOP_HALF_W * battle.WS / LASER_WAVE_HW_TEX
	sp.hframes = LASER_DIRS
	sp.vframes = LASER_WAVE_FRAMES
	sp.frame = dirf
	sp.position = battle._world_pos(at, h)
	return sp


## ═══ 演出编排(有 await, 走游戏时钟) ═══

func _eq_laser_sweep(u: Dictionary, tgt: Dictionary, si: int) -> void:
	## 文案原话:「每隔一次攻击间隔朝最近的敌人斩出一道 120° 扇形红激光…
	##            若仅命中 1 名敌人则追加一道竖劈冲击波」。
	##
	## ★★**没有预警**(用户 2026-09-10:「不应该有预警啊」)。
	##   我上一版按 009 的套路给它加了 0.30 秒预警扇形 —— 那是把 009 评审里得出的规矩
	##   (预警范围 == 伤害范围)当成了通用设计法则, 去套一件**文案里根本没有预警**的装备。
	##   010 是【每隔一次攻击间隔】就斩一次的节奏技, 不是蓄力型的一击;
	##   给它加预警 = 每 1.25 秒闪一片红网点, 还把出手推迟 0.30 秒。
	##   ⇒ 触发就斩, 伤害在斩击第 0 帧同帧落地。
	if not u.get("alive", false): return
	var raw: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if raw.length() < 0.1: raw = Vector2.RIGHT
	## ★★把瞄准轴**吸附到素材的 16 档**, 然后判定也用吸附后的轴(与 009 同一条)。
	##   贴图只有 16 档而判定用真实角 ⇒ 画出来的扇边和真判定边最多差 11.25°,
	##   在 450 码处两端错开约 88 码 —— 敌人明明画在扇里却不掉血。
	var dirf: int = _ground_dir_frame(raw, LASER_DIRS)
	var dir: Vector2 = _laser_dir_of(dirf)
	var org: Vector2 = u["pos"]
	var rng: float = laser_fan_range(u, si)
	battle._anticipate(u)   # 预备姿势(不是预警 —— 只是携带者自己的出手动作)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	var slash := _laser_sprite(LASER_SLASH_TEX, LASER_SLASH_FRAMES, dirf, 0, org, rng, 0.12)
	battle._world.add_child(slash)
	## ① 伤害与斩击**同一帧**落地。
	var hits: Array = laser_fan_strike(u, si, org, dir, rng)
	## ② 斩击逐帧: 领先边从 -60° 扫到 +60°, 扫过之处径向盖满; 尾段靠碎开消散(不靠变暗)。
	for fi in range(LASER_SLASH_FRAMES):
		if is_instance_valid(slash):
			slash.frame = fi * LASER_DIRS + dirf
		await battle._wait_sim(LASER_SLASH_STEP)
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 free), 回来必须重新确认
	if is_instance_valid(slash): slash.queue_free()
	## ③ 只命中 1 人 ⇒ 追加竖劈冲击波(文案原话)。
	if hits.size() == 1 and u.get("alive", false):
		var cd: Vector2 = (hits[0]["pos"] - u["pos"]).normalized()
		if cd.length() < 0.1: cd = dir
		var cdf: int = _ground_dir_frame(cd, LASER_DIRS)
		await _eq_laser_chop(u, si, u["pos"], _laser_dir_of(cdf), cdf, laser_chop_reach(u, si))


func _eq_laser_chop(u: Dictionary, si: int, org: Vector2, dir: Vector2, dirf: int, reach: float) -> void:
	## 文案原话:「追加一道竖劈冲击波, **沿直线推进**对沿途每名敌人各造成一次全额伤害」。
	##
	## ★★所以画面上必须是**一道波真的在往前走**, 碰到谁谁就在那一刻掉血。
	##   上一版我把它做成沿路径铺 N 条、逐条点亮 —— 几何是对的(每条正是 160 码判定带),
	##   但那不是「波在移动」, 是把效果换个说法重新编码了一遍
	##   (用户 2026-09-10:「我实际的效果就是波在移动, 碰到人造成伤害, 你这样没有遵从装备效果啊」)。
	##
	## ★落刃画在**携带者**身上而不是目标身上: 竖劈是携带者劈出来的, 波才是打人的那一下。
	##   旧版把刀画在目标头上、伤害却靠波飞 0.30 秒才到 ⇒ 玩家看到的「劈」和真正掉血的「波」
	##   不是同一件事(实拍帧 12-19 演完、帧 24 才命中)。
	## ★推进与结算在**同一个 `_wait_sim` 循环**里, 同一条时钟 ⇒ 画面碰到人的那一帧就是掉血那一帧
	##   (memory `fb-second-clock-drops-events`)。
	battle._shake(battle.JUICE_SHAKE_BIG)
	## 落刃: 公告板, 5 帧, 与波同时起手
	var blade := Sprite3D.new()
	blade.texture = load(LASER_CHOP_TEX)
	blade.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	blade.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	blade.shaded = false
	blade.transparent = true
	blade.hframes = 1
	blade.vframes = LASER_CHOP_FRAMES
	blade.frame = 0
	blade.pixel_size = (150.0 * battle.WS) / 48.0
	blade.position = battle._world_pos(org, 1.0)
	battle._world.add_child(blade)
	## 波前: 一个精灵, 每步往前挪
	var wave := _laser_wave_sprite(dirf, org, 0.10)
	battle._world.add_child(wave)
	var hit: Array = []
	var travelled := 0.0
	var step_i := 0
	while travelled < reach:
		var prev: float = travelled
		travelled = minf(reach, travelled + LASER_CHOP_SPEED * LASER_CHOP_STEP)
		if is_instance_valid(wave):
			wave.position = battle._world_pos(org + dir * travelled, 0.10)
			## 0 = 刚出的细亮线; 1/2 = 满波前(两帧交替读作能量在抖); 3 = 到头碎开
			var wf: int = 0 if step_i == 0 else (1 + (step_i % 2))
			if travelled >= reach: wf = 3
			wave.frame = wf * LASER_DIRS + dirf
		if is_instance_valid(blade):
			blade.frame = mini(LASER_CHOP_FRAMES - 1, step_i)
		## ★这一步波前扫过的那一片 [prev, travelled) —— 碰到谁, 谁这一帧掉血
		for o in laser_chop_slab(org, dir, prev, travelled, laser_alive_enemies(u)):
			if battle._arr_has_unit(hit, o): continue
			hit.append(o)
			battle._damage._apply_damage_from(u, o, laser_hit_dmg(u, si, o),
				Color("#9bf0ff"), 0.0, false, true)
			battle._damage._knockback(u, o, 0.0, 0.2, 0.0)
		step_i += 1
		await battle._wait_sim(LASER_CHOP_STEP)
		if not is_instance_valid(battle): return
	if is_instance_valid(blade): blade.queue_free()
	if is_instance_valid(wave): wave.queue_free()   # 有开就有合: 一个都不许留在场上


## ★以下两个函数是 009 的【可量部分】, 从演出里抽出来 —— 演出调它们, 门禁也直接调它们。
##   (CLAUDE.md §3.5: 一个测"数值对不对"的用例, 不该依赖任何演出 tween 跑完。)
func blade_alive_enemies(src: Dictionary) -> Array:
	var out: Array = []
	for o in battle._targeting._enemies_of(src):
		if o.get("alive", false): out.append(o)
	return out


## 谁被 500~800 码 / BLADE_ARC_DEG 度的扇形带罩住。判定与演出共用同一个 org ⇒ 画到哪就打到哪。
func blade_hit_test(org: Vector2, dir: Vector2, enemies: Array) -> Array:
	var cos_half: float = cos(deg_to_rad(BLADE_ARC_DEG * 0.5))
	var out: Array = []
	for o in enemies:
		var rel: Vector2 = o["pos"] - org
		var dist: float = rel.length()
		if dist < BLADE_R_IN or dist > BLADE_R_OUT: continue
		if dir.dot(rel / maxf(1.0, dist)) < cos_half: continue
		out.append(o)
	return out


## 沿 aim 方向在 ±BLADE_SEEK 内自选释放点, 使扇形带**罩住尽可能多的敌人** ——
## 这是把文案原话「自动选定释放点, 使其 500~800 码扇形带罩住敌群」真的实现出来。
##
## ★为什么不再是"带心 650 码对准敌群质心"(2026-07-19 那版): 带宽只有 300 码,
##   而三个 160 码等距排开的敌人跨度就有 320 码 —— 对准质心时外侧两个各差 10 码落在带外。
##   2026-09-08 实拍量到的原话: 携带者 (398,474) / 敌人 (1018,474)(1178,474)(1338,474),
##   质心 1178 ⇒ org=(528,474) ⇒ 三敌距 org 490/650/810 ⇒ **三打三只命中中间一个**,
##   还会误触发"仅命中 1 名敌人 ⇒ 伤害 x2/2.5/3"这条本该只在单挑时给的补偿。
##   带的形状与大小一点没动(用户当年的约束), 动的只是"放在哪"——那本来就是文案说要自动选的。
##
## ★候选点只取【某个敌人正好压在内圈/外圈上】那几个 offset: 这类区间覆盖问题的最优解必在边界,
##   所以不需要扫描步长(扫描会带来"步长多大才够"这种没有答案的参数)。
func blade_release_point(src: Dictionary, dir: Vector2, enemies: Array, aim_dist: float) -> Vector2:
	var base: float = clampf(aim_dist - (BLADE_R_IN + BLADE_R_OUT) * 0.5, -BLADE_SEEK, BLADE_SEEK)
	var cands: Array = [base]
	for o in enemies:
		var d: float = (o["pos"] - src["pos"]).dot(dir)
		cands.append(clampf(d - BLADE_R_IN - 1.0, -BLADE_SEEK, BLADE_SEEK))
		cands.append(clampf(d - BLADE_R_OUT + 1.0, -BLADE_SEEK, BLADE_SEEK))
	var best: float = base
	var best_n: int = -1
	for c in cands:
		var n: int = blade_hit_test(src["pos"] + dir * float(c), dir, enemies).size()
		## 命中数相同时取离"对准质心"最近的那个 ⇒ 罩不罩得住不受影响时, 观感与老版一致
		if n > best_n or (n == best_n and absf(float(c) - base) < absf(best - base)):
			best_n = n
			best = float(c)
	return src["pos"] + dir * best


func _eq_wide_blade(src: Dictionary, tgt: Dictionary, si: int) -> void:   # 宽刃弯刀(用户改造·剑魔Q式): 预警环形扇区(500~800码60度)→黄色月光斩→伤害
	var foes: Array = blade_alive_enemies(src)
	var cen := Vector2.ZERO   # 方向朝敌方整体(质心), 角度对携带者稳定(用户)
	for _o in foes: cen += _o["pos"]
	if not foes.is_empty(): cen /= float(foes.size())
	var aimpt: Vector2 = cen if not foes.is_empty() else tgt["pos"]
	var raw: Vector2 = (aimpt - src["pos"]).normalized()
	if raw.length() < 0.1: raw = Vector2.RIGHT
	## ★★把瞄准轴**吸附到素材的 16 档**, 然后**选释放点和判定都用吸附后的轴**。
	##   贴图只有 16 档而判定用真实角 ⇒ 画出来的扇区边和真判定边最多差 11.25°,
	##   在带心 650 码处两端错开约 127 码 —— 敌人明明画在带里却不掉血, 就是通病「演出与判定不一致」。
	##   不靠加档位解决(32 档贴图会翻倍), 靠**让判定也用同一个角** ⇒ 差值恒为 0。
	##   代价只是瞄准轴落在 22.5° 网格上, 而释放点搜索本来就会沿该轴重新找最优覆盖。
	var dirf: int = _ground_dir_frame(raw, MOON_DIRS)
	var dir: Vector2 = _moon_dir_of(dirf)
	var org: Vector2 = blade_release_point(src, dir, foes, (aimpt - src["pos"]).length())
	## 1) 预警: **一片填充的区域**(不是几条线) —— 上一代最重要的那一样, 我上一版把它删了。
	##    从 alpha 0 淡入, 0.56 秒里脉动两个来回; 峰值只到 0.58 ⇒ 半透, 单位照样画在它上面。
	var tel := _moon_sprite(MOON_BAND_TEX, 1, dirf, org, dir, 0.08)
	tel.modulate.a = 0.0
	battle._world.add_child(tel)
	## ★逐格走 `_wait_sim`(游戏时钟)而不是 tween: tween 走未钳制的真实 delta,
	##   与量它的时刻戳不是同一条时钟, 实拍会量出假时长(v0.19.345 那一课)。
	##   alpha 也在**同一个循环里**直接写 ⇒ 演出与量它的尺子共用一条时钟。
	for gi in range(MOON_TEL_STEPS):
		if is_instance_valid(tel):
			tel.modulate.a = _moon_tel_alpha(float(gi) / float(MOON_TEL_STEPS))
		await battle._wait_sim(MOON_TEL_STEP)
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 free), 回来必须重新确认
	if not src.get("alive", false):
		if is_instance_valid(tel): tel.queue_free()
		return
	battle._shake(battle.JUICE_SHAKE_HEAVY)   # 2) 斩痕: **叠在还亮着的预警上**, 不是"预警收掉再出现"
	var moon := _moon_sprite(MOON_SLASH_TEX, MOON_SLASH_FRAMES, dirf, org, dir, 0.12)
	battle._world.add_child(moon)
	## 3) 伤害: 用**和演出同一个** org / dir 与同一个谓词(手写一份就等于抄一次永远落后一次)
	var hits: Array = blade_hit_test(org, dir, blade_alive_enemies(src))
	var mult: float = ([2.0, 2.5, 3.0][si]) if hits.size() <= 1 else 1.0
	for o in hits:   # 同帧两段同时结算: 物理(红)+真实(白); 飘字各自随机抛物散开(不叠, 无延时)
		battle._damage._apply_damage_from(src, o, int(battle._atk_dmg(src, [0.5, 0.7, 0.9][si], o) * mult), Color("#ff5a5a"), 0.0, false, true)
		battle._damage._apply_damage_from(src, o, int([30, 45, 60][si] * mult), Color("#ffffff"), 0.0, true, true)
	## 4) 斩痕逐帧: 细亮线 → 张开 → 满(热核+冷边) → 碎 → 残片。同样走游戏时钟。
	##    伤害在第 0 帧就结完 —— 斩击本来就是瞬间的, 后面几帧是它留下的痕迹, 不是"还在飞"。
	## ★★消散**只靠碎开 + alpha**, 素材本身全程满亮(逐帧实测平均亮度 194~202)。
	##   上一代是把颜色压暗成灰(实拍 #44-46 / #84-86), 黑场上读成"地上飘着几块灰板" ——
	##   这是 `fb-vfx-defect-families` 的「淡出病」, 也是上一代唯一一个真正的演出缺陷。
	## ★预警**不在斩痕出现时立刻收掉**: 上一代实拍 #24-26 里黄区还亮着, 白光叠在它上面,
	##   读作"在这片区域里劈了一刀"。前两帧原样保持, 之后才淡出。
	for mfi in range(MOON_SLASH_FRAMES):
		if is_instance_valid(moon):
			moon.frame = mfi * MOON_DIRS + dirf
			moon.modulate.a = 1.0 if mfi < MOON_SLASH_FRAMES - 1 else 0.55
		## ★★预警**一起手就退场**, 两帧内退完(用户 2026-09-09:「斩击后为什么还有预警？」)。
		##   预警的活在伤害落地那一刻就干完了 —— 它的唯一职责是"提前告诉你这片地要挨打",
		##   刀已经砍下去了还挂在那儿, 就变成了没有含义的底色。
		##   上一版让它拖到斩痕后期才淡出, 是把"叠在预警上"这条读法用过头了:
		##   叠只需要**斩痕出现的那一瞬**, 之后就该让位给斩痕自己。
		if is_instance_valid(tel):
			var fade: float = clampf(1.0 - float(mfi) * 0.5, 0.0, 1.0)
			tel.modulate.a = (MOON_TEL_A + MOON_TEL_SWING) * fade
			if fade <= 0.0:
				tel.queue_free()
		await battle._wait_sim(MOON_SLASH_STEP)
		if not is_instance_valid(battle): return
	if is_instance_valid(moon): moon.queue_free()
	if is_instance_valid(tel): tel.queue_free()   # 有开就有合: 预警一定收掉


## 预警的 alpha 包络: 前 MOON_TEL_RISE 从 0 淡入, 全程在 0.56 秒里脉动**两个来回**。
## ★抽成纯函数是为了让门禁能直接量它(而不是等演出跑完再截图猜), 也是为了
##   「演出与量它的尺子共用一条时钟」—— 调用点在 `_wait_sim` 循环里逐格写。
func _moon_tel_alpha(u: float) -> float:
	var rise: float = clampf(u / MOON_TEL_RISE, 0.0, 1.0)
	return rise * (MOON_TEL_A + MOON_TEL_SWING * sin(u * TAU * 2.0 - PI * 0.5))


## 第 k 档方向对应的**单位向量** —— 与 `_ground_dir_frame` 严格互逆。
## ★两者必须是同一套口径: 判定用它返回的向量, 贴图用 k 号格, 于是"画的"和"打的"永远同一个方向。
func _moon_dir_of(k: int) -> Vector2:
	var a: float = TAU * float(posmod(k, MOON_DIRS)) / float(MOON_DIRS)
	return Vector2(cos(a), sin(a))


## 009 的两张贴地素材共用这一份摆放(别各抄一份: 两处的口径必须完全一致, 否则预警和刃会错位)。
func _moon_sprite(tex_path: String, vframes: int, dirf: int, org: Vector2, dir: Vector2, h: float) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = load(tex_path)
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画必须 NEAREST, 否则缩放糊成一团
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.axis = Vector3.AXIS_Y                                    # ★AXIS_Y 本身就是平铺, 不要再加 rotation.x
	sp.shaded = false
	sp.transparent = true
	sp.pixel_size = MOON_PIXEL_SIZE
	sp.hframes = MOON_DIRS
	sp.vframes = vframes
	sp.frame = dirf
	## 画布中心 = 释放点 + 瞄准方向 × 带心半径(素材就是这么烤的, 见 tools/gen_moonslash.py)
	sp.position = battle._world_pos(org + dir * MOON_ANCHOR, h)
	return sp
# 灼热火珊瑚 023(主动满法力)
# 灼热火珊瑚 023(主动满法力)
func _eq_fire_coral_active(src: Dictionary, si: int) -> void:
	## 023 灼热火珊瑚【主动】: 蓄力 → 朝敌方挥出一道火焰波, 在 CORAL_ARC_DEG 度扇形内
	## 缓慢推进 CORAL_TRAVEL 码, 扫到的敌人各吃 40/60/90 层灼烧。
	##
	## ★★2026-09-13 重写。上一版实拍 + 探针确诊三条硬伤:
	##   ① 波是 `VfxTex._make_qi_texture()` **程序生成的气波**染橙 —— 复用别件的原语
	##      (素材不复用铁律), 也不是像素画;
	##   ② **没设 texture_filter** ⇒ 探针实测 Sprite3D 默认 `LINEAR_WITH_MIPMAPS`(=3);
	##      而且每帧 `wave.scale = ...` **连续缩放** —— 像素风三条硬约束破了两条;
	##   ③ 推进与判定都挂在 `get_process_delta_time()` 上 = **第二条钟**
	##      (CLAUDE.md §3.5 / memory [[fb-second-clock-drops-events]])。
	##
	## ★★现在: 波 = 沿弧摆的**一排直立火簇**(fire-crest.png, 8 帧循环)。
	##   火焰永远朝上 ⇒ 贴片**一次都不用转**(像素风不许自由旋转),
	##   波变长就**多摆几个(整数个)** ⇒ 不需要连续缩放。形状是被约束逼出来的。
	##   推进走**游戏钟**(`_wait_sim`), 伤害抽成 `_fire_coral_wave_hit()` 供门禁直调。
	if not src.get("alive", false): return
	var es = battle._targeting._enemies_of(src)
	var dir := Vector2.RIGHT
	if not es.is_empty():
		var cen := Vector2.ZERO
		for o in es: cen += o["pos"]
		dir = (cen / float(es.size()) - src["pos"]).normalized()
	battle._anticipate(src); battle._shake(battle.JUICE_SHAKE_HEAVY)   # 蓄力
	await battle._wait_sim(CORAL_WINDUP)
	if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 free)
	if not is_instance_valid(self) or not src.get("alive", false): return
	var origin: Vector2 = src["pos"]
	var t0: float = battle._t
	var pool: Array = []
	var hit: Array = []
	var traveled := 0.0
	while is_instance_valid(battle) and is_instance_valid(self) and traveled < CORAL_TRAVEL:
		await battle._wait_sim(battle.SIM_DT)
		if not is_instance_valid(battle) or not is_instance_valid(self): break
		traveled += CORAL_SPEED * battle.SIM_DT      # ★走游戏钟, 不用未钳制的真实 delta
		_fire_coral_place(pool, origin, dir, traveled, t0)
		_fire_coral_wave_hit(src, origin, dir, traveled, hit, si)
	for sp in pool:
		if is_instance_valid(sp): sp.queue_free()


## 把火簇摆到当前波前上 —— 摆几个是**算出来的整数**(弧长 / 簇间距), 不是缩放。
func _fire_coral_place(pool: Array, origin: Vector2, dir: Vector2, traveled: float, t0: float) -> void:
	if battle._world == null: return
	var half := deg_to_rad(CORAL_ARC_DEG * 0.5)
	## 弧长 = 半径 × 张角; 簇间距取簇宽的 0.62 倍 ⇒ 相邻互相盖住一截, 连成一道波
	var arc: float = traveled * (2.0 * half)
	## ★★间距要按【实际画幅】算, 不是按格宽: 格子 28 texel = 49.7 码, 但火簇**只画了
	##   18.9 texel = 33.5 码**(格里有留白)。按格宽×0.80 = 39.8 码摆 ⇒ 每两簇空 6 码,
	##   弧上出现断口 —— 用户 2026-09-13 一眼看出来:「**为什么你这是两段火焰呢**」。
	##   现在按实际画幅 × 0.70 ⇒ 相邻互相盖住三成, 连成一条不断的弧。
	var step: float = CORAL_CREST_ART_YARDS * 0.70
	var ncol: int = clampi(int(ceil(arc / maxf(1.0, step))) + 1, 2, CORAL_CREST_MAX)
	var n: int = ncol * CORAL_CREST_ROWS
	while pool.size() < n:
		var sp := Sprite3D.new()
		if _firecrest_tex == null: _firecrest_tex = load(CORAL_CREST_TEX)
		if _firecrest_tex == null: return        # 素材没 import 就静默跳过, 不崩战斗
		sp.texture = _firecrest_tex
		sp.hframes = CORAL_CREST_FRAMES
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false; sp.transparent = true
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # ★不设就是 LINEAR_WITH_MIPMAPS(探针实测=3)
		sp.no_depth_test = true
		sp.render_priority = 5
		sp.pixel_size = (CORAL_CREST_YARDS * battle.WS) / float(CORAL_CREST_CELL)
		battle._world.add_child(sp)
		pool.append(sp)
	var fr: int = int((battle._t - t0) * CORAL_CREST_FPS) % CORAL_CREST_FRAMES
	for i in range(pool.size()):
		var sp2 = pool[i]
		if not is_instance_valid(sp2): continue
		if i >= n:
			sp2.visible = false; continue
		sp2.visible = true
		## 沿弧均分: -half .. +half
		## i 拆成【角度位】与【径向排】: 角度铺满扇形, 径向铺满判定带
		var ai: int = i % ncol
		var ri: int = i / ncol
		var a: float = -half + (2.0 * half) * (float(ai) / float(maxi(1, ncol - 1)))
		var d2: Vector2 = dir.rotated(a)
		## 径向偏移: 3 排落在 -43.3 / 0 / +43.3 码, 覆盖 ±68 码 ⊇ 判定带 ±65
		var roff: float = (float(ri) - float(CORAL_CREST_ROWS - 1) * 0.5) * (CORAL_BAND * 2.0 / float(CORAL_CREST_ROWS))
		sp2.position = battle._world_pos(origin + d2 * maxf(0.0, traveled + roff), CORAL_CREST_H)
		## 每簇错开相位 ⇒ 整道波在翻腾, 不是一排同步的复制品(被否过的「规则图案」)
		sp2.frame = (fr + ai * 3 + ri * 5) % CORAL_CREST_FRAMES


## 波前判定 —— **从演出里抽出来**: 门禁直调它验伤害, 不用等演出跑完(CLAUDE.md §3.5)。
func _fire_coral_wave_hit(src: Dictionary, origin: Vector2, dir: Vector2,
		traveled: float, hit: Array, si: int) -> int:
	var half := deg_to_rad(CORAL_ARC_DEG * 0.5)
	var n := 0
	for o in battle._targeting._enemies_of(src):
		if battle._arr_has_unit(hit, o): continue
		var rel: Vector2 = o["pos"] - origin
		if rel.dot(dir) <= 0.0: continue
		if absf(rel.angle_to(dir)) > half: continue          # 扇形内
		if absf(rel.length() - traveled) > CORAL_BAND: continue   # 波前带
		hit.append(o)
		battle._damage._apply_dot_stacks(o, "burn", CORAL_BURN[si], src)
		n += 1
	return n

# ============================================================================
#  on-target (受伤时, 防守者视角)
# ============================================================================
# ============================================================================
#  on-target (受伤时, 防守者视角)
# ============================================================================
func _eq_on_target(u: Dictionary, src: Dictionary, dmg: int) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		battle._cur_eq_item = iid   # 盾羁绊9档要认"这次护盾/治疗是哪件装备给的"(用完在函数末尾清)
		var stt: Dictionary = u["eq_state"].get(iid, {})
		# ── 批④(2026-08-06) 统一路由(理由同 _eq_on_hit: 十七件六个系统, 不抄进每个 match) ──
		#    ★这条钩子挂在【两条伤害路径】上(CLAUDE.md §3.3), 所以 081 的充能条 / 082 的护心反伤 /
		#      085 的受伤转龟能 / 087 的压载舱 都在这里各自收自己那一份。
		var _b4t = _b4(iid)
		if _b4t != null:
			u["_b4_dot"] = false   # ★口径标志: 这一段来自【普攻/技能】路(另一条见 _b4_on_damaged_any)
			_b4t.on_damaged(u, src, float(dmg), iid, si)
		match iid:
			"p2eq_013", "p2eq_014":   # 受击硬化: +def/mr (层上限读 stt["harden_cap"]: 013=20 / 014=25, 见 equip_stats_apply); 013满层给护盾
				var cur: int = int(stt.get("harden_stacks", 0))
				var hcap: int = int(stt.get("harden_cap", 20))
				if cur < hcap:
					cur += 1
					var inc: float = float(stt.get("harden_inc", 1.0))
					u["base_def"] += inc; u["base_mr"] += inc
					battle._recalc_stats(u)
					stt["harden_stacks"] = cur
					if cur >= hcap and not bool(stt.get("harden_given", false)):
						if iid == "p2eq_013":   # 013满层: 海胆护盾(特殊紫色) 100/170/250 + 5/12/20%最大生命(用户2026-07-19; 原50/60/80金盾)
							var _usb: float = float(u.get("shield", 0.0))
							# shield-perm-ok: 013 是【特殊护盾】—— 文案写了「该护盾在 10 秒内逐渐衰减」, 下一行的 urchin_sh_rate 就是它自己的衰减机制; 走通用 4 秒过期会变成"第4秒直接归零"与文案不符
							battle._damage._grant_shield(u, [100.0, 170.0, 250.0][si] + u["maxHp"] * [0.05, 0.12, 0.20][si])
							var _ugot: float = float(u.get("shield", 0.0)) - _usb   # 实际获盾(经shield_amp/上限后)
							u["urchin_sh_left"] = _ugot
							u["urchin_sh_rate"] = _ugot / URCHIN_DECAY   # 10秒内线性衰减完(用户2026-07-19"慢慢衰减")
							battle._urchin_shield_fx(u)   # 紫刺环+紫字, 与普通金盾区分
						stt["harden_given"] = true
			"p2eq_015":   # 荆棘海胆(用户2026-07-30 重做): 反伤真伤 + 【累计到阈值】→ 护盾 + 强化下一次普攻
				if src.get("alive", false) and battle._is_hostile(u, src):
					var refl: float = float(dmg) * float(stt.get("reflect_pct", THORN_REFLECT[0]))
					if refl >= 1.0:
						battle._damage._apply_damage_from(u, src, int(refl), Color("#c9a36b"), 0.0, true, true)   # 反伤=真实伤害跳白字(原_raw_lose静默不跳数字=bug); from_equip防循环
					# ★★重做: 原来是"每次反伤都给攻击者 2/2.5/3 层流血"。
					#   现在改成【累计制】—— 反伤总量每满 THORN_THRESHOLD 点:
					#     ① 给【自己】THORN_SHIELD 点护盾
					#     ② 强化下一次普攻, 命中时施加 THORN_BLEED 层流血(见 _eq_on_hit 的同 id 分支)
					#   ★累计的是【反伤出去的量】refl, 不是"挨了多少打" —— 文案写的是"每反伤 N 点伤害"。
					#   ★用 while 不用 if: 一发巨额反伤应当一次结算多层, 否则会吞掉溢出部分。
					var acc: float = float(stt.get("thorn_accum", 0.0)) + maxf(0.0, refl)
					var thr: float = THORN_THRESHOLD[si]
					var fired := 0
					while acc >= thr and fired < 20:
						acc -= thr
						fired += 1
					if fired > 0:
						battle._damage._grant_shield(u, THORN_SHIELD[si] * float(fired), BattleDamage.COMMON_SHIELD_SEC)   # 通用护盾=4秒(文案没写时长)
						stt["thorn_empower"] = int(stt.get("thorn_empower", 0)) + fired   # 攒着的强化次数
						battle._skill_ring(u["pos"], Color(0.86, 0.72, 0.45, 0.7), 54.0)
					stt["thorn_accum"] = acc
					## ★2026-08-17 补【局内读数】: 015 以前在两张读数表里【一个字都没有】——
					##   玩家看不到离下次触发还差多少, 也不知道下一击有没有被强化。
					##   这正是 068/065/069/074 当初的形状(「越攒越强, 但攒到哪看不见」),
					##   由 `probe_noui` 脚本重扫 eq_state 写入字段扫出来(上一次是人眼扫的, 漏了)。
					##   阈值随星级变(300/270/230) ⇒ 按 EquipReadouts 表头的规矩存归一化镜像。
					stt["thorn_pct"] = clampf(acc / maxf(1.0, thr), 0.0, 1.0) * 100.0
					u["eq_state"][iid] = stt
			"p2eq_017":   # 不沉之锚: 回血移到 _tick_anchor(每0.25秒, 用户2026-08-01); on-hurt 不再处理
				# ★别在这里加回"受伤即回血" —— 那会变成"定时 + 受伤"双份触发。
				#   verify_equip_batch_20260801 ⑫组焊死: on-hurt 不得产生任何治疗。
				pass
			# ── 药水 068 深海气压罐(2026-08-05 用户重做): 受到的伤害存进专属充能条 ──
			"p2eq_068": _potion_sys._eq_pressure_store(u, dmg, si)
		u["eq_state"][iid] = stt
	battle._cur_eq_item = ""   # ★分发结束立刻清: 不清的话紧随其后的 _grant_shield/_heal(比如盾羁绊冲击波)
							   #   会被误判成"这件装备给的"而白拿 9 档的 20% 转化(实测: 护盾 11 变成 13)

# ============================================================================
#  on-dodge (闪避后)
# ============================================================================
# ============================================================================
#  on-dodge (闪避后)
# ============================================================================
func _eq_on_dodge(u: Dictionary) -> void:
	## 060 磷光水母伞: 伞的闪避真挡下一击时闪一记迷你伞残影 —— 按【buff 来源】判,
	## 不遍历 equips: 被罩的队友自己不带这件装备(光环给的), 遍历装备会漏掉他们。
	_spirit_sys.on_parasol_dodge(u)
	for e in u.get("equips", []):
		if str(e["id"]) == "p2eq_046":   # 幽灵墨鱼: 闪避→永久护盾
			var stt: Dictionary = u["eq_state"].get("p2eq_046", {})
			battle._damage._grant_shield(u, float(stt.get("ghost_shield", 30.0)))
			battle._shield_dome(u)   # 专属护盾罩(原注释说的 `_shield_bubble` 已于 2026-09-13 删除)
		# ── 灵物 5 件(2026-08-05 用户逐件重做·§0.5 定稿) ──────────────────
		#    ★060/061 原来挂在这个钩子上的旧效果(闪避→魔法伤 / 闪避→移速)
		#      已整条作废: 060 改成 7 秒周期开伞、061 改成 on-hit 破损。
		#      现在挂闪避钩的是 062 螳螂虾钳(闪避后蓄一发强化普攻)。
		match str(e["id"]):
			"p2eq_062": _spirit_sys._eq_mantis_ready(u, _eq_si(int(e.get("star", 1))))

# ============================================================================
#  on-cast (放主动技后)
# ============================================================================
# ============================================================================
#  on-cast (放主动技后)
# ============================================================================
func _eq_on_cast(u: Dictionary, tgt: Dictionary) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		battle._cur_eq_item = iid   # 盾羁绊9档要认"这次护盾/治疗是哪件装备给的"(用完在函数末尾清)
		if battle._stress or battle._wd_on: battle._dbg_op = "eqcast:" + iid   # 卡死猎手: 定位是哪件装备on-cast卡住(用户2026-07-19)
		match iid:
			"p2eq_027":   # 电棍: 电击已移到 _eq_on_basic_attack(普攻命中消耗1层, 用户2026-07-03); on_cast不处理
				pass
			"p2eq_017":   # 不沉之锚: 锚击移到_eq_on_basic_attack(普攻消耗1充能, 用户2026-07-02); on_cast不处理
				pass
			"p2eq_006":   # 千刃风暴: 移到每7秒 _tick_sword_storm(用户); on_cast不处理
				pass
			"p2eq_007":   # 锈蚀阔剑: 移到每6秒 _tick_broadsword(用户); on_cast不处理
				pass
			"p2eq_008":   # 双穿珊瑚刺: 移到 _tick_coral(**每 9 秒**, 用户 2026-07-19 从 6→9); on_cast 不处理
				pass
			"p2eq_011":   # 饮血护符坠: 连斩已改由【法力条满】触发(2026-08-12); on_cast 不处理
				# ★规则(用户):「法器只有法力条触发的主动效果, 可能有常驻的被动效果」——
				#   法器的主动**只有一个触发口**。011 的连斩本来挂在"施法后", 那是第二个口,
				#   拆掉; 现在唯一入口是 fire_equip_effect → _eq_bloodletting(法力满时调)。
				#   被动(溢出治疗转血护盾, 见 equip_stats_apply)是常驻字段, 不受影响。
				pass
			"p2eq_014":   # 深海堡垒甲: 汲取移到 _tick_fortress(硬化满25层后每8秒汲取, 用户2026-07-02); on_cast不处理
				pass
			"p2eq_022":   # 余烬燃油瓶: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_fuel_throw, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_028":   # 冰霜冻露瓶: 改为每6秒定时(battle._EQ_CUSTOM_IV→_eq_ice_throw, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_030":   # 迷你水晶球A: 法力条集满触发(fire_equip_effect→_eq_crystal_line); 不在任何周期表里; on_cast不处理
				pass
			"p2eq_031":   # 迷你水晶球B: 法力条集满触发(fire_equip_effect→_eq_crystal_sweep); 不在任何周期表里; on_cast不处理
				pass
			"p2eq_039":   # 竹制弓箭: 改为每第3段普攻消耗1次充能(_eq_on_basic_attack, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_048":   # 黄铜手铳: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_pistol_volley, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_049":   # 连发弩: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_crossbow_volley, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_050":   # 幽灵加特林: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_gatling_burst, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_051":   # 激光手枪: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_laser_pistol, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_053":   # 霰弹贝古: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_shotgun_blast, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_057":   # 狙击长管: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_sniper, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_010":   # 激光长刃: 移到独立计时器 _tick_laser(第二普攻扇形斩); on_cast不处理
				pass
			# ★065/066 已由用户整条重做(2026-08-05 §0.5): 065 改成"每次普攻叠攻速 + 5 龟能"、
			#   066 改成"本路第 11 秒喝药变身", 两件都不再挂 on-cast。别把旧效果加回来。
			# ══ 灵物(2026-08-05 用户逐件重做·§0.5 定稿) ═══════════════════════
			#    063 白鲸气环第①段: 放技能后 +30/60/100% 攻速, 持续【本次消耗龟能 ×0.03】秒
			"p2eq_063": _spirit_sys._eq_whale_haste(u, si)
			# ══ 弓箭(2026-08-05 用户逐件重做·§0.5 定稿) ══════════════════
			#    076 连发弩机主动: 放完技能起一轮连射, 发数 = 本次技能消耗龟能 ÷ 8。
			#    ★消耗查 `battle._skill_cost(u, stype)`, 不在任何地方抄一份消耗表。
			"p2eq_076": _bow_sys.on_cast_076(u, si)
	battle._cur_eq_item = ""   # ★分发结束立刻清: 不清的话紧随其后的 _grant_shield/_heal(比如盾羁绊冲击波)
							   #   会被误判成"这件装备给的"而白拿 9 档的 20% 转化(实测: 护盾 11 变成 13)

# 水晶叠层 (A/B共用); splash=true(B 3★): 引爆范围扩大50%波及邻格敌
# 水晶叠层 (A/B共用); splash=true(B 3★): 引爆范围扩大50%波及邻格敌
func _eq_crystal_stack(src: Dictionary, o: Dictionary, si: int) -> void:
	var lv = battle._add_stack(o, "p2crystal", 1, CrystalSystem.MINI_STACK_MAX)
	if lv >= CrystalSystem.MINI_STACK_MAX:
		battle._consume_stacks(o, "p2crystal")
		battle._crystal_sys._crystal_stack_set(o, 0)
		battle._crystal_sys._crystal_detonate(o["pos"])
		battle._damage._apply_damage_from(src, o, battle._resolve_dmg(src, float(o["maxHp"]) * [0.14, 0.17, 0.20][si], o, true), Color("#bfa8ff"), 0.0, false, true)
	else:
		battle._crystal_sys._crystal_stack_set(o, lv)   # 更新可视层数

# 狙击长管 057: 递归开枪
# 狙击长管 057: 递归开枪
const SNIPER_WINDUP := 1.0    # 每一枪的蓄力时长(秒)

func _eq_sniper_windup(u: Dictionary, si: int) -> void:   # 狙击长管057: 每8秒一轮, 每枪先蓄力1秒(瞄准线+枪口聚能+锁定环)再开(用户2026-07-19 / 2026-08-01)
	_eq_sniper_charge_then_fire(u, si, 0)


## 一枪 = 蓄力 SNIPER_WINDUP 秒 → 开火。★用户 2026-08-01「重新开枪需要蓄力」:
##   原来只有本轮【第一枪】蓄力, 击杀后递归追加的后续枪是【立即】开的 —— 一轮下来能瞬间连狙好几个,
##   看上去像"一枪扫掉半个队"。现在把蓄力包进这一层, 首枪与连狙走同一条路径, 不存在"某种枪不蓄力"。
func _eq_sniper_charge_then_fire(u: Dictionary, si: int, depth: int) -> void:
	if not u.get("alive", false): return
	if depth >= SNIPER_MAX_CHAIN: return        # 与 _eq_sniper 同一上限, 防连狙无限递归
	var low = null; var lv := INF
	for o in battle._targeting._pick_enemies_of(u):
		var p: float = CombatMath.hp_frac(o["hp"], o["maxHp"])
		if p < lv: lv = p; low = o
	if low == null: return
	battle._sniper_charge_fx(u, low)
	battle._pending_shots.append({"delay": SNIPER_WINDUP, "fn": func(): _eq_sniper(u, si, depth), "src": u})

func _eq_sniper(u: Dictionary, si: int, depth: int) -> void:
	if depth >= SNIPER_MAX_CHAIN:
		return
	var low = null; var lv := INF
	for o in battle._targeting._pick_enemies_of(u):
		var p: float = o["hp"] / o["maxHp"]
		if p < lv: lv = p; low = o
	if low == null:
		return
	var dir: Vector2 = (low["pos"] - u["pos"]).normalized()
	battle._muzzle_flash(u["pos"], dir, Color("#ff5a5a"))
	battle._shake(battle.JUICE_SHAKE_HEAVY)                                                  # 开枪后坐(用户2026-07-19)
	battle._skill_ring(u["pos"] + dir * 28.0, Color(1.0, 0.42, 0.36, 0.8), 46.0)      # 枪口爆环
	var _snd: float = 1.5 if OS.has_environment("XDBG") else 0.28
	var _tip: Vector2 = low["pos"] + dir * 150.0
	battle._laser_beam(u["pos"], _tip, Color(1.0, 0.24, 0.28, 0.82), 0.17, _snd, 1.0)          # 粗红外辉(醒目狙击曳光)
	battle._laser_beam(u["pos"], _tip, Color(1.0, 0.92, 0.86, 0.96), 0.06, _snd * 0.85, 1.02)   # 白热细核(高速弹道感)
	battle._vfx._hit_spark(low)
	var killed := false
	for o in battle._targeting._enemies_of(u):
		if battle._on_line(u["pos"], dir, o["pos"], 36.0):
			var before: bool = o["alive"]
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, [2.0, 3.0, 7.0][si], o), Color("#ff4444"), 0.0, false, true)
			if before and not o["alive"]:
				killed = true
	if killed:
		_eq_sniper_charge_then_fire(u, si, depth + 1)   # ★连狙也要蓄力(用户2026-08-01), 不再直接 _eq_sniper

# ============================================================================
#  on-kill (击杀者视角) — 暴君之牙
# ============================================================================
# ============================================================================
#  on-kill (击杀者视角) — 暴君之牙
# ============================================================================
func _eq_on_kill(killer: Dictionary, victim: Dictionary) -> void:
	for e in killer.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		if battle._stress or battle._wd_on: battle._dbg_op = "eqkill:%s:%d:%d" % [iid, si, 1 if victim.get("alive", false) else 0]   # 卡死猎手: 定位是哪件装备on-kill卡住(同 _eq_on_cast)
		match iid:
			"p2eq_004":   # 暴君之牙: 处决后回20龟能 (无龟能单位改回40血)
				if battle._has_energy_system(killer):
					_eq_grant_energy(killer, FANG_EXEC_ENERGY)
				else:
					battle._damage._heal(killer, FANG_EXEC_HEAL)
			# ★068 已由用户整条重做成【深海气压罐】(2026-08-05 §0.5): 旧的"击杀永久+攻"
			#   是全表用滥的模板(远古之力/战利品/旧092 同形状), 用户点名作废。
			#   新效果落在【受伤充能 + 每 12 秒释放】上, on-kill 不再有它。
			#   ⚠ 这里原来有一个 `var victim` 的唯一使用点; 参数保留是因为 004 之外将来还会用到。

# ============================================================================
#  on-death (阵亡者视角) — 复活海螺 / 黄铜齿轮 (+ 左轮052 敌亡补弹)
# ============================================================================
# ============================================================================
#  on-death (阵亡者视角) — 复活海螺 / 黄铜齿轮 (+ 左轮052 敌亡补弹)
# ============================================================================
func _eq_on_death(u: Dictionary, _killer) -> void:
	## 096 小木斧: 斧头击杀 / 3 秒内助攻 → +2 砍伐经验。
	## ★挂在 on-death 而不是 on-kill —— on-kill 遍历"击杀者的 equips", 而斧头是召唤物,
	##   身上一件装备都没有, 那条路上永远轮不到它(它还额外要求击杀者 alive,
	##   斧头与目标同归于尽时整条跳过)。
	_axe.on_death(u, _killer)
	## ★亡灵之斧: 斧头自己倒下时安排 2.5 秒后重生(2026-09-01 补 —— 之前 undead_on_death 零调用者,
	##   也就是说亡灵之斧**死了根本不会重生**, 而门禁全绿因为它直接调那个函数)。
	if u.get("_eq_axe", false):
		_axe._fin.undead_on_death(u)
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		battle._cur_eq_item = iid   # 盾羁绊9档要认"这次护盾/治疗是哪件装备给的"(用完在函数末尾清)
		var stt: Dictionary = u["eq_state"].get(iid, {})
		# ── 批④(2026-08-06) 统一路由 —— 094 祖龟碑在这里立碑; 077/080 在这里改召唤物的状态 ──
		var _b4d = _b4(iid)
		if _b4d != null:
			_b4d.on_death(u, iid, si)
		match iid:
			"p2eq_033":   # 复活海螺: 彻底阵亡→原位变形成小虫(通用打法/攻速0.65) + 亡灵变形演出
				battle._conch_transform(u["pos"])
				# ★用户 2026-07-30 加强: 小虫 生命 400/900/5000 → 100/1500/10000, 攻击 30/55/200 → 50/80/200
				var worm = battle._spawn._spawn_summon(u, "worm", [100.0, 1500.0, 10000.0][si], [50.0, 80.0, 200.0][si], {"label": "海螺虫", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})   # 小虫只有星级无等级(去_lvl_mult), 数值即实际
				if worm != null:
					worm["pos"] = u["pos"]
					worm["atk_interval"] = 1.0 / 0.65
					if is_instance_valid(worm["sprite"]):
						worm["sprite"].position = battle._world_pos(u["pos"], battle.GROUND_LIFT)
						var wsc: Vector3 = worm["sprite"].scale
						worm["sprite"].scale = Vector3.ZERO
						var wtw = battle._reg_tween()
						wtw.tween_interval(0.12)
						wtw.tween_property(worm["sprite"], "scale", wsc, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					worm["eq_state"] = {}; worm["equips"] = []
					_conch_grant_equips(worm, si)   # ★用户 2026-07-30: 小虫诞生时带 3 件随机装备
					if si == 2:   # 3★: 标记每周期分裂
						worm["worm_split"] = true
			"p2eq_035":   # 黄铜齿轮: 死亡不销毁不结算(产币走 _tick_gear 每6秒实时到账, 与死亡无关)
				pass
			# 067 毒药瓶: 携带者阵亡 → 立刻撤掉它挂在中毒者身上的【护盾强度减半】。
			# ★必须有: shield_amp 不像 heal_reduce_until 自带到期, 写进去没人撤就是永久减半。
			"p2eq_067": _potion_sys._eq_vial_cleanse(u)
			# 072 铁皮蛋糕盒: 携带者阵亡 → 分裂出【两个】蛋糕礼盒(20/40/100% 携带者最大生命)。
			# ★分裂盒自己也带着 p2eq_072 条目(为的是吃到每帧 _eq_tick), 所以它们死了也会走到这里 ——
			#   `_eq_cake_split` 头一行就用 `_cake_is_box` 挡住, 链条到此终止, 不会无限分裂。
			"p2eq_072": _food_sys._eq_cake_split(u, si, int(e.get("star", 1)))
	# 左轮052: 任何敌人阵亡 → 对方(u的敌方)持左轮的存活单位 +1发子弹 (上限6)
	for o in battle._units:
		if o["alive"] and battle._eff_side(o) != battle._eff_side(u):
			for e2 in o.get("equips", []):
				if str(e2["id"]) == "p2eq_052":
					var rst: Dictionary = o["eq_state"].get("p2eq_052", {})
					rst["revolver_bullets"] = mini(REVOLVER_AMMO, int(rst.get("revolver_bullets", 0)) + 1)
					o["eq_state"]["p2eq_052"] = rst
	# ★这里原来是「064 深渊招魂螺: 友方阵亡 → 额外召一只亡魂」。2026-08-05 用户把 064
	#   整条重做成【溺者的浮囊】(残血幽灵护盾 + 破盾诅咒爆炸), 新设计里**没有亡魂** ——
	#   用户原话「064 亡魂立绘到时候再重做」那条待办也随之作废。效果本体见 eq_spirit_batch.gd。
	battle._cur_eq_item = ""   # ★分发结束立刻清: 不清的话紧随其后的 _grant_shield/_heal(比如盾羁绊冲击波)
							   #   会被误判成"这件装备给的"而白拿 9 档的 20% 转化(实测: 护盾 11 变成 13)

# ============================================================================
#  HP阈值 (首次<50%) — 深海项链 / 珍珠耳环
# ============================================================================
# ============================================================================
#  HP阈值 (首次<50%) — 深海项链 / 珍珠耳环
# ============================================================================
## 【半血救急】044 深海项链 / 045 珍珠耳环共用的触发线: 生命首次降到这个比例以下。
const LOWHP_GATE := 0.5          # 首次 < 此比例 触发(两件共用同一条线)
const NECKLACE_HOT_SEC := 6.0    # 深海项链 044: 回复摊在 6 秒内(用户2026-08-01)
const EARRING_HOT_SEC := 8.0     # 珍珠耳环 045: 回复摊在 8 秒内(用户2026-08-01)

## 开一段【固定总量 / 固定时长】的持续回血。消费侧在 RealtimeBattle3DScene._tick_unit 的
## `if _t < u["eq_hot_until"]` 那两行(与蜡烛 037 的 candle_hot 同一惯例)。
## ★写这里的时候把速率【锁死】: rate = 总量 / 时长, 之后 maxHp 涨了也不重算 ——
##   否则温泉蛋/临时升级顶高 maxHp 时, 实发总量会超过文案写的百分比。
## ★两件同时触发时【取总量更大的那一段】而不是相加: 相加会让速率叠成一条巨额瞬回,
##   把"改成持续回复"这次削弱整个抵消掉。
func _eq_start_hot(u: Dictionary, total: float, secs: float) -> void:
	if total <= 0.0 or secs <= 0.0: return
	var rate: float = total / secs
	var cur_left: float = maxf(0.0, float(u.get("eq_hot_until", 0.0)) - battle._t) * float(u.get("eq_hot_rate", 0.0))
	if total <= cur_left:
		return
	u["eq_hot_rate"] = rate
	u["eq_hot_until"] = battle._t + secs


func _eq_check_hp_threshold(u: Dictionary) -> void:
	if u.get("hp50_fired", false) or u["hp"] > u["maxHp"] * LOWHP_GATE or not u["alive"]:
		return
	var fired := false
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		battle._cur_eq_item = iid   # 盾羁绊9档要认"这次护盾/治疗是哪件装备给的"(用完在函数末尾清)
		match iid:
			"p2eq_044":   # 深海项链: 首次<50%触发, 【6秒内】回复 20/40/80% maxHp(用户2026-08-01, 原为瞬回12/27/40%)
				_eq_start_hot(u, u["maxHp"] * [0.20, 0.40, 0.80][si], NECKLACE_HOT_SEC); fired = true
				battle._heal_body_glow(u)
			"p2eq_045":   # 珍珠耳环: 首次<50%触发, 【8秒内】回复 30/60/100% maxHp(用户2026-08-01, 原为瞬回15/29/65%) + 抛物线火球
				_eq_start_hot(u, u["maxHp"] * [0.30, 0.60, 1.00][si], EARRING_HOT_SEC)
				battle._heal_ascend(u)   # 绿光环上浮(045专属, 不复用044)
				var balls: int = [1, 1, 2][si]
				var es = battle._targeting._pick_enemies_of(u)
				for b in range(balls):
					if es.is_empty(): break
					var o = es[battle._battle_rng.randi() % es.size()]
					battle._spawn_fireball(u, o, int(o["maxHp"] * [0.08, 0.17, 0.30][si]), [30, 70, 150][si])
					battle._skill_ring(o["pos"], Color(1.0, 0.45, 0.12, 0.6), 50.0)   # 火球爆裂环
				fired = true
	if fired:
		u["hp50_fired"] = true
	battle._cur_eq_item = ""   # ★分发结束立刻清: 不清的话紧随其后的 _grant_shield/_heal(比如盾羁绊冲击波)
							   #   会被误判成"这件装备给的"而白拿 9 档的 20% 转化(实测: 护盾 11 变成 13)

# ============================================================================
#  周期 tick (每 2.5 秒) — A类回合节拍效果
# ============================================================================
# ============================================================================
#  周期 tick (每 2.5 秒) — A类回合节拍效果
# ============================================================================
# ★`_sig_tick_fr`(按帧号去重)已删: 它存在的唯一理由是"_eq_tick 每单位调一次、而波是全局的"。
#   2026-08-06 全局推进搬进了 tick_global(主循环每帧只调一次) ⇒ 去重的前提没了。


## 【全局】每帧推进 —— 与"某只龟身上有没有装备"完全无关。
##
## ★★2026-08-06 从 `_eq_tick` 里抽出来的(E 路 agent 报的真耦合)。
##   原来它挂在主循环 `if not u.get("equips", []).is_empty(): _eq_tick(u, delta)` 之内 ⇒
##   **场上没有一个带装备的活单位时, 全局在途表就停摆**:
##     · 094 祖龟碑的携带者已经死了, 碑却要继续放光环与石雷 —— 最容易撞上的正是这一件;
##     · 077 的小手枪 / 079 的医疗炮台 / 080 的直升机在携带者死后都要继续动;
##     · 038 的弧形电磁波、075 的箭雨、076 的连射也一样(它们已经这样躺了一阵子)。
##   现在由主循环每帧直接调一次, 不再需要帧号去重(那个闸本来就是为了抵消"每单位调一次")。
func tick_global(delta: float) -> void:
	_sigwave.tick(delta)
	_bow_sys.tick(delta)   # 弓箭 4 件: 箭雨/连射的在途表 + 演出层
	# 批④(2026-08-06) 六个系统: 小手枪/医疗炮台/直升机/浮游炮群/潮汐碑/符纸/祖龟碑 的自走与结算
	for _b4s in _b4_all():
		_b4s.tick(delta)


## 某个单位【真实落地】(airborne true→false)那一帧, 由主循环调。
## ★为什么要有这个事件: 主循环里 `tick_global` 在 airborne 积分【上方】无条件执行,
##   而积分本身被顿帧/时停门控 ⇒ 冻结期间"倒计时"和"跳跃"走的是两条时钟。
##   凡是"必须与某只龟的落地同帧"的效果, 都该听这个事件, 不该自己数秒。
func on_unit_landed(u: Dictionary) -> void:
	_arcane_sys.on_unit_landed(u)


func _eq_tick(u: Dictionary, delta: float) -> void:
	# ★这里原来有一段"用帧号去重地推进全局在途表"(弧形波/箭雨/连射)。
	#   2026-08-06 整段搬进 `tick_global` —— 见那边的头注(它挂在"该单位有装备"闸里面, 会停摆)。
	# ★这里原来是 084 血牙巨剑的「每帧看一眼是不是跌破 50% 血 → 开关两条常驻 buff」。
	#   2026-08-06 用户把 084 整条重做成【手半剑】(近战/远程两套完全不同的行为),
	#   半血加攻那一半作废 ⇒ 守卫与 `_eq_fang_refresh` 一并删除。084 的新逻辑
	#   (含射程实时转化)在 EqBladeBatch.tick_unit 里, 走下面批④ 的统一 `_b4_eq` 守卫。
	# 灵物 060 磷光水母伞(7 秒/2.5 秒两相自管计时) + 064 溺者的浮囊(首次跌破 35% 血线)
	# + 这两件的演出推进。同样放在 EQ_TICK 闸【之前】—— 相位切换与血线判定都要每帧精度。
	# ★守卫在 tick_unit 内部, 是两个常驻字段(_parasol_si / _bladder_si), 不遍历 equips。
	_spirit_sys.tick_unit(u, delta)
	# 药水 066(本路第 11 秒喝药 + 免疫维持 + 过冲回稳的体型曲线) / 068(充能条 + 激光泄放 +
	# 每 12 秒释放) / 065 油膜光晕 / 067 中毒场。同样在 EQ_TICK 闸【之前】——
	# 「第 11 秒」「每 12 秒」要秒级精度, 2.5 秒的节拍会把触发时刻甩出去 2 秒多。
	# ★守卫是常驻字段 `_potion_tick`(EquipStatsApply 写), 不遍历 equips。
	if bool(u.get("_potion_tick", false)):
		_potion_sys.tick_unit(u, delta)
	# 食物 069(三块糖糕的 80/55/30% 血线 + 两条并存的每秒回血) / 070(灰条逐帧差分 + 每秒 5% 转回
	# + 随最大生命实时变的攻速) / 071(累计损失 50% 补盾) / 072(嘲讽刷新 + 按锁定人数实时算双抗)。
	# 同样在 EQ_TICK 闸【之前】—— 血线与"实时双抗"都要每帧精度, 2.5 秒的节拍会把它们变成一卡一卡的。
	# ★守卫是常驻字段 `_food_eq`(EquipStatsApply 写 / 分裂礼盒自己写), 不遍历 equips。
	if bool(u.get("_food_eq", false)):
		_food_sys.tick_unit(u, delta)
	# ── 批④(2026-08-06) 逐单位推进 ──────────────────────────────────────
	#    ★守卫是常驻字段 `_b4_eq`(EquipStatsApply 在登场时写), 不遍历 equips ——
	#      伤害/tick 是全 95 件装备的公共热路径, 不带这十七件的单位只多一次 dict.get。
	#    ★放在 EQ_TICK(2.5 秒)闸【之前】: 078 的 2 秒交替 / 079 炮台"攻速实时跟随" /
	#      081 举盾计时 / 084 射程实时转化 / 087 的 15/10/4 秒 / 091 的 0.25 秒回血,
	#      全都要每帧精度, 2.5 秒的节拍会把它们变成一卡一卡的。
	if bool(u.get("_b4_eq", false)):
		for _b4u in _b4_all():
			_b4u.tick_unit(u, delta)
	u["eq_timer"] = u.get("eq_timer", 0.0) + delta
	if u["eq_timer"] < battle.EQ_TICK:
		return
	u["eq_timer"] = 0.0
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		battle._cur_eq_item = iid   # 盾羁绊9档要认"这次护盾/治疗是哪件装备给的"(用完在函数末尾清)
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_001":   # 木制长剑: 移到每帧 _tick_rustblade (每3s就绪 + 2000码(全场)射程内有敌即劈·用户2026-07-19 近战→远程剑气); 周期tick不处理
				pass
			"p2eq_012":   # 海藻: 移到 _tick_jelly (每4s, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_016":   # 铁壁盾: 全队盾移到 _tick_ironwall(每5秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_018":   # 守护贝壳: 自回血移到 _tick_shell(每8秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_019":   # 海葵药膏: 移到 _tick_anemone(每7秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_020":   # 哑铃: 移到 _tick_dumbbell(每8秒编排:锻炼锁攻锁充能→掷哑铃击退, 用户2026-07-19 从10秒改; 周期tick不处理)
				pass
			"p2eq_021":   # 守护贝母: 移到 _tick_barnacle(每5秒连接→自己+最高攻友军 +10龟能+10%攻速本场, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_024":   # 龙蛋: 每周期+1吐息, 满3→喷火龙直线扫射
				stt["dragon_stacks"] = int(stt.get("dragon_stacks", 0)) + 1
				if int(stt["dragon_stacks"]) >= 3:
					stt["dragon_stacks"] = 0
					_eq_dragon_breath(u, si)
			"p2eq_025":   # 雷鸣贝壳: 移到每帧 _tick_thunder(每4秒/道间错峰/大雷/伤害在雷中段跳, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_027":   # 电棍: 移到on_cast(施法后电击, 用户描述); 周期tick不处理
				pass
			"p2eq_035":   # 黄铜齿轮: 齿轮层改每6s(_tick_gear), 周期tick不处理
				pass
			"p2eq_034":   # 玩偶小熊: 移到每帧 _tick_doll(4s派小熊 + 满层蓄力召大熊); 周期tick不处理
				pass
			"p2eq_036":   # 温泉蛋: 孵化进度, 满100→全队均摊护盾(一次)
				battle._equip_tick_sys._egg_add_progress(u, EquipTickSystem.EGG_PER_CYCLE)   # 每周期+5 (其余源: 敌死+10/己死+15/造成×0.1/承受×0.1)
			"p2eq_042":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_043":   # 海浪护符: 改为【法力条满直接涌浪】(2026-08-12); 周期tick不处理
				# ★原来是"每周期 +1 巨浪层, 满 3/2/2 层才涌浪" —— 那是第二条充能条。
				#   法器只能有一条充能条(法力条), 所以巨浪层整套取消, 不是搬家。
				pass
			"p2eq_052":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_037":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_038":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_040":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_056":   # 飞镖: 每周期向所有带"靶子"(被击飞)的敌各射1镖+流血
				if OS.has_environment("EQDEMO_EQUIP") and str(OS.get_environment("EQDEMO_EQUIP")) == "p2eq_056":   # demo: 无击飞源→强制标靶看飞镖volley
					for _e in battle._targeting._enemies_of(u):
						if _e.get("alive", false):
							battle._mark_vfx(_e, 5.0, Color("#ffa040")); _e["eq_target_until"] = battle._t + 5.0
				for o in battle._targeting._enemies_of(u):
					if battle._t < o.get("eq_target_until", 0.0):
						o["eq_target_until"] = 0.0
						o["_mark_until"] = battle._t   # 靶子锁定框消失
						battle._spawn_eq_bolt(u, o, battle._resolve_dmg(u, u["atk"] * [1.5, 3.0, 9.0][si] + [130.0, 190.0, 600.0][si], o, false), "res://assets/sprites/vfx/dart.png", Color("#ffe0b0"), true, maxi(1, roundi(u["atk"] * DART_BLEED_COEF)))
		u["eq_state"][iid] = stt
	battle._cur_eq_item = ""   # ★分发结束立刻清: 不清的话紧随其后的 _grant_shield/_heal(比如盾羁绊冲击波)
							   #   会被误判成"这件装备给的"而白拿 9 档的 20% 转化(实测: 护盾 11 变成 13)

# 龙蛋喷火龙: 沿随机有敌的朝向直线扫射 (同列友回血/敌魔伤+灼烧)
# 024 喷火龙(定稿场景): 龙低空沿"敌方质心方向的线"掠射, 边飞边点燃 burn-loop 真像素火燃烧带, 命中敌=fx_explosion金爆+着火+魔伤, 掠过友=绿治疗环
# 龙蛋喷火龙: 沿随机有敌的朝向直线扫射 (同列友回血/敌魔伤+灼烧)
# 024 喷火龙(定稿场景): 龙低空沿"敌方质心方向的线"掠射, 边飞边点燃 burn-loop 真像素火燃烧带, 命中敌=fx_explosion金爆+着火+魔伤, 掠过友=绿治疗环
func _eq_dragon_breath(u: Dictionary, si: int) -> void:
	var es = battle._targeting._pick_enemies_of(u)
	if es.is_empty():
		return
	var cen := Vector2.ZERO
	for o in es:
		cen += o["pos"]
	cen /= float(es.size())
	var anchor = es[0]                               # 瞄最靠质心的敌人=保证龙穿过它(不是瞄质心从两敌之间缝里穿)
	var abest := INF
	for o in es:
		var dd: float = o["pos"].distance_squared_to(cen)
		if dd < abest:
			abest = dd; anchor = o
	var dir: Vector2 = (anchor["pos"] - u["pos"]).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var start: Vector2 = u["pos"]
	var reach: float = 340.0                         # 飞到最远敌人身后(真穿过去), 不再固定760码够不着
	for o in es:
		reach = maxf(reach, (o["pos"] - start).dot(dir) + 260.0)
	var end: Vector2 = start + dir * reach
	var total: float = maxf(1.0, start.distance_to(end))
	var dur: float = clampf(reach / 480.0, 1.6, 2.6)  # 按距离定时长=恒定速度
	## 前摇: 召唤点聚火蓄能再爆发出龙(修「一下冒出来」)
	battle._anticipate(u)
	battle._dragon_sys._dragon_windup(start)                            # 前摇: 召唤点聚火蓄能(~0.55s)再爆发出龙(修"一下冒出来")
	## ★★2026-09-13: 这里原来也是 `tween_interval` + `tween_callback` —— 和 `_dragon_unleash`
	##   里那两段同病。tween 走**未钳制的真实 delta, 无头下推不动**(CLAUDE.md §3.5),
	##   门禁 verify_dragon_breath ④ 实测「走真入口后敌人掉血 0」, 探针打出 `pending=0`
	##   ⇒ 龙**压根没放出来**。改挂进 DragonSystem 的游戏钟队列。
	##   ★教训: 我第一次只修了内层投递, 外层这一条还在 tween 上 —— **一条链要整条查**。
	battle._dragon_sys.schedule_unleash(u, si, start, end, dir, total, dur, DRAGON_WINDUP)


# ═══════════════════════════════════════════════════════════════════════════
#  批① 周期类新装备 15 件 (方案书 docs/plans/20260804-新装备35件效果.md · 2026-08-04)
#  全部经 fire_equip_effect 的 match 分发 —— 不另起周期分发(方案书 §1.3 / R3)。
#  ★数值一律【就近声明】成三元数组: tooltip_number_audit 要求文案里的 "a/b/c"
#    能在【该装备的效果函数体内】找到同样的数组, 提到文件顶部会被判"远处命中"。
# ═══════════════════════════════════════════════════════════════════════════

## ★食物 069/070/072 的旧周期效果(_eq_coral_cake / _eq_ration_brick / _eq_feast_pulse)
##   已于 2026-08-05 随用户逐件重做【整条删除】, 不是搬走:
##     · 069 旧「每 2.5 秒回已损失生命」→ 新【三块糖糕】(80/55/30% 三道阈值线)
##     · 070 旧「每 2.5 秒永久 +最大生命」→ 新【on-hit + 250 码溅射 + 灰色血条】
##     · 072 旧「开战送血 + 全队回已损」→ 新【变身蛋糕礼盒】
##   新的效果本体全在 scripts/systems/equip/eq_food_batch.gd, 走每帧 `_eq_tick` 的
##   常驻字段守卫 `_food_eq`(不是周期分发) ⇒ 它们也从 EQ_IV_BATCH1 里摘掉了。


























## 触发【某一件装备】的周期效果。
## ★2026-08-03 从 _tick_eq_intervals 里抽出来 —— 法器羁绊的【法力条】满了也要触发同一件事:
##   规格原话是"满 100 → 触发这件法器的效果", 那就必须和它【自然到点时走同一条路】,
##   否则会长出两套行为(一套走 tick、一套走法力), 数值与特效各不一样, 而且只有一套会被门禁覆盖。
func fire_equip_effect(u: Dictionary, iid: String, star: int, stt = null) -> void:
	var si: int = _eq_si(star)
	if stt == null:
		stt = u["eq_state"].get(iid, {})
	match iid:
		"p2eq_004": _eq_tyrantfang_tick(u, si)
		"p2eq_048": _eq_pistol_volley(u, si)
		"p2eq_049": _eq_crossbow_volley(u, si)
		"p2eq_050": _eq_gatling_burst(u, si)
		"p2eq_051": _eq_laser_pistol(u, si)
		"p2eq_053": _eq_shotgun_blast(u, si)
		"p2eq_057": _eq_sniper_windup(u, si)
		"p2eq_022": _eq_fuel_throw(u, si)
		"p2eq_028": _eq_ice_throw(u, si)
		"p2eq_030": _eq_crystal_line(u, si)
		"p2eq_031": _eq_crystal_sweep(u, si)
		"p2eq_037": _eq_candle_tick(u, si, stt)
		"p2eq_040": _eq_fpga_tick(u, si)
		"p2eq_042": _eq_ripple_tick(u, si)
		"p2eq_052": _eq_revolver_tick(u, si, stt)
		# ── 批①(2026-08-04) 周期类新装备 · 按类型分组 ────────────────────────
		#    ★不拆成多个分发函数(方案书 R3): 抽出 fire_equip_effect 本来就是为了
		#      "周期到点"与"法器法力满"走同一条路; 再拆一遍等于把它抽掉的问题请回来。
		# 灵物: 2026-08-05 用户逐件重做后, 060~064 五件【一件都不是周期类】——
		#   060 走自管两相计时(_spirit_sys.tick_unit), 061/062/063 走 on-hit/on-dodge/on-cast,
		#   064 走血线 + SpecialBalance。所以这里现在一条灵物分支都没有, 这是对的。
		# 食物: 2026-08-05 用户逐件重做后, 069~072 四件【一件都不是周期类】——
		#   069 走三道血量阈值线, 070 走 on-hit + 每帧灰条, 071 走开局/损失阈值 + SpecialBalance,
		#   072 走变身。全部在 _food_sys(eq_food_batch.gd) 的每帧 tick_unit 里,
		#   所以这里现在一条食物分支都没有, 这是对的。
		# 药水(2026-08-05 用户逐件重做): 067 毒药瓶每 6 秒投一个瓶子
		"p2eq_067": _potion_sys._eq_poison_vial(u, si)
		# 弓箭(2026-08-05 用户逐件重做·§0.5 定稿) —— 效果本体在 eq_bow_batch.gd
		#   只有 075 在这里: 每 6 秒一轮箭雨(落点取敌人最密集处)。
		#   073(攻速 buff 到期) 与 076(0.25 秒逐发连射) 走 EqBowBatch.tick() 每帧推进, 不占周期口。
		"p2eq_075": _bow_sys.rain_start(u, si)
		# ── 批④(2026-08-06) 后 17 件 ────────────────────────────────────────
		#    ★这里原来有十行(077/079/080/081/087/088/089/090/091/094), 全是 AI 编的旧效果,
		#      用户已把这十七件逐件亲手重做 ⇒ **旧函数整批作废, 不是搬家**。别加回来。
		#    ★法器三件(088/089/090)仍然走这条路 —— 它们的触发时机是【法力条满】,
		#      由 StaffSynergySystem 调 fire_equip_effect。所以这三件在这里路由到 on_mana_full;
		#      其余十四件已从 EQ_IV_BATCH1 摘掉, 根本不会走到这个函数。
		"p2eq_088", "p2eq_089", "p2eq_090":
			_arcane_sys.on_mana_full(u, iid, si)
		# ── 法器【补齐】(2026-08-12) ────────────────────────────────────────
		#   ★这五件此前【不在这张表里】= 法力条满了只清零 + 放一根光柱, 效果零触发。
		#     而规格(staff_synergy_system.gd 头注逐字)是「满 200/180/150/120/80 →
		#     **触发这件法器的效果**」—— 十件都该触发, 不是只有能路由的那五件。
		#     用户 2026-08-12 问「每个法器装备又正确接了法力条吗, 能触发主动吗」查出来的。
		#   ★一律接【它原生路径调的同一个函数】(与本函数抽出来的初衷一致:
		#     "周期到点"与"法器法力满"走同一条路), 不另写一套:
		#       011 施法后连斩 → _eq_bloodletting     (原生: _eq_on_cast)
		#       023 火珊瑚主动 → _eq_fire_coral_active(原生: 自己的 fire_mana 满 100)
		#       026 连锁闪电   → battle._chain_windup (原生: 自己的 thunder 满 100)
		#       029 冰道       → _eq_ice_fissure      (原生: 每 12 秒 _tick_ice_fissure)
		#       043 巨浪       → +1 层, 满层才涌浪    (原生: 每周期 +1 层 —— 同一分支, 见下)
		"p2eq_011": _blood_sys._eq_blood_combo(u, si)
		"p2eq_023": _eq_fire_coral_active(u, si)
		"p2eq_026": battle._chain_windup(u, si)
		"p2eq_029": _eq_ice_fissure(u, si)
		# 043: 法力满【直接涌浪】。★今天早些时候这里写的是"+1 巨浪层, 满层才涌浪"(照抄它
		#   原来的周期分支保持同义), 但那样就是法力条和巨浪层两道闸串起来 = 法力满了还不放,
		#   与规则相反。巨浪层已整套取消 —— 法器只能有一条充能条。
		"p2eq_043": _eq_water_wave(u, si)
		# ★092【剧毒飞行物】没有分支 —— 它不是"周期到点触发一次"的形状(0.25 秒节拍 + 每帧飞行),
		#   驱动挂在 RelicSynergySystem.tick() → _venom.tick(delta)。见 eq_venom_drone.gd 文件头。
		# ★094【祖龟碑】也没有分支 —— 改成【阵亡触发】, 走 _eq_on_death → _relic_sys.on_death。


# ═══════════════════════════════════════════════════════════════════════════
#  批② 命中/普攻类新装备 10 件 (方案书 docs/plans/20260804-新装备35件效果.md · 2026-08-05)
#  分派全部落在【已有的】四个钩子上 —— 没有新增分发口(方案书 R3):
#    _eq_on_hit(067 073 074 075 076 083) / _eq_on_basic_attack(078)
#    _eq_on_dodge(060 061) / _eq_on_kill(068)
#  ★数值一律【就近声明】成三元数组: tooltip_number_audit 要求文案里的 "a/b/c"
#    能在【该装备分派到的效果函数体内】找到同样的数组, 提到文件顶部会被判"远处命中"。
# ═══════════════════════════════════════════════════════════════════════════

## ★这里原来是 `_eq_hunter_flask`(067 猎人的酒囊·打猎物额外真伤)。2026-08-05 用户把 067
##   整条重做成【毒药瓶】, 效果本体搬到 eq_potion_batch.gd。**函数整体删除**而不是留个空壳 ——
##   零调用者的死函数会被"断言函数存在"这类门禁保护住, 还可能被 VFXPREVIEW 指过去当成
##   有效目视验证(memory [[fb-verify-must-run-the-real-path]] 那次就栽在这个形状上)。


## ★073 藤蔓弓弦 / 074 鲸骨胸甲 / 075 测距绳结 / 076 连发弩机 ——
##   四件已由用户逐件亲手重写(2026-08-05 §0.5 定稿), 效果本体搬到
##   `scripts/systems/equip/eq_bow_batch.gd`(EqBowBatch), 演出在 `scripts/scenes/battle/bow_eq_vfx.gd`。
##   原来住在这里的 `_eq_vine_bow` / `_eq_bone_quiver` / `_eq_eagle_lens` / `_eq_corroder`
##   是 AI 编的旧效果(打健康目标加伤 / 暴击追真伤 / 距离分档加伤 / 暴击喂腐蚀),
##   已整段删除 —— **不是搬家而是作废**。别把它们加回来: 新效果已占着同一批钩子,
##   加回来就是两套效果叠着生效。



## ★★2026-08-05 状态: **本函数当前零触发, 是一条【休眠的通用免死通道】。**
##   原主人 063 幽影墨囊已被用户整条重做成【白鲸气环】(见 eq_spirit_batch.gd),
##   写 `u["_ink_sac"]` 的那一处(EquipStatsApply._eq_apply_flags)随之删掉 ⇒ 守卫恒不成立。
##   **函数留着不删**, 理由与 `eq_marked_until` 那条完全一样:
##     ① 调用点在 battle_damage.gd 的两条伤害路径上(那是主会话的地盘, 本批不许碰),
##        删函数会让静态类型的 `battle._equip_sys._eq_ink_sac(...)` 直接解析失败;
##     ② 它是一条**写好且两路都挂对了**的通用"免死"通道 —— 将来哪件装备要免死,
##        写 `u["_ink_sac"] = true` + `_ink_sac_si` 即可, 不必重新在两条路上各挂一次。
##   ⚠ 要加新的免死来源就写这两个字段; **别把 063 的旧效果加回来** —— 那件已经是别的东西了。
##
## ── 以下是它原来(063 幽影墨囊)的设计说明, 留作这条通道的行为文档 ──
## 受到【致命】伤害时改为留 1 点血, 并获得 1.5/2/2.5 秒不可选中。
##
## ★★用户拍板 U6-A: 判定挂在 `_mitigate_incoming` 之后、【扣血之前】——
##   而且 **两条伤害路径都要挂**(CLAUDE.md §3.3: `_apply_damage` DoT/真伤 与
##   `_apply_damage_from` 普攻/技能 各自扣盾扣血)。只挂一条 = "只有被普攻打死才救得回来,
##   被灼烧烧死就救不回来" 这类只在某类伤害下出现的诡异行为。
## ★精确位置在【护盾吸收之后】: 护盾先扛, 扛完还致命才算"致命伤害"。
## ★返回值 = 本次【真正扣掉】的血量。返回 hp-1 ⇒ 调用点那句 `hp = maxf(0, hp - d)` 落在 1。
## ★"每场一次" 实装成【每路一次】—— 标记存 eq_state, 换路整体重建单位 ⇒ 天然按路重置。
##   与批① 070/091/092 的累积口径一致(那三件也是按路), 待用户一并拍板。
## ⚠ 诚实记录: 飘字/统计里记的仍是【本来会打进来的那一发】的数字(dmg 在本钩子之前就
##   定型了), 而实际只掉 1 点血。要让数字也跟着变得把钩子提到 `dmg = maxi(...)` 之前,
##   那样又会漏掉护盾这一段, 两害相权取"判定准确"。
func _eq_ink_sac(u: Dictionary, d: float) -> float:
	var stt: Dictionary = u["eq_state"].get("p2eq_063", {})
	if bool(stt.get("ink_used", false)):
		return d
	stt["ink_used"] = true
	u["eq_state"]["p2eq_063"] = stt
	var si: int = int(u.get("_ink_sac_si", 0))
	u["untargetable_until"] = maxf(float(u.get("untargetable_until", 0.0)), battle._t + [1.5, 2.0, 2.5][si])
	battle._skill_ring(u["pos"], Color(0.32, 0.26, 0.42, 0.75), 70.0)
	battle._vfx._float_text(u["pos"] + Vector2(0, -70), "墨遁", Color(0.72, 0.66, 0.9))
	return maxf(0.0, float(u["hp"]) - 1.0)


## ★这里原来是 `_eq_spring_moss`(065 涌泉苔药剂·放技能回已损血) 与 `_eq_surge_brew`
##   (066 狂潮浓缩液·放技能减下一次冷却) 两个函数 + 常量 SURGE_ICD。
##   2026-08-05 用户把 065/066 整条重做成【鲨肝油】与【鲸涎浓浆】, 效果本体搬到
##   eq_potion_batch.gd。**整体删除**而不是留空壳, 理由同上面 067 那段。






## 受到【法术伤害】时的两件奇械(085 / 086)。挂在 `_apply_damage_from` 里 `_eq_on_target`
## 的旁边, 由 `_b3_gadget` 这个常驻 flag 守门 ⇒ 不带这两件的单位一次调用都不会发生。
##
## ★只挂普攻/技能这条路, 【不挂 DoT 那条】: 灼烧/中毒每跳都是法术伤害, 挂上去 085 会
##   按每秒好几次的频率掷骰充能, 那不是"受到法术伤害时"该有的频率。取保守的一侧。
## ★伤害类型用调用点算好的伤害桶 `bkt` 传进来, 不在这里读 `battle._last_dmg_type` ——
##   那个全局在 on-hit 链里会被嵌套的 `_atk_dmg` 覆写(battle_damage.gd:103 的注释写着这件事)。
func _eq_on_magic_hurt(u: Dictionary, src, dmg: int, bkt: String) -> void:
	if bkt != "mag":
		return
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var si: int = _eq_si(int((e as Dictionary).get("star", 1)))
		# ── 批④(2026-08-06) 统一路由 ──────────────────────────────────────
		#    ★这里原来是 085「铜齿护符·受法伤掷骰回龟能」与 086「极地反冲·减速+反弹」。
		#      两件都已被用户整条重做(085 → 压电陶瓷片: 受伤按【比例】转龟能、且 DoT 与
		#      护盾挡掉的都算; 086 → 六分仪浮游炮: 环绕炮群 + 终极射线) ⇒ 旧效果作废。
		#      085 的新效果吃【所有伤害】不只法术 ⇒ 它的收账点在 `_eq_on_target`, 不在这里。
		var _b4m = _b4(str((e as Dictionary).get("id", "")))
		if _b4m != null:
			_b4m.on_magic_hurt(u, src, float(dmg), str((e as Dictionary).get("id", "")), si)




## ★【已作废】这里原是 086「极地反冲装置」的两个常量(`RECOIL_ICD := 4.0` / `RECOIL_SLOW_MULT := 0.7`)
##   与它的效果说明。086 已被用户整条重做成【六分仪浮游炮】(环绕炮群 + 终极射线, 效果本体在
##   eq_gadget_batch.gd) —— 见本文件上方 `_eq_on_magic_hurt` 里那段 2026-08-06 批④ 记录。
##   两个常量全仓零引用, 且描述的是一个不存在的效果 ⇒ 一并删除, 不留"看着还在用"的假线索。


## ★★2026-08-06 批④: 上面这一批位置原有【18 个旧效果函数】(_double_barrel_shot / _eq_derringer_volley+_derringer_shot / _eq_armory_burst+_armory_shot /
##   _eq_breacher_cannon / _eq_wicker_shield / _eq_abyss_mint / _eq_tide_scepter /
##   _eq_eclipse_talisman / _eq_tide_codex / _eq_ancient_scute / _eq_awaken_core /
##   _eq_tide_rapier / _eq_clam_mitigate / _eq_fang_refresh / _eq_brass_ward / _eq_polar_recoil)。
##   它们是 077~094 这十七件的【AI 编的旧效果】, 用户已逐件亲手重做 ⇒ **整批删除, 不是搬家**。
##   删而不是留空壳: 零调用者的死函数会被"断言函数存在"这类门禁保护住, 还会被 VFXPREVIEW
##   指过去当成有效目视验证(memory [[fb-verify-must-run-the-real-path]] 那次就栽在这个形状上)。
##   新效果本体在 eq_gun/blade/gadget/arcane/relic_batch.gd 与 incense_stone_system.gd。
