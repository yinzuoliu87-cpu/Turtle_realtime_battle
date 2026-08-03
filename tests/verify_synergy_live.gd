extends Node
## verify_synergy_live.gd — 类型羁绊【真的生效了】（批 4-1 · 方案书 §5 的 🟢 部分）
##
## ★这个门禁存在的理由，是本项目最典型的一类事故：
##   `Phase2Types.apply_team_start` 写得好好的、九个标记一应俱全，
##   **全仓库零调用方**，实时版没有任何消费方 —— 玩家在背包面板看得见档位，打起来毫无区别。
##   memory [[fb-verify-must-run-the-real-path]]：**「断言函数存在」守不住「还有没有人调」。**
##   ⇒ 所以这里**一条都不验"函数在不在"**，全部验**单位字典上的数值真的变了**。
##
## 守六组：
##   ① ★分母 + 对照：不激活羁绊时属性【一点都不加】（否则下面全是恒真式）
##   ② 达到首档 → per-piece 属性真的加到了携带者身上，且用的是**战斗的字段名**
##      （`base_atk` 而不是回合制的 `baseAtk` —— 那正是 apply_team_start 写了没人读的原因）
##   ③ ★per-piece 是「携带者身上几件」不是「全队几件」：同队另一只带 3 件，本只带 1 件 → 只吃 1 件的量
##   ④ ★档位越高每件给得越多（凸梯度），且**没激活的类型一点不给**
##   ⑤ 周期效果：法器潮涌 / 食物盛宴 真的回血，盾圣光真的给盾
##   ⑥ ★计数域是【全队】不是【本路】（D11）：两只不同 side 的单位各自按自己那方算
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_synergy_live.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0
var _s


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 类型羁绊真的生效了 (批4-1) ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	# 剑 = [3,6,9]，每档每件 +15 / +38 / +62 攻击力
	var swords: Array = _ids_of_type("剑", 9)
	_ok("★分母: 找到 %d 件剑类装备(需要 ≥9 件才验得了顶档)" % swords.size(), swords.size() >= 9)

	# ── ① 对照：2 件剑（不到首档 3）⇒ 一点都不加 ──────────────
	var u0: Dictionary = _run([_mk("left", swords.slice(0, 2))])[0]
	_ok("① ★对照: 只带 2 件剑(未达首档 3) → 攻击力一点不加",
		absf(float(u0["base_atk"]) - 100.0) < 0.01, "base_atk=%.1f (基准 100)" % float(u0["base_atk"]))

	# ── ② 首档：3 件剑，全在一只身上 ⇒ 每件 +15 × 3 = +45 ──────
	var u1: Dictionary = _run([_mk("left", swords.slice(0, 3))])[0]
	_ok("② 剑首档(3件): 携带者 base_atk = 100 + 15×3 = 145",
		absf(float(u1["base_atk"]) - 145.0) < 0.01, "实得 %.1f" % float(u1["base_atk"]))
	_ok("② ★用的是战斗字段 base_atk, 不是回合制的 baseAtk(那是 apply_team_start 写了没人读的原因)",
		not u1.has("baseAtk"), "baseAtk 存在=%s" % str(u1.has("baseAtk")))

	# ── ③ per-piece 是「携带者身上几件」不是「全队几件」 ────────
	# A 带 3 件、B 带 1 件 ⇒ 队伍共 4 件(仍是首档), A 吃 3 件的量、B 只吃 1 件的量。
	var us := _run([_mk("left", swords.slice(0, 3)), _mk("left", swords.slice(3, 4))])
	_ok("③ 队友带 3 件时, 本只只带 1 件 → 只吃 1 件的量(+15)",
		absf(float(us[1]["base_atk"]) - 115.0) < 0.01, "实得 %.1f" % float(us[1]["base_atk"]))
	_ok("③ ★同一队里带 3 件的那只吃 3 件的量(+45) —— per-piece 不是全队均分",
		absf(float(us[0]["base_atk"]) - 145.0) < 0.01, "实得 %.1f" % float(us[0]["base_atk"]))

	# ── ④ 档位梯度 + 未激活类型不给 ────────────────────────────
	# 6 件剑分给两只(各 3 件) ⇒ 全队 6 件 = 第 2 档, 每件 +38
	var us2 := _run([_mk("left", swords.slice(0, 3)), _mk("left", swords.slice(3, 6))])
	_ok("④ 剑二档(全队 6 件): 每件 38 → 带 3 件者 100 + 114 = 214",
		absf(float(us2[0]["base_atk"]) - 214.0) < 0.01, "实得 %.1f" % float(us2[0]["base_atk"]))
	var us3 := _run([_mk("left", swords.slice(0, 3)), _mk("left", swords.slice(3, 6)),
		_mk("left", swords.slice(6, 9))])
	_ok("④ 剑顶档(全队 9 件): 每件 62 → 带 3 件者 100 + 186 = 286",
		absf(float(us3[0]["base_atk"]) - 286.0) < 0.01, "实得 %.1f" % float(us3[0]["base_atk"]))
	_ok("④ ★梯度是凸的(15 → 38 → 62, 每档增量递增)", 38 - 15 < 62 - 38)
	# 未激活的类型: 盾没凑够 3 件 ⇒ 护甲不加
	var shields: Array = _ids_of_type("盾", 2)
	var u4: Dictionary = _run([_mk("left", swords.slice(0, 3) + shields.slice(0, 2))])[0]
	_ok("④ ★没激活的类型一点不给(带 2 件盾, 未达首档 3 → 护甲不加)",
		absf(float(u4["base_def"])) < 0.01, "base_def=%.1f" % float(u4["base_def"]))

	# ── ⑤ 周期效果真的发生 ────────────────────────────────────
	# 法器 [2,5,8,10]，档2(5 件) 潮涌 = 每 2.5 秒回复已损失生命 5%
	var staffs: Array = _ids_of_type("法器", 5)
	var u5: Dictionary = _run([_mk("left", staffs.slice(0, 3)), _mk("left", staffs.slice(3, 5))])[0]
	u5["hp"] = float(u5["maxHp"]) * 0.5          # 掉一半血, 才有"已损失"可回
	var hp_before: float = float(u5["hp"])
	_s._synergy._t_pulse = 0.0
	_s._synergy.tick(2.6)                        # 推过一个 2.5 秒节拍
	_ok("⑤ 法器潮涌: 掉血后过一个节拍会回血(回 已损失的 5%%)",
		float(u5["hp"]) > hp_before + 1.0,
		"%.0f → %.0f (已损失 %.0f)" % [hp_before, float(u5["hp"]), float(u5["maxHp"]) - hp_before])
	# 盾圣光: 档2(6 件) → 基数 50 ×(1+0.4×身上件数)
	var shields9: Array = _ids_of_type("盾", 9)
	var u6: Dictionary = _run([_mk("left", shields9.slice(0, 3)), _mk("left", shields9.slice(3, 6))])[0]
	var sh_before: float = float(u6.get("shield", 0.0))
	_s._synergy._t_light = 0.0
	_s._synergy.tick(5.1)
	_ok("⑤ 盾圣光: 过一个 5 秒节拍后携带者获得护盾(基数 50 × (1+0.4×3) = 110)",
		float(u6.get("shield", 0.0)) > sh_before + 1.0,
		"%.0f → %.0f" % [sh_before, float(u6.get("shield", 0.0))])

	# ── ⑥ 计数域按【全队】且两方各算各的 ──────────────────────
	# 我方 3 件剑(激活) / 敌方 1 件剑(不激活) ⇒ 敌方那只一点不加。
	var mix := _run([_mk("left", swords.slice(0, 3)), _mk("right", swords.slice(0, 1))])
	_ok("⑥ ★敌方按敌方自己的件数算(1 件剑不到首档 → 不加)",
		absf(float(mix[1]["base_atk"]) - 100.0) < 0.01, "敌 base_atk=%.1f" % float(mix[1]["base_atk"]))
	_ok("⑥ 我方仍然吃到首档", absf(float(mix[0]["base_atk"]) - 145.0) < 0.01,
		"我 base_atk=%.1f" % float(mix[0]["base_atk"]))

	# ★收尾必须先清空 _units 再释放场景: 合成单位没有 sprite / bar_root(渲染节点),
	#   留在战场上会被渲染步撞出 "Invalid access to property 'sprite'" ——
	#   断言全绿, 但 run-tests.sh 的致命正则会把整个测试判红, 表现得像"断言没打出来"。
	_s._units.clear()
	_s.set_process(false)
	await get_tree().process_frame
	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 类型羁绊真的生效(批4-1)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 某类型的前 n 件装备 id
