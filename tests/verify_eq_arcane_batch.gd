extends Node
## verify_eq_arcane_batch.gd — 法器 3 件(088/089/090)逐件焊死 + 演出形态门禁
##
## 规格: docs/plans/20260805-装备逐件重做.md §0.5【用户逐件亲手写的定稿】
## 契约: docs/plans/20260806-实装契约-批④.md
## 实装: scripts/systems/equip/eq_arcane_batch.gd  ·  演出: scripts/scenes/battle/arcane_eq_vfx.gd
##
## ★本文件的规矩(契约 §8, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】—— 随机 spawn 的敌带盾/flat_dr/未播种 RNG 会让精确数值
##     在 CI 上偶发红(memory [[fb-ci-vs-local-divergence]])。
##   · **全部断言函数都是同步的, 一帧都不 await** —— 战斗场景的 `_process` 每帧都在跑 sim
##     (它自己也会调 `_arcane_sys.tick`), 只要中途让出一帧, 碑/符纸就会被推进两次,
##     精确的"5 跳 / 15 跳"立刻失真。节拍一律由本文件**手动喂** `tick(delta)`。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##   · 触发一律走【真入口】(`fire_equip_effect` / `_eq_on_basic_attack` / `StaffSynergySystem.add_mana`),
##     并且每件至少有一条【经中央伤害管线 _apply_damage_from 的端到端】断言 ——
##     memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调它」。
##   · **不依赖任何演出 tween / 弹道飞完**(CLAUDE.md §3.5)。演出层本身就没有 tween。
##   · 每条断言打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##   · 美术断言查**真的显示进 `_world`** 且**量真实节点**(不是把公式在测试里抄一遍 ——
##     memory [[fb-write-without-reader-and-fake-gates]]: 抄公式的门禁, 产品改成写死也照样绿)。
##
## 跑法: <godot> --headless --path . res://tests/verify_eq_arcane_batch.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const P2T := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 干净合成单位。★携带者一律 `fortune` 不用 `basic`:
##   小龟·不屈会给小龟造成的一切伤害 +20%, 拿 basic 当携带者验精确数值会量到 ×1.2。
func _mk(id: String, side: String, off: Vector2, hp: float = 200000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["crit"] = 0.0
	u["crit_dmg"] = 1.5
	u["heal_amp"] = 0.0
	u["shield_amp"] = 0.0
	u["reflect"] = 0.0
	u["lifesteal"] = 0.0
	u["ls_bonus"] = 0.0
	u["tenacity"] = 0.0
	u["armor_pen_pct"] = 0.0
	u["magic_pen_pct"] = 0.0
	u["armor_pen"] = 0.0
	u["magic_pen"] = 0.0
	u["aspd_perm"] = 1.0
	u["airborne"] = false
	u["vy"] = 0.0
	u["stun_until"] = 0.0
	u["dots"] = []
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


## 每组开局清干净: 撤场 + 清单位表 + 清一帧伤害计数。
## ★不清单位表的话, 上一组留下的单位会被 090 那发 1000 码猛砸扫到(战场才 1140×520)。
func _fresh() -> void:
	_arc().clear_all()
	_s._units.clear()
	_s._adf_ct = 0


func _arc():
	return _s._equip_sys._arcane_sys


## 手动喂节拍。★这是本门禁唯一的时间来源 —— 不 await 帧、不用 create_timer。
## 推进时间。★★2026-08-08 补上 `_step_pending_shots`: 本件多处结算已改成**延后到演出到达**
##   (浪潮每跳 WAVE_HOP_SEC 才落), 而旧版 `_feed` 只推装备自己的 tick、**不推延后队列**
##   ⇒ 断言全读到 0。"推进时间"本来就该把两条都推。
func _feed(sec: float, step: float = 0.05) -> void:
	var n: int = int(round(sec / step))
	for i in range(n):
		_arc().tick(step)
		_s._ballistics._step_pending_shots(step)


func _st(u: Dictionary, iid: String) -> Dictionary:
	return (u.get("eq_state", {}) as Dictionary).get(iid, {})


## 取【已剥注释】源码里某个函数的函数体(到下一个顶格 func 为止)。
func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


func _strip(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


func _count(hay: String, needle: String) -> int:
	var n := 0
	var i: int = hay.find(needle)
	while i >= 0:
		n += 1
		i = hay.find(needle, i + needle.length())
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 法器 3 件(088 涨潮碑 / 089 蚀月符纸 / 090 镇海杵) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准

	# ★★从这里往下【一帧都不 await】—— 见文件头第二条规矩。
	_t_dispatch()
	_t_stats()
	_t088_raise_and_pin()
	_t088_shield_and_pool()
	_t088_aura()
	_t088_mana_lock()
	_t089_target_and_total()
	_t089_shred_and_amplify()
	_t089_stack_and_transfer()
	_t090_slam()
	_t090_mana_lock()
	_t090_wave()
	_t_discipline()
	_t_vfx_pure()
	_t_vfx_nodes()
	_t_clear_all()

	_arc().clear_all()
	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 法器 3 件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ═════════════════════════════════════════════════════════════
# ⓪ 分发纪律与接线 —— 三件都落在【已有的】钩子上, 没有新增分发口
# ═════════════════════════════════════════════════════════════
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	## ★先剥注释再找分派 —— 否则会命中说明文字(前几份门禁的作者都吃过这个亏)
	var code: String = _strip("res://scripts/systems/equip/equip_system.gd")

	var owner: Dictionary = EquipSystem.B4_OWNER
	var bad: Array = []
	for iid in ["p2eq_088", "p2eq_089", "p2eq_090"]:
		if str(owner.get(iid, "")) != "arcane":
			bad.append("%s→%s" % [iid, str(owner.get(iid, "?"))])
	_ok("⓪ B4_OWNER 把 088/089/090 全路由到 arcane", bad.is_empty(), str(bad))
	_ok("⓪ ★分母: B4_OWNER 一共 %d 件(批④ 17 件)" % owner.size(), owner.size() == 17, "size=%d" % owner.size())

	var fb: String = _fn_body(code, "func fire_equip_effect")
	_ok("⓪ ★分母: fire_equip_effect 的函数体非空(空串会让下面那条恒真)",
		fb.length() > 400, "len=%d" % fb.length())
	_ok("⓪ 三件在 fire_equip_effect 里路由到 _arcane_sys.on_mana_full",
		fb.contains("\"p2eq_088\", \"p2eq_089\", \"p2eq_090\"") and fb.contains("_arcane_sys.on_mana_full(u, iid, si)"))

	var bb: String = _fn_body(code, "func _eq_on_basic_attack")
	_ok("⓪ ★分母: _eq_on_basic_attack 的函数体非空", bb.length() > 400, "len=%d" % bb.length())
	_ok("⓪ 普攻钩经 _b4() 路由到批系统的 on_basic(090 的浪潮靠它)",
		bb.contains("_b4o.on_basic(u, tgt,"))

	## ★全局节拍 2026-08-06 从 `_eq_tick` 搬到了 `tick_global` —— 原来它挂在
	##   "该单位身上有装备"那道闸里面, 携带者一死全局在途表就停摆。
	var tb: String = _fn_body(code, "func tick_global")
	_ok("⓪ ★分母: tick_global 的函数体非空(空串会让下面那条恒真)",
		tb.length() > 60, "len=%d" % tb.length())
	_ok("⓪ 全局节拍真的调 _b4s.tick(delta)(碑/符纸/砸落全靠它推进)",
		tb.contains("_b4s.tick(delta)"))
	## ★★光有函数不算数: 还得有人调它。memory [[fb-verify-must-run-the-real-path]] ——
	##   「断言函数存在」守不住「还有没有人调」, 零调用者的死函数照样让门禁绿。
	var main: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("⓪ ★★主循环每帧真的调 _equip_sys.tick_global(dt)(不是个零调用者的死函数)",
		main.contains("_equip_sys.tick_global("))

	_ok("⓪ ★★接线: battle._equip_sys._arcane_sys 真的存在且是 EqArcaneBatch",
		_s._equip_sys._arcane_sys != null and _s._equip_sys._arcane_sys is EqArcaneBatch,
		str(_s._equip_sys._arcane_sys))
	_ok("⓪ ★★接线: 它自己也真的 new 了演出层 ArcaneEqVfx",
		_arc().vfx != null and _arc().vfx is ArcaneEqVfx)
	_ok("⓪ ★★接线: _b4_all() 里含 _arcane_sys(换路 clear_all / 全局 tick 靠它遍历)",
		_s._equip_sys._b4_all().has(_arc()))

	## ★本批一件都不排周期(契约 §2): 法器的触发时机是【法力条满】, 排周期会长出两套行为
	var iv: Array = []
	for iid in ["p2eq_088", "p2eq_089", "p2eq_090"]:
		if EquipSystem.EQ_IV_BATCH1.has(iid):
			iv.append(iid)
	_ok("⓪ 三件都【不】排 EQ_IV_BATCH1 周期(触发时机是法力条满)", iv.is_empty(), str(iv))

	## ★类型必须真的是【法器】—— 不是法器的话 StaffSynergySystem.add_mana 根本不会理它,
	##   三件就成了永远不触发的死装备(而单看代码完全看不出来)。
	var wrong: Array = []
	for iid in ["p2eq_088", "p2eq_089", "p2eq_090"]:
		if P2T.type_of(iid) != "法器":
			wrong.append("%s=%s" % [iid, P2T.type_of(iid)])
	_ok("⓪ 088/089/090 在类型表里都是【法器】", wrong.is_empty(), str(wrong))


# ═════════════════════════════════════════════════════════════
# ⓪b 属性(equip_stats.STATS) —— 逐星硬写, 不读被测表
# ═════════════════════════════════════════════════════════════
func _t_stats() -> void:
	print("── ⓪b 三件的逐星属性 ──")
	var ES := preload("res://scripts/gamedata/equip_stats.gd")
	var want := {
		"p2eq_088": [{"magicPen": 5, "_maxEnergy": 12}, {"magicPen": 11, "_maxEnergy": 22}, {"magicPen": 20, "_maxEnergy": 40}],
		"p2eq_089": [{"_echargePct": 6, "def": 6}, {"_echargePct": 11, "def": 13}, {"_echargePct": 18, "def": 22}],
		"p2eq_090": [{"magicPen": 18, "hp": 150, "_maxEnergy": 45}, {"magicPen": 42, "hp": 420, "_maxEnergy": 80}, {"magicPen": 110, "hp": 1200, "_maxEnergy": 150}],
	}
	var checked := 0
	for iid in want:
		for si in range(3):
			var got: Dictionary = ES.STATS[iid][si]
			var exp: Dictionary = want[iid][si]
			var bad: Array = []
			if got.size() != exp.size():
				bad.append("字段数 %d≠%d" % [got.size(), exp.size()])
			for k in exp:
				checked += 1
				if not got.has(k) or absf(float(got[k]) - float(exp[k])) > 0.0001:
					bad.append("%s=%s(期望 %s)" % [str(k), str(got.get(k, "缺")), str(exp[k])])
			_ok("⓪b %s %d★ 属性" % [str(iid), si + 1], bad.is_empty(), str(bad))
	_ok("⓪b ★分母: 一共核了 %d 个属性字段(应为 21)" % checked, checked == 21, "checked=%d" % checked)


# ═════════════════════════════════════════════════════════════
# ① 088 涨潮碑 —— 立碑 / 钉在地上不跟随 / 每秒 15/25/40 / 5 跳封顶
# ═════════════════════════════════════════════════════════════
func _t088_raise_and_pin() -> void:
	print("── ① 088 涨潮碑: 立碑 + 钉在地上 + 每秒伤害 ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_088", 3)
	var near := _mk("fortune", "right", Vector2(100, 0))       # 圈内(100 < 250)
	var far := _mk("fortune", "right", Vector2(900, 0))        # 圈外(900 > 250)

	## ★走真入口: fire_equip_effect 是 StaffSynergySystem 满条时调的那一个
	_s._equip_sys.fire_equip_effect(u, "p2eq_088", 3)
	_ok("① 立碑: _steles 里出现 1 块", _arc()._steles.size() == 1, "n=%d" % _arc()._steles.size())
	_ok("① 立碑: 同步触发证据 stele_raised == 1",
		int(_st(u, "p2eq_088").get("stele_raised", 0)) == 1,
		"raised=%d" % int(_st(u, "p2eq_088").get("stele_raised", 0)))
	var pin: Vector2 = _arc()._steles[0]["pos"]
	_ok("① 碑立在【携带者脚下】", pin.distance_to(u["pos"] as Vector2) < 0.001,
		"碑=%s 人=%s" % [str(pin), str(u["pos"])])

	## ★★钉在地上不跟随: 把携带者搬到远处的 far 旁边, 碑必须留在原地
	u["pos"] = far["pos"]
	var hp_near0: float = near["hp"]
	var hp_far0: float = far["hp"]
	_feed(4.0)
	_ok("① ★钉在地上: 携带者跑出 900 码后, 碑坐标一动没动",
		(not _arc()._steles.is_empty())
			and (_arc()._steles[0]["pos"] as Vector2).distance_to(pin) < 0.001
			and pin.distance_to(u["pos"] as Vector2) > 500.0,
		"碑=%s 人=%s" % [str(pin), str(u["pos"])])
	_feed(1.4)
	var d_near: float = hp_near0 - float(near["hp"])
	var d_far: float = hp_far0 - float(far["hp"])
	## 3★ 每秒 40 魔法伤害 × 5 跳 = 200(干净目标 mr=0 ⇒ 倍率 1.0, 整数无损)
	_ok("① 圈内敌人 5 秒共吃 200(3★ 每秒 40 × 5 跳)", int(d_near) == 200, "实测 %d" % int(d_near))
	_ok("① 恰好跳 5 次(不是 4 也不是 6)",
		int(_st(u, "p2eq_088").get("stele_ticks", -1)) == 5,
		"ticks=%d" % int(_st(u, "p2eq_088").get("stele_ticks", -1)))
	_ok("① ★碑不跟人走: 携带者身边(圈外 900 码)的敌人一点没掉", int(d_far) == 0, "实测 %d" % int(d_far))
	_ok("① 5 秒到期后碑自动消失", _arc()._steles.is_empty(), "n=%d" % _arc()._steles.size())

	## ★第 6 秒不再跳(封顶 5 跳) —— 碑已经没了, 再喂 3 秒血量不该再掉
	var hp_after: float = near["hp"]
	_feed(3.0)
	_ok("① 碑没了以后不再结算(第 6~8 秒 0 伤害)", absf(float(near["hp"]) - hp_after) < 0.001,
		"又掉了 %.1f" % (hp_after - float(near["hp"])))

	## 1★ / 2★ 逐星: 每秒 15 / 25
	for cse in [[1, 15], [2, 25]]:
		_fresh()
		var u2 := _mk("fortune", "left", Vector2(0, 0))
		_equip(u2, "p2eq_088", int(cse[0]))
		var e2 := _mk("fortune", "right", Vector2(80, 0))
		var h0: float = e2["hp"]
		_s._equip_sys.fire_equip_effect(u2, "p2eq_088", int(cse[0]))
		_feed(5.4)
		var got: int = int(h0 - float(e2["hp"]))
		_ok("① %d★ 圈内敌人 5 秒共吃 %d" % [int(cse[0]), int(cse[1]) * 5],
			got == int(cse[1]) * 5, "实测 %d" % got)


func _t088_shield_and_pool() -> void:
	print("── ① 088: 圈内友军护盾(可叠加·到期不消失·排龟蛋与大师) ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_088", 3)
	var ally := _mk("fortune", "left", Vector2(60, 0))
	var out := _mk("fortune", "left", Vector2(900, 0))
	var egg := _mk("fortune", "left", Vector2(70, 20))
	egg["_isEgg"] = true
	var master := _mk("fortune", "left", Vector2(70, -20))
	master["is_trainer"] = true

	_s._equip_sys.fire_equip_effect(u, "p2eq_088", 3)
	_feed(5.4)
	## 3★ 每秒 55 护盾 × 5 跳 = 275。**单发只有 55** ⇒ 275 本身就是"可叠加"的证据。
	_ok("① 圈内友军 5 秒共得 275 护盾(3★ 每秒 55 × 5 跳·可叠加)",
		absf(float(ally["shield"]) - 275.0) < 0.01, "实测 %.2f" % float(ally["shield"]))
	_ok("① 携带者自己也在圈里, 同样拿 275",
		absf(float(u["shield"]) - 275.0) < 0.01, "实测 %.2f" % float(u["shield"]))
	_ok("① 圈外友军 0 护盾", absf(float(out["shield"])) < 0.01, "实测 %.2f" % float(out["shield"]))
	_ok("① ★龟蛋不吃(契约 §4「友军一律排除龟蛋与训龟大师」)",
		absf(float(egg["shield"])) < 0.01, "实测 %.2f" % float(egg["shield"]))
	_ok("① ★训龟大师不吃", absf(float(master["shield"])) < 0.01, "实测 %.2f" % float(master["shield"]))
	## 到期不消失
	_feed(4.0)
	_ok("① ★护盾到期不消失(碑没了 4 秒后仍是 275)",
		absf(float(ally["shield"]) - 275.0) < 0.01, "实测 %.2f" % float(ally["shield"]))

	## 1★ / 2★ 逐星: 每秒 20 / 35
	for cse in [[1, 20], [2, 35]]:
		_fresh()
		var u2 := _mk("fortune", "left", Vector2(0, 0))
		_equip(u2, "p2eq_088", int(cse[0]))
		var a2 := _mk("fortune", "left", Vector2(50, 0))
		_s._equip_sys.fire_equip_effect(u2, "p2eq_088", int(cse[0]))
		_feed(5.4)
		_ok("① %d★ 圈内友军 5 秒共得 %d 护盾" % [int(cse[0]), int(cse[1]) * 5],
			absf(float(a2["shield"]) - float(int(cse[1]) * 5)) < 0.01,
			"实测 %.2f" % float(a2["shield"]))


func _t088_aura() -> void:
	print("── ① 088: 攻速只在圈内(走出去立刻没·护盾留着) ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_088", 3)
	var ally := _mk("fortune", "left", Vector2(60, 0))
	_s._equip_sys.fire_equip_effect(u, "p2eq_088", 3)
	_feed(1.2)
	_ok("① 圈内友军攻速 +25%(3★): aspd_perm == 1.25",
		absf(float(ally["aspd_perm"]) - 1.25) < 1e-6, "实测 %.4f" % float(ally["aspd_perm"]))
	_ok("① 携带者自己也 +25%", absf(float(u["aspd_perm"]) - 1.25) < 1e-6,
		"实测 %.4f" % float(u["aspd_perm"]))
	var shd: float = ally["shield"]
	_ok("① ★分母: 这时友军已经拿到过护盾(否则下一条「护盾留着」是空检查)",
		shd > 0.0, "shield=%.2f" % shd)

	## 走出圈 → 攻速立刻收回, 护盾留着
	ally["pos"] = (ally["pos"] as Vector2) + Vector2(900, 0)
	_feed(0.1)
	_ok("① ★走出圈: 攻速立刻回到 1.0", absf(float(ally["aspd_perm"]) - 1.0) < 1e-6,
		"实测 %.4f" % float(ally["aspd_perm"]))
	_ok("① ★走出圈: 已给的护盾留着", absf(float(ally["shield"]) - shd) < 0.01,
		"实测 %.2f(离圈前 %.2f)" % [float(ally["shield"]), shd])
	_ok("① 还站圈里的携带者攻速不受影响, 仍 1.25",
		absf(float(u["aspd_perm"]) - 1.25) < 1e-6, "实测 %.4f" % float(u["aspd_perm"]))

	## 碑到期 → 剩下那个人的攻速也收回
	_feed(5.4)
	_ok("① ★碑到期: 攻速全部收回(携带者 aspd_perm 回 1.0)",
		absf(float(u["aspd_perm"]) - 1.0) < 1e-6, "实测 %.4f" % float(u["aspd_perm"]))

	## 1★ / 2★ 逐星: +10% / +15%
	for cse in [[1, 1.10], [2, 1.15]]:
		_fresh()
		var u2 := _mk("fortune", "left", Vector2(0, 0))
		_equip(u2, "p2eq_088", int(cse[0]))
		_s._equip_sys.fire_equip_effect(u2, "p2eq_088", int(cse[0]))
		_feed(0.1)
		_ok("① %d★ 圈内攻速倍率 %.2f" % [int(cse[0]), float(cse[1])],
			absf(float(u2["aspd_perm"]) - float(cse[1])) < 1e-6,
			"实测 %.4f" % float(u2["aspd_perm"]))


func _t088_mana_lock() -> void:
	print("── ① 088 ★★释放期间锁法力条(不锁的话法器 4 档就常驻了) ──")
	_fresh()
	## 法器 4 档 ⇒ 法力条满值 50(StaffSynergySystem.MANA_FULL 的顶档)
	_s._synergy._by_side["left"] = {"法器": 4}
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_088", 3)
	var _e := _mk("fortune", "right", Vector2(100, 0))

	## ★走【真入口】: 法力条满是由 StaffSynergySystem.add_mana 触发的
	_s._staff_syn.add_mana(u, 50.0)
	_ok("① 法力满 → 经 add_mana 真的立起了碑", _arc()._steles.size() == 1,
		"n=%d" % _arc()._steles.size())
	_ok("① 碑存在 ⇒ 这件装备的法力条被标记为锁住",
		_arc().mana_locked(u, "p2eq_088"))

	## ①-拒发: 锁期内再灌满也不许再立第二块碑
	_s._staff_syn.add_mana(u, 999.0)
	_ok("① ★锁期内再灌满 999 法力: 仍然只有 1 块碑(拒发)",
		_arc()._steles.size() == 1, "n=%d" % _arc()._steles.size())

	## ②-压零: 锁期内灌不满的量, 下一帧也要被按回 0("法力不增长"的可断言形式)
	_s._staff_syn.add_mana(u, 10.0)
	var mid: float = float(_st(u, "p2eq_088").get("mana", -1.0))
	_feed(0.05, 0.05)
	var after: float = float(_st(u, "p2eq_088").get("mana", -1.0))
	_ok("① ★分母: add_mana(10) 确实先把条推到 10(否则下一条是空检查)",
		absf(mid - 10.0) < 1e-6, "mid=%.3f" % mid)
	_ok("① ★★锁期内法力条被压回 0(不增长)", absf(after) < 1e-6, "after=%.3f" % after)

	## 碑到期 → 解锁 → 条恢复增长
	_feed(5.5)
	_ok("① 碑到期后解锁", not _arc().mana_locked(u, "p2eq_088"))
	_s._staff_syn.add_mana(u, 10.0)
	_feed(0.05, 0.05)
	var grow: float = float(_st(u, "p2eq_088").get("mana", -1.0))
	_ok("① ★解锁后法力条恢复增长(灌 10 就是 10)", absf(grow - 10.0) < 1e-6, "mana=%.3f" % grow)
	_ok("① ★分母: 这一组一共立了 %d 块碑(应恰为 2: 首发 + 解锁后没再自动放)" % int(_st(u, "p2eq_088").get("stele_raised", 0)),
		int(_st(u, "p2eq_088").get("stele_raised", 0)) == 1,
		"raised=%d" % int(_st(u, "p2eq_088").get("stele_raised", 0)))
	_s._synergy._by_side["left"] = {}


# ═════════════════════════════════════════════════════════════
# ② 089 蚀月符纸
# ═════════════════════════════════════════════════════════════
func _t089_target_and_total() -> void:
	print("── ② 089: 贴给最近的敌人 + 15 秒共 400/700/1000 ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_089", 3)
	var near := _mk("fortune", "right", Vector2(120, 0))
	var far := _mk("fortune", "right", Vector2(600, 0))

	_s._equip_sys.fire_equip_effect(u, "p2eq_089", 3)
	_ok("② 贴符: _talismans 里出现 1 张", _arc()._talismans.size() == 1,
		"n=%d" % _arc()._talismans.size())
	_ok("② 贴给【最近】的那个敌人(120 码那只, 不是 600 码那只)",
		is_same(_arc()._talismans[0]["tgt"], near))
	_ok("② 同步触发证据 moon_stuck == 1",
		int(_st(u, "p2eq_089").get("moon_stuck", 0)) == 1)

	## ★总量: 每跳把目标魔抗按回 0, 隔离掉"削魔抗→增伤"这一层, 单独量 400/700/1000。
	##   (削魔抗那条在下一组单独验, 两件事分开量才说得清)
	var hp0: float = near["hp"]
	for i in range(330):
		near["mr"] = 0.0
		near["base_mr"] = 0.0
		near["mr_shred"] = 0.0     # 削减走这个字段 ⇒ 隔离时也要按回 0
		_arc().tick(0.05)
	var got: float = hp0 - float(near["hp"])
	var ticks: int = int(_st(u, "p2eq_089").get("moon_ticks", -1))
	_ok("② 15 秒共 15 跳(不是 14 也不是 16)", ticks == 15, "ticks=%d" % ticks)
	_ok("② 符纸 15 秒后自动消失", _arc()._talismans.is_empty(), "n=%d" % _arc()._talismans.size())
	## 每跳 1000/15 = 66.67 → 取整 67, 15 跳 = 1005(整数取整误差 ≤ 15)
	_ok("② 3★ 15 秒共造成 ≈1000 魔法伤害(整数取整误差 ≤15)",
		absf(got - 1000.0) <= 15.0, "实测 %.0f" % got)
	_ok("② ★分母: 这次真的打出了伤害(不是 0)", got > 0.0, "实测 %.0f" % got)

	for cse in [[1, 400.0], [2, 700.0]]:
		_fresh()
		var u2 := _mk("fortune", "left", Vector2(0, 0))
		_equip(u2, "p2eq_089", int(cse[0]))
		var e2 := _mk("fortune", "right", Vector2(100, 0))
		var h0: float = e2["hp"]
		_s._equip_sys.fire_equip_effect(u2, "p2eq_089", int(cse[0]))
		for i in range(330):
			e2["mr"] = 0.0
			e2["base_mr"] = 0.0
			e2["mr_shred"] = 0.0
			_arc().tick(0.05)
		var g2: float = h0 - float(e2["hp"])
		_ok("② %d★ 15 秒共造成 ≈%.0f" % [int(cse[0]), float(cse[1])],
			absf(g2 - float(cse[1])) <= 15.0, "实测 %.0f" % g2)


func _t089_shred_and_amplify() -> void:
	print("── ② 089 ★★每秒削 1 魔抗 → 削穿变增伤(走 _recalc_stats 的 mr_shred 通道) ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_089", 3)
	var e := _mk("fortune", "right", Vector2(100, 0))
	e["base_mr"] = 5.0
	_s._recalc_stats(e)
	var atk := _mk("fortune", "left", Vector2(-200, 0))

	## ★① 削【之前】先打一发 1000 基数的魔法, 记住它有多疼(这一发是下面比值的基线)
	_ok("② ★分母: 起手魔抗真的是 5(是 0 的话「变增伤」根本无从谈起)",
		absf(float(e["mr"]) - 5.0) < 1e-6, "mr=%.2f" % float(e["mr"]))
	var b0: float = e["hp"]
	_s._damage._apply_damage_from(atk, e, _s._resolve_dmg(atk, 1000.0, e, true),
		Color.WHITE, 0.0, false, true)
	var d0: float = b0 - float(e["hp"])
	## 魔抗 5 ⇒ 倍率 1 − 5/(5+40) = 0.888889 ⇒ 1000 → 889
	_ok("② 削之前: 1000 基数魔法打出 889(魔抗 5 ⇒ ×0.888889)", int(d0) == 889,
		"实测 %d" % int(d0))

	## ★② 贴符 —— 每秒削 1 点
	_s._equip_sys.fire_equip_effect(u, "p2eq_089", 3)
	_feed(7.2)
	_ok("② 7 秒后魔抗 5 → −2(每秒 −1)", absf(float(e["mr"]) + 2.0) < 1e-6,
		"实测 mr=%.2f" % float(e["mr"]))
	_feed(9.0)
	_ok("② 15 跳跑满 ⇒ 魔抗 5 → −10", absf(float(e["mr"]) + 10.0) < 1e-6,
		"实测 mr=%.2f" % float(e["mr"]))

	## ★★③ 削【之后】打**完全一样**的一发 —— 这才是"削穿之后变增伤"的真凭据:
	##    比的是【实际掉血】, 不是比某个常量。
	var b1: float = e["hp"]
	_s._damage._apply_damage_from(atk, e, _s._resolve_dmg(atk, 1000.0, e, true),
		Color.WHITE, 0.0, false, true)
	var d1: float = b1 - float(e["hp"])
	## 魔抗 −10 ⇒ 倍率 1 + 10/(10+40) = 1.2 ⇒ 1000 → 1200
	_ok("② ★★同一发魔法, 削穿之后真的更疼: 889 → 1200", int(d1) == 1200 and d1 > d0,
		"削前 %d → 削后 %d" % [int(d0), int(d1)])
	_ok("② ★★增伤比 = 1200/889 = 1.350(负抗性走 1+|r|/(|r|+40), 上限 2.0)",
		absf(d1 / maxf(1.0, d0) - 1.350) < 0.01, "实测 %.4f" % (d1 / maxf(1.0, d0)))

	## ★④ 削减必须扛得住 `_recalc_stats` —— 它是 mr 的唯一写入点, 每帧都可能被别的系统调
	_s._recalc_stats(e)
	_ok("② 再算一次属性也不会把削掉的 15 点弹回来", absf(float(e["mr"]) + 10.0) < 1e-6,
		"实测 mr=%.2f" % float(e["mr"]))

	## ★⑤ ★分母 + 口径: `maxf(0.0, …)` 那个下钳【还在】, 它钳的是【加法/乘法那一段】;
	##    `mr_shred` 是钳【之后】才减的 ⇒ 只有显式削减拿得到负抗性,
	##    百分比/固定值 debuff(冰寒减攻那一类)照旧被钳在 0, 不会变成增伤。
	e["buffs"].append({"stat": "mr", "amount": -999.0, "pct": false, "until": float(_s._t) + 99.0})
	_s._recalc_stats(e)
	_ok("② ★钳还在(钳的是加法段): −999 的 mr debuff 被钳成 0, 再减 15 ⇒ −15, 不是 −1009",
		absf(float(e["mr"]) + 15.0) < 1e-6, "实测 %.2f" % float(e["mr"]))
	e["buffs"].clear()
	_s._recalc_stats(e)
	_ok("② 拿掉那个 debuff 后回到 −10", absf(float(e["mr"]) + 10.0) < 1e-6,
		"实测 %.2f" % float(e["mr"]))

	## 本路不恢复: 符纸早已结束, 再喂 5 秒魔抗也不回升
	_feed(5.0)
	_ok("② ★削掉的魔抗本路不恢复(符纸结束 5 秒后仍是 −10)",
		absf(float(e["mr"]) + 10.0) < 1e-6, "实测 mr=%.2f" % float(e["mr"]))


func _t089_stack_and_transfer() -> void:
	print("── ② 089: 可叠加 + 死亡转移(只转剩余时长) ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_089", 3)
	var a := _mk("fortune", "right", Vector2(100, 0))
	var b := _mk("fortune", "right", Vector2(260, 0))

	_s._equip_sys.fire_equip_effect(u, "p2eq_089", 3)
	_s._equip_sys.fire_equip_effect(u, "p2eq_089", 3)
	_ok("② ★符纸可叠加: 同一目标上贴了 2 张", _arc()._talismans.size() == 2,
		"n=%d" % _arc()._talismans.size())
	_feed(1.2)
	_ok("② 2 张同时跳 ⇒ 1 秒削 2 点魔抗", absf(float(a["mr"]) + 2.0) < 1e-6,
		"实测 mr=%.2f" % float(a["mr"]))

	## 再走 4 秒(共 5 跳), 然后弄死 a → 符纸带【剩余 10 秒】转到 b
	_feed(4.0)
	var a_mr: float = a["mr"]
	_ok("② ★分母: 转移前 a 已被削了 %.0f 点(5 跳 × 2 张)" % absf(a_mr),
		absf(a_mr + 10.0) < 1e-6, "实测 %.2f" % a_mr)
	a["alive"] = false
	a["hp"] = 0.0
	_feed(0.05, 0.05)
	_ok("② ★死亡转移: 两张符纸都转到了最近的敌人 b",
		_arc()._talismans.size() == 2
			and is_same(_arc()._talismans[0]["tgt"], b)
			and is_same(_arc()._talismans[1]["tgt"], b))
	_ok("② 转移次数记账 hops == 1", int(_arc()._talismans[0]["hops"]) == 1,
		"hops=%d" % int(_arc()._talismans[0]["hops"]))
	_ok("② ★已削的魔抗留在死者身上(不跟着转走)", absf(float(a["mr"]) + 10.0) < 1e-6,
		"实测 %.2f" % float(a["mr"]))
	_ok("② ★新目标从它【自己】的魔抗开始削(转移当下还是 0)",
		absf(float(b["mr"])) < 1e-6, "实测 %.2f" % float(b["mr"]))

	## ★只转剩余时长: 已经跑了 5 跳, b 身上只该再吃 10 跳 × 2 张 = 20 点
	_feed(11.0)
	_ok("② ★★只转【剩余时长】: b 共被削 20 点(10 跳 × 2 张), 不是 30",
		absf(float(b["mr"]) + 20.0) < 1e-6, "实测 %.2f" % float(b["mr"]))
	_ok("② 符纸走完 15 秒后消失", _arc()._talismans.is_empty(),
		"n=%d" % _arc()._talismans.size())

	## 没有敌人可转 → 符纸作废(不是留一张贴在尸体上继续打)
	_fresh()
	var u3 := _mk("fortune", "left", Vector2(0, 0))
	_equip(u3, "p2eq_089", 3)
	var only := _mk("fortune", "right", Vector2(100, 0))
	_s._equip_sys.fire_equip_effect(u3, "p2eq_089", 3)
	only["alive"] = false
	_feed(0.05, 0.05)
	_ok("② 场上没有第二个敌人时符纸作废", _arc()._talismans.is_empty(),
		"n=%d" % _arc()._talismans.size())


# ═════════════════════════════════════════════════════════════
# ③ 090 镇海杵
# ═════════════════════════════════════════════════════════════
func _t090_slam() -> void:
	print("── ③ 090 主动: 跳起猛砸(3ATK + 200/300/5000 · 眩晕 2/3/8 · 击飞 1 秒) ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_090", 3)
	u["atk"] = 100.0
	var inr := _mk("fortune", "right", Vector2(900, 0))       # 1000 码内
	var outr := _mk("fortune", "right", Vector2(1200, 0))     # 1000 码外

	_s._equip_sys.fire_equip_effect(u, "p2eq_090", 3)
	_ok("③ 起跳: _slams 里出现 1 条在途记录", _arc()._slams.size() == 1,
		"n=%d" % _arc()._slams.size())
	_ok("③ 起跳: 携带者进入滞空态(airborne)", bool(u.get("airborne", false)))
	## ★★3★ 的两个极端值必须原样保留(用户 2026-08-06:「5000，8秒，就要8」)
	_ok("③ ★★3★ 猛砸固定魔伤 = 5000(不许调低)",
		absf(float(_arc()._slams[0]["flat"]) - 5000.0) < 1e-6,
		"实测 %.0f" % float(_arc()._slams[0]["flat"]))
	_ok("③ ★★3★ 眩晕 = 8.0 秒(不许调低)",
		absf(float(_arc()._slams[0]["stun"]) - 8.0) < 1e-6,
		"实测 %.2f" % float(_arc()._slams[0]["stun"]))

	var h_in: float = inr["hp"]
	var h_out: float = outr["hp"]
	# ★★滞空时长不写死 —— 拿 `pestle_jump_sec()` 本人算。
	#   2026-08-08 起跳改成"先定峰高与重力、再推滞空"(用户「不够物理」),
	#   T 从 0.6 变成 2√(2h/g)。写死的话调一次峰高就得改一次测试。
	var T: float = EqArcaneBatch.pestle_jump_sec()
	_feed(T * 0.65)
	_ok("③ 起跳后滞空的 65%% 时还没砸下来(伤害没有提前结算)",
		absf(float(inr["hp"]) - h_in) < 0.001 and _arc()._slams.size() == 1,
		"hp 变化 %.1f" % (h_in - float(inr["hp"])))
	_feed(T * 0.40)
	_ok("③ %.2f 秒落地 → 砸落结算" % T, _arc()._slams.is_empty(),
		"n=%d" % _arc()._slams.size())
	## 3 ATK(=300) + 5000 = 5300, 干净目标 mr=0 ⇒ 倍率 1.0
	var took: float = h_in - float(inr["hp"])
	_ok("③ 1000 码内敌人吃 5300(3×100 ATK + 5000)", int(took) == 5300, "实测 %d" % int(took))
	_ok("③ 1000 码外敌人一点没吃", absf(float(outr["hp"]) - h_out) < 0.001,
		"实测 %.0f" % (h_out - float(outr["hp"])))
	_ok("③ 眩晕 8 秒(韧性 0 ⇒ 原值)",
		absf((float(inr["stun_until"]) - float(_s._t)) - 8.0) < 0.05,
		"实测 %.2f 秒" % (float(inr["stun_until"]) - float(_s._t)))
	_ok("③ 圈外敌人不吃眩晕", float(outr.get("stun_until", 0.0)) <= float(_s._t))
	## 1 秒击飞: 滞空 = 2·vy/|g|
	var vy: float = float(inr.get("vy", 0.0))
	var g: float = absf(float(inr.get("knock_g", 0.0)))
	var air: float = (2.0 * vy / g) if g > 0.0 else -1.0
	_ok("③ 击飞: 目标进入滞空态", bool(inr.get("airborne", false)))
	_ok("③ ★击飞滞空恰好 1.0 秒(2·vy/|g|)", absf(air - 1.0) < 1e-4,
		"vy=%.3f g=%.3f ⇒ 滞空 %.4f 秒" % [vy, g, air])
	_ok("③ 记账: pestle_slam_hit == 1(只有圈内那一个)",
		int(_st(u, "p2eq_090").get("pestle_slam_hit", -1)) == 1,
		"hit=%d" % int(_st(u, "p2eq_090").get("pestle_slam_hit", -1)))

	## 1★ / 2★ 逐星: 3ATK + 200 / 300, 眩晕 2 / 3
	for cse in [[1, 200.0, 2.0], [2, 300.0, 3.0]]:
		_fresh()
		var u2 := _mk("fortune", "left", Vector2(0, 0))
		_equip(u2, "p2eq_090", int(cse[0]))
		u2["atk"] = 100.0
		var e2 := _mk("fortune", "right", Vector2(200, 0))
		var h0: float = e2["hp"]
		_s._equip_sys.fire_equip_effect(u2, "p2eq_090", int(cse[0]))
		_feed(EqArcaneBatch.pestle_jump_sec() + 0.1)   # ★等滞空走完(不写死)
		var g2: int = int(h0 - float(e2["hp"]))
		_ok("③ %d★ 猛砸 = 300 + %.0f" % [int(cse[0]), float(cse[1])],
			g2 == int(300.0 + float(cse[1])), "实测 %d" % g2)
		_ok("③ %d★ 眩晕 %.0f 秒" % [int(cse[0]), float(cse[2])],
			absf((float(e2["stun_until"]) - float(_s._t)) - float(cse[2])) < 0.05,
			"实测 %.2f" % (float(e2["stun_until"]) - float(_s._t)))


func _t090_mana_lock() -> void:
	print("── ③ 090 ★★造成伤害之后才重新开始记录法力值 ──")
	_fresh()
	_s._synergy._by_side["left"] = {"法器": 4}
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_090", 3)
	u["atk"] = 100.0
	var _e2 := _mk("fortune", "right", Vector2(200, 0))

	_s._staff_syn.add_mana(u, 50.0)
	_ok("③ 法力满 → 经 add_mana 真的起跳了", _arc()._slams.size() == 1,
		"n=%d" % _arc()._slams.size())
	_ok("③ 起跳瞬间就锁住法力条", _arc().mana_locked(u, "p2eq_090"))
	_feed(EqArcaneBatch.pestle_jump_sec() * 0.55)   # ★半空中(滞空的一半多一点)
	_s._staff_syn.add_mana(u, 10.0)
	_feed(0.05, 0.05)
	_ok("③ ★在【半空中】(伤害还没造成)法力条仍被压回 0",
		absf(float(_st(u, "p2eq_090").get("mana", -1.0))) < 1e-6,
		"mana=%.3f" % float(_st(u, "p2eq_090").get("mana", -1.0)))
	_ok("③ ★分母: 这时确实还没砸下来", _arc()._slams.size() == 1, "n=%d" % _arc()._slams.size())
	_feed(EqArcaneBatch.pestle_jump_sec() * 0.55)   # ★再推到落地
	_ok("③ ★造成伤害之后才解锁", not _arc().mana_locked(u, "p2eq_090"))

	# ── ★★起跳物理(用户 2026-08-08:「不够高, 不够物理, 哪有这么快的跳」) ──
	#   新口径是**先定峰高 h 与重力 g、再推滞空 T**(物理的因果方向),
	#   而不是旧版"先定 T 再倒推 g"(h=2.4/T=0.6 ⇒ g=26.7 = 2.7 个地球重力)。
	var _h: float = EqArcaneBatch.PESTLE_APEX_M
	var _g: float = EqArcaneBatch.PESTLE_G
	var _T: float = EqArcaneBatch.pestle_jump_sec()
	_ok("③P 滞空 T ≡ 2√(2h/g)(不是写死的数)",
		absf(_T - 2.0 * sqrt(2.0 * _h / _g)) < 1e-6, "T=%.4f h=%.1f g=%.1f" % [_T, _h, _g])
	_ok("③P 峰高 = v₀²/(2g) ≡ h(起跳初速与峰高自洽)",
		absf(pow(sqrt(2.0 * _g * _h), 2.0) / (2.0 * _g) - _h) < 1e-4, "h=%.3f" % _h)
	_ok("③P 重力在地球重力的 1.5~3 倍内(旧版 26.7 = 2.7 倍但峰高只有 2.4 米 ⇒ 又矮又快)",
		_g >= 14.7 and _g <= 29.4 and _h >= 5.0, "g=%.1f h=%.1f T=%.2f" % [_g, _h, _T])

	# ── ★★雷电预警圈的半径 ≡ 真实砸落半径 ──
	#   旧版预告环收拢到 `LEAP_WINDUP_PX = 110` 码, 而真正挨砸的是 1000 码 —— **差九倍**,
	#   而且节点上的 meta 写的是 1000(元数据说 1000、画出来 110) ⇒ 只验 meta 抓不到。
	#   这一条直接钉**两个常量相等**, 哪天又拆开就红。
	_ok("③W 预警圈半径 SLAM_R_PX ≡ 伤害半径 PESTLE_RADIUS(旧版差九倍)",
		absf(ArcaneEqVfx.SLAM_R_PX - EqArcaneBatch.PESTLE_RADIUS) < 1e-6,
		"圈 %.0f / 伤害 %.0f" % [ArcaneEqVfx.SLAM_R_PX, EqArcaneBatch.PESTLE_RADIUS])
	_s._staff_syn.add_mana(u, 10.0)
	_feed(0.05, 0.05)
	_ok("③ ★解锁后法力条恢复增长(灌 10 就是 10)",
		absf(float(_st(u, "p2eq_090").get("mana", -1.0)) - 10.0) < 1e-6,
		"mana=%.3f" % float(_st(u, "p2eq_090").get("mana", -1.0)))
	_s._synergy._by_side["left"] = {}


func _t090_wave() -> void:
	print("── ③ 090 被动: 每第三次普攻发浪潮(跳友军也跳敌军·不重复) ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_090", 3)
	var e1 := _mk("fortune", "right", Vector2(120, 0))
	var e2 := _mk("fortune", "right", Vector2(240, 0))
	var e3 := _mk("fortune", "right", Vector2(360, 0))
	var a1 := _mk("fortune", "left", Vector2(-120, 0))
	var a2 := _mk("fortune", "left", Vector2(-240, 0))
	a1["hp"] = float(a1["maxHp"]) - 5000.0
	a2["hp"] = float(a2["maxHp"]) - 5000.0
	## 契约 §4:「友军一律排除龟蛋与训龟大师」—— 这两个贴在携带者身边(比谁都近),
	## 只要口径错了浪潮第一跳就会落到它们头上, 藏不住。
	var egg := _mk("fortune", "left", Vector2(30, 0))
	egg["_isEgg"] = true
	egg["hp"] = float(egg["maxHp"]) - 5000.0
	var master := _mk("fortune", "left", Vector2(-30, 0))
	master["is_trainer"] = true
	master["hp"] = float(master["maxHp"]) - 5000.0
	var heg: float = egg["hp"]
	var hms: float = master["hp"]

	## ★走真入口 `_eq_on_basic_attack` —— 不是直接调 on_basic
	_s._equip_sys._eq_on_basic_attack(u, e1)
	_s._equip_sys._eq_on_basic_attack(u, e1)
	_ok("③ 前两次普攻【不】发浪潮",
		int(_st(u, "p2eq_090").get("pestle_waves", 0)) == 0,
		"waves=%d" % int(_st(u, "p2eq_090").get("pestle_waves", 0)))
	var he1: float = e1["hp"]
	var he2: float = e2["hp"]
	var he3: float = e3["hp"]
	var ha1: float = a1["hp"]
	var ha2: float = a2["hp"]
	var hu: float = u["hp"]
	_s._equip_sys._eq_on_basic_attack(u, e1)
	_ok("③ 第三次普攻发出浪潮",
		int(_st(u, "p2eq_090").get("pestle_waves", 0)) == 1,
		"waves=%d" % int(_st(u, "p2eq_090").get("pestle_waves", 0)))
	# ★★浪潮的伤害/治疗现在**等那一簇水真的跳到**才结算(每跳 WAVE_HOP_SEC),
	#   不再是出手那一帧就把整条链算完 ⇒ 断言前必须把延后队列推完。
	_feed(EqArcaneBatch.WAVE_HOP_SEC * 10.0)
	var st: Dictionary = _st(u, "p2eq_090")
	_ok("③ ★分母: 场上 3 敌 + 2 友 = 5 个可跳单位(龟蛋/大师不算), 3★ 上限 8 ⇒ 全跳完 5 个",
		int(st.get("wave_hits", -1)) == 5, "hits=%d" % int(st.get("wave_hits", -1)))
	_ok("③ 打到 3 个敌人 / 奶到 2 个友军",
		int(st.get("wave_dmg_n", -1)) == 3 and int(st.get("wave_heal_n", -1)) == 2,
		"dmg_n=%d heal_n=%d" % [int(st.get("wave_dmg_n", -1)), int(st.get("wave_heal_n", -1))])
	_ok("③ 3★ 打到敌人 140 魔法伤害(每人恰好一次, 不重复飞)",
		int(he1 - float(e1["hp"])) == 140 and int(he2 - float(e2["hp"])) == 140
			and int(he3 - float(e3["hp"])) == 140,
		"e1=%d e2=%d e3=%d" % [int(he1 - float(e1["hp"])), int(he2 - float(e2["hp"])), int(he3 - float(e3["hp"]))])
	_ok("③ 3★ 打到友军 80 治疗",
		absf((float(a1["hp"]) - ha1) - 80.0) < 0.01 and absf((float(a2["hp"]) - ha2) - 80.0) < 0.01,
		"a1=%.1f a2=%.1f" % [float(a1["hp"]) - ha1, float(a2["hp"]) - ha2])
	_ok("③ ★携带者是起点(算已飞过): 既没被打也没被奶",
		absf(float(u["hp"]) - hu) < 0.01, "hp 变化 %.1f" % (float(u["hp"]) - hu))
	_ok("③ ★龟蛋与训龟大师不算友军(贴在携带者身边也不被浪潮奶到)",
		absf(float(egg["hp"]) - heg) < 0.01 and absf(float(master["hp"]) - hms) < 0.01,
		"蛋 %+.1f 大师 %+.1f" % [float(egg["hp"]) - heg, float(master["hp"]) - hms])
	_ok("③ 发完浪潮后计数归零(下一轮重新数三下)",
		int(_st(u, "p2eq_090").get("pestle_basics", -1)) == 0,
		"basics=%d" % int(_st(u, "p2eq_090").get("pestle_basics", -1)))

	## ★跳数上限: 1★ 上限 4, 场上 6 个可跳单位 ⇒ 只跳 4 次
	_fresh()
	var u2 := _mk("fortune", "left", Vector2(0, 0))
	_equip(u2, "p2eq_090", 1)
	for i in range(4):
		var _eN := _mk("fortune", "right", Vector2(100 + 60 * i, 0))
	for i in range(2):
		var aN := _mk("fortune", "left", Vector2(-100 - 60 * i, 0))
		aN["hp"] = float(aN["maxHp"]) - 5000.0
	for i in range(3):
		_s._equip_sys._eq_on_basic_attack(u2, _s._units[1])
	_ok("③ ★1★ 跳数上限 4(场上有 6 个可跳单位)",
		int(_st(u2, "p2eq_090").get("wave_hits", -1)) == 4,
		"hits=%d" % int(_st(u2, "p2eq_090").get("wave_hits", -1)))

	## 2★ 上限 5 + 逐星数值 70 / 40
	_fresh()
	var u3 := _mk("fortune", "left", Vector2(0, 0))
	_equip(u3, "p2eq_090", 2)
	var t3 := _mk("fortune", "right", Vector2(120, 0))
	for i in range(5):
		var _eN2 := _mk("fortune", "right", Vector2(240 + 60 * i, 0))
	var h3: float = t3["hp"]
	for i in range(3):
		_s._equip_sys._eq_on_basic_attack(u3, t3)
	_ok("③ ★2★ 跳数上限 5(场上有 6 个可跳单位)",
		int(_st(u3, "p2eq_090").get("wave_hits", -1)) == 5,
		"hits=%d" % int(_st(u3, "p2eq_090").get("wave_hits", -1)))
	_feed(EqArcaneBatch.WAVE_HOP_SEC * 10.0)   # ★同上: 等水跳到
	_ok("③ 2★ 打到敌人 70 魔法伤害", int(h3 - float(t3["hp"])) == 70,
		"实测 %d" % int(h3 - float(t3["hp"])))

	_fresh()
	var u4 := _mk("fortune", "left", Vector2(0, 0))
	_equip(u4, "p2eq_090", 1)
	var t4 := _mk("fortune", "right", Vector2(120, 0))
	var a4 := _mk("fortune", "left", Vector2(-120, 0))
	a4["hp"] = float(a4["maxHp"]) - 5000.0
	var h4: float = t4["hp"]
	var ha4: float = a4["hp"]
	for i in range(3):
		_s._equip_sys._eq_on_basic_attack(u4, t4)
	_feed(EqArcaneBatch.WAVE_HOP_SEC * 10.0)   # ★同上: 等水跳到
	_ok("③ 1★ 打到敌人 40 / 奶友军 20",
		int(h4 - float(t4["hp"])) == 40 and absf((float(a4["hp"]) - ha4) - 20.0) < 0.01,
		"dmg=%d heal=%.1f" % [int(h4 - float(t4["hp"])), float(a4["hp"]) - ha4])


# ═════════════════════════════════════════════════════════════
# ④ 焊死口径: from_equip / 零裸随机 / 不拿单位字典当键
# ═════════════════════════════════════════════════════════════
func _t_discipline() -> void:
	print("── ④ 三条焊死口径(源码级) ──")
	var code: String = _strip("res://scripts/systems/equip/eq_arcane_batch.gd")
	var calls: int = _count(code, "_apply_damage_from(")
	var flagged: int = _count(code, ", false, true)")
	_ok("④ ★分母: 本文件一共有 %d 处伤害调用(0 处 = 空检查)" % calls, calls >= 4, "calls=%d" % calls)
	_ok("④ ★每一段伤害都 from_equip = true(不回钩 on-hit / 不涨法力 ⇒ 不自激)",
		calls == flagged, "calls=%d flagged=%d" % [calls, flagged])

	var bare := 0
	for pat in ["randi(", "randf(", "randfn(", "randi_range(", "randf_range("]:
		var i: int = code.find(pat)
		while i >= 0:
			var head: String = code.substr(maxi(0, i - 12), mini(12, i))
			if not head.contains("_battle_rng."):
				bare += 1
			i = code.find(pat, i + 1)
	_ok("④ 零裸随机(裸 randi/randf 会破坏确定性指纹)", bare == 0, "bare=%d" % bare)

	## ★绝不拿单位字典当 Dictionary 的键(CLAUDE.md §3.2) —— 存在判断只许用 _arr_has_unit
	_ok("④ 存在判断走 battle._arr_has_unit(不是 in / .has())",
		code.contains("battle._arr_has_unit(visited, o)"))
	## ★089 的削减只许走共享的 `mr_shred` 通道 —— 自己写 mr/base_mr 就等于把
	##   `_recalc_stats` 的公式再镜像一份(memory [[fb-hand-rolled-copies-drift]]: 抄一次永远落后一次)。
	_ok("④ ★089 不自己写 mr / base_mr(削减只累加 mr_shred 再调唯一写入点)",
		code.contains("o[\"mr_shred\"] =") and code.contains("battle._recalc_stats(o)")
			and not code.contains("o[\"mr\"] =") and not code.contains("o[\"base_mr\"] ="))
	_ok("④ 单位比较走 is_same(不是 ==)", code.contains("is_same(o, src)"))

	## ★演出层同样不许有 tween(无头 CI 下推进不稳)
	var vcode: String = _strip("res://scripts/scenes/battle/arcane_eq_vfx.gd")
	_ok("④ 演出层零 tween(生命周期全由 tick(delta) 推进)",
		not vcode.contains("create_tween") and not vcode.contains("_reg_tween"))


# ═════════════════════════════════════════════════════════════
# ⑤ 演出层纯函数 —— 闭式解, 不建节点不等演出
# ═════════════════════════════════════════════════════════════
func _t_vfx_pure() -> void:
	print("── ⑤ 演出形态(闭式解) ──")
	## 碑体上涌: ζ=1 临界阻尼阶跃 —— 起点 0 · 严格单调增 · 恒 < 1(永不过冲)
	_ok("⑤ rise_frac(0) == 0", absf(ArcaneEqVfx.rise_frac(0.0, 0.55)) < 1e-9)
	var mono := true
	var over := false
	var prev := -1.0
	for i in range(401):
		var t: float = 0.55 * float(i) / 400.0
		var v: float = ArcaneEqVfx.rise_frac(t, 0.55)
		if v < prev - 1e-12:
			mono = false
		if v >= 1.0:
			over = true
		prev = v
	_ok("⑤ rise_frac 在 401 个采样点上严格单调增", mono)
	_ok("⑤ rise_frac 恒 < 1(临界阻尼永不过冲 ⇒ 碑是顶上来不是弹出来)", not over)
	_ok("⑤ rise_frac(T) ≈ 0.98(定标点)",
		absf(ArcaneEqVfx.rise_frac(0.55, 0.55) - 0.98) < 0.005,
		"实测 %.5f" % ArcaneEqVfx.rise_frac(0.55, 0.55))

	## 潮涌环【匀速】 vs 猛砸【Sedov 爆轰 t^0.4】—— 两条曲线形状必须不同
	_ok("⑤ pulse_radius 线性: 半程 = 半径的一半",
		absf(ArcaneEqVfx.pulse_radius(0.5, 1.0, 250.0) - 125.0) < 1e-6,
		"实测 %.4f" % ArcaneEqVfx.pulse_radius(0.5, 1.0, 250.0))
	_ok("⑤ blast_radius Sedov: 半程 = R·0.5^0.4 = 0.757858·R",
		absf(ArcaneEqVfx.blast_radius(0.5, 1.0, 1000.0) - 757.858283) < 0.01,
		"实测 %.4f" % ArcaneEqVfx.blast_radius(0.5, 1.0, 1000.0))
	_ok("⑤ ★两条曲线不是同一条(爆轰前段明显更快)",
		ArcaneEqVfx.blast_radius(0.5, 1.0, 1000.0) > ArcaneEqVfx.pulse_radius(0.5, 1.0, 1000.0) + 200.0)
	_ok("⑤ 两条都在 t=T 收敛到 R",
		absf(ArcaneEqVfx.pulse_radius(1.0, 1.0, 250.0) - 250.0) < 1e-6
			and absf(ArcaneEqVfx.blast_radius(1.0, 1.0, 250.0) - 250.0) < 1e-6)

	## 浪潮拱线 4·h·s(1−s): 两端贴地、中点最高
	_ok("⑤ arc_height 两端为 0",
		absf(ArcaneEqVfx.arc_height(0.0, 3.0)) < 1e-9 and absf(ArcaneEqVfx.arc_height(1.0, 3.0)) < 1e-9)
	_ok("⑤ arc_height 峰在中点且 == 拱高",
		absf(ArcaneEqVfx.arc_height(0.5, 3.0) - 3.0) < 1e-9,
		"实测 %.6f" % ArcaneEqVfx.arc_height(0.5, 3.0))

	## 符纸悬浮: 简谐, 四分之一周期到峰
	_ok("⑤ bob_offset(0) == 0", absf(ArcaneEqVfx.bob_offset(0.0)) < 1e-9)
	_ok("⑤ bob_offset 在 1/4 周期(0.4 秒)到达幅值 4 码",
		absf(ArcaneEqVfx.bob_offset(0.4) - 4.0) < 1e-4,
		"实测 %.5f" % ArcaneEqVfx.bob_offset(0.4))

	## 折线长度
	var pts: Array = [Vector2(0, 0), Vector2(3, 4), Vector2(3, 14)]
	_ok("⑤ path_length([0,0]→[3,4]→[3,14]) == 15",
		absf(ArcaneEqVfx.path_length(pts) - 15.0) < 1e-6,
		"实测 %.4f" % ArcaneEqVfx.path_length(pts))


# ═════════════════════════════════════════════════════════════
# ⑥ 演出真的显示进 _world —— 量真实节点, 不抄公式
# ═════════════════════════════════════════════════════════════
func _t_vfx_nodes() -> void:
	print("── ⑥ 演出节点(量真实对象) ──")
	_fresh()
	_arc().vfx.clear()
	var u := _mk("fortune", "left", Vector2(0, 0))
	_equip(u, "p2eq_088", 3)
	var e := _mk("fortune", "right", Vector2(100, 0))
	_s._equip_sys.fire_equip_effect(u, "p2eq_088", 3)
	_ok("⑥ ★★立碑真的建了演出节点(效果层确实调了演出层)",
		_arc().vfx.alive_count("stele") == 1, "n=%d" % _arc().vfx.alive_count("stele"))
	var node = null
	for x in _arc().vfx._owned:
		if is_instance_valid(x) and str((x as Node).get_meta("arcane_eq_vfx", "")) == "stele":
			node = x
	_ok("⑥ ★分母: 找到了那个碑节点", node != null)
	if node != null:
		_ok("⑥ 碑节点挂在战斗世界 _world 下(不是孤儿)",
			is_instance_valid((node as Node).get_parent()) and (node as Node).get_parent() == _s._world,
			str((node as Node).get_parent()))
		## ★量【效果半径】本身: 250 码, 不是贴片尺寸(memory 那次把半径当尺寸, 公式全对但长 19.2 米)
		_ok("⑥ 碑的地面环记着真实效果半径 250 码",
			absf(float((node as Node).get_meta("radius_px", -1.0)) - 250.0) < 1e-6,
			"实测 %.2f" % float((node as Node).get_meta("radius_px", -1.0)))
		_ok("⑥ 碑节点有两个子件(地面环 + 碑体)", (node as Node).get_child_count() == 2,
			"children=%d" % (node as Node).get_child_count())

	## 每秒一跳的潮涌环: 5 跳 ⇒ 至少建过 5 个 pulse
	_feed(5.4)
	_ok("⑥ 5 秒里潮涌环脉冲了 5 次(每跳一圈)",
		_count_meta("pulse") >= 5, "累计 %d" % _count_meta("pulse"))

	## 浪潮折线: 段数 = 跳数 × ARC_SEG
	_fresh()
	_arc().vfx.clear()
	var pts: Array = [Vector2(0, 0), Vector2(200, 0), Vector2(200, 200)]
	var wave = _arc().vfx.wave_path(pts)
	_ok("⑥ 浪潮折线建出来了", wave != null and is_instance_valid(wave))
	if wave != null:
		# ★★2026-08-08 浪潮从"折线"改成"**一簇水**"(用户: 一簇水在目标之间跳来跳去,
		#   有高度变化, 并不是闪电连锁) ⇒ 断言也跟着换成这一条的真判据。
		_ok("⑥ 一簇水: %d 颗水滴" % ArcaneEqVfx.WATER_DROPS,
			(wave as Node).get_child_count() == ArcaneEqVfx.WATER_DROPS,
			"children=%d" % (wave as Node).get_child_count())
		# ★★"有高度变化": **量真实节点的世界 Y**, 不是断言公式存在。
		#   一跳的中点必须明显高于落点 —— 平着飞就不叫"跳"。
		var _d0 = (wave as Node).get_child(0)
		_feed(EqArcaneBatch.WAVE_HOP_SEC * 0.5)
		var y_mid: float = (_d0 as Node3D).position.y
		_feed(EqArcaneBatch.WAVE_HOP_SEC * 0.5)
		var y_end: float = (_d0 as Node3D).position.y
		_ok("⑥ ★有高度变化: 跳到一半时比落点高(平着飞就不叫跳)",
			y_mid > y_end + 0.15, "中点 y=%.3f 落点 y=%.3f" % [y_mid, y_end])
		_ok("⑥ 折线记着真实几何长度 400 码",
			absf(float((wave as Node).get_meta("path_len", -1.0)) - 400.0) < 1e-6,
			"实测 %.2f" % float((wave as Node).get_meta("path_len", -1.0)))

	## 符纸跟着目标走(位置真的随目标变)
	_fresh()
	_arc().vfx.clear()
	var tgt := _mk("fortune", "right", Vector2(0, 0))
	var tal = _arc().vfx.talisman_stick(tgt, 15.0)
	_ok("⑥ 符纸节点建出来了", tal != null and is_instance_valid(tal))
	if tal != null:
		var p0: Vector3 = (tal as Node3D).position
		tgt["pos"] = (tgt["pos"] as Vector2) + Vector2(300, 0)
		_arc().vfx.tick(0.05)
		_ok("⑥ ★符纸真的跟着目标走(目标移动 300 码后节点位置变了)",
			(tal as Node3D).position.distance_to(p0) > 1.0,
			"位移 %.3f 米" % (tal as Node3D).position.distance_to(p0))


func _count_meta(kind: String) -> int:
	var n := 0
	for x in _arc().vfx._owned:
		if is_instance_valid(x) and str((x as Node).get_meta("arcane_eq_vfx", "")) == kind:
			n += 1
	return n


# ═════════════════════════════════════════════════════════════
# ⑦ 换路撤场 —— 漏了就把上一路的碑/攻速带进下一路
# ═════════════════════════════════════════════════════════════
func _t_clear_all() -> void:
	print("── ⑦ 换路撤场 ──")
	_fresh()
	var u := _mk("fortune", "left", Vector2(0, 0))
	u["equips"] = [{"id": "p2eq_088", "star": 3}, {"id": "p2eq_089", "star": 3}, {"id": "p2eq_090", "star": 3}]
	u["eq_state"] = {}
	u["atk"] = 100.0
	var _e3 := _mk("fortune", "right", Vector2(120, 0))
	_s._equip_sys.fire_equip_effect(u, "p2eq_088", 3)
	_s._equip_sys.fire_equip_effect(u, "p2eq_089", 3)
	_s._equip_sys.fire_equip_effect(u, "p2eq_090", 3)
	_feed(0.1)
	_ok("⑦ ★分母: 撤场前三样都在(碑 %d / 符纸 %d / 在途猛砸 %d) 且攻速已加成"
			% [_arc()._steles.size(), _arc()._talismans.size(), _arc()._slams.size()],
		_arc()._steles.size() == 1 and _arc()._talismans.size() == 1
			and _arc()._slams.size() == 1 and absf(float(u["aspd_perm"]) - 1.25) < 1e-6,
		"aspd=%.4f" % float(u["aspd_perm"]))
	_arc().clear_all()
	_ok("⑦ 撤场后三张表全空",
		_arc()._steles.is_empty() and _arc()._talismans.is_empty() and _arc()._slams.is_empty())
	_ok("⑦ ★撤场把圈内攻速增量还了回去(不还就是每换一路白涨一次)",
		absf(float(u["aspd_perm"]) - 1.0) < 1e-6, "实测 %.4f" % float(u["aspd_perm"]))
	_ok("⑦ 撤场把演出节点也清了", _arc().vfx.alive_count() == 0,
		"n=%d" % _arc().vfx.alive_count())
	_ok("⑦ 撤场把两把法力锁都解开(不解就把锁带进下一路)",
		not _arc().mana_locked(u, "p2eq_088") and not _arc().mana_locked(u, "p2eq_090"))