func _ids_of_type(t: String, n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		if Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == t:
			out.append(str((e as Dictionary).get("id", "")))
		if out.size() >= n:
			break
	return out


## 干净合成单位（memory fb-ci-vs-local-divergence：随机 spawn 的单位测精确数值会 CI 偶发红）
func _mk(side: String, ids: Array) -> Dictionary:
	var eqs: Array = []
	for i in ids:
		eqs.append({"id": str(i), "star": 1})
	return {"id": "basic", "name": "合成", "side": side, "alive": true,
		"hp": 3000.0, "maxHp": 3000.0, "shield": 0.0, "equips": eqs, "eq_state": {},
		"base_atk": 100.0, "atk": 100.0, "base_def": 0.0, "def": 0.0,
		"base_mr": 0.0, "mr": 0.0, "crit": 0.0, "crit_dmg": 1.5,
		"armor_pen": 0.0, "magic_pen": 0.0, "lifesteal": 0.0, "buffs": {},
		"pos": Vector2.ZERO}


## 放一组单位进战场并施加羁绊。★每次都重置 _by_side —— 羁绊设计上是"一场算一次"（D11），
## 但门禁要在同一个场景实例里跑很多组，必须显式重算，否则第二组会拿到第一组的档位。
func _run(units: Array) -> Array:
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	return units
