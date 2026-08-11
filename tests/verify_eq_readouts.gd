extends Node
## verify_eq_readouts.gd — 068 深海气压罐【攒了一整条充能, 局内得看得见】(2026-08-11)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户 2026-08-11「我记得 5 费应该有个气压瓶是吗」
## ══════════════════════════════════════════════════════════════════
## 查下去发现 068 把挨的伤害整条存进 `eq_state["p2eq_068"]["can_charge"]`,
## 而 `PANEL_CHARGE` 与 `PANEL_COUNT` **都没有 068** ⇒ **局内零出口**:
## 玩家看不到自己攒到哪, 而这件的效果恰恰是"攒得越多, 护盾越厚、激光越狠"。
##
## ⚠ 这条与用户 2026-08-10 的原话同族:「我压根没看到装备图标那里有法力条, 在攒法力吗」。
##   那一轮我把 9 件**法器**的法力条接上了, 却漏了这件真正带「法力护盾/法力激光」的 5 费装备。
##
## ⚠★更值得记的一条: `PANEL_COUNT` 上方的注释写着 065/069/074 是
##   「扫 eq_state 写入字段 vs 本表 + PANEL_CHARGE 读取字段**扫出来的**」——
##   但 068 没被扫出来。**那次是人眼扫的**。所以这份门禁不写"我检查过了",
##   而是把判据落在真实字段上, 让它以后自己红。
##
## ★判据落在【真实 eq_state 字段 + 真实伤害入口】, 不量纯函数:
##   走 `_apply_damage` / `_eq_on_target` 真入口喂伤害 → 读 eq_state → 与表里声明的字段对上。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_eq_readouts.tscn --quit-after 2000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EID := "p2eq_068"

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _mk(hp: float, star: int) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-300.0, 0.0))
	u["alive"] = true
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["flat_dr"] = 0.0
	u["damage_reduction"] = 0.0
	u["equips"] = [{"id": EID, "star": star}]
	u["eq_state"] = {}
	# ★走【真实的上装备管线】点亮 `_potion_tick` —— 手搓字典点不亮它,
	#   不走这一步测的就不是"装上这件会发生什么"
	_s._equip_sys._stats._eq_apply_flags(u, EID, star)
	_s._units.append(u)
	return u


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 068 深海气压罐: 充能条必须在局内看得见 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给所有伤害再乘一次, 关掉才量得准

	# ── ① 表里得有它, 且读的字段要对得上 ────────────────────────────
	var tbl: Dictionary = _s.PANEL_CHARGE
	_ok("① ★★068 进了局内充能条表(PANEL_CHARGE) —— 漏了就是「攒了没人看得见」",
		tbl.has(EID), "PANEL_CHARGE 里没有 %s" % EID)
	if not tbl.has(EID):
		print("FAIL x%d" % maxi(_fail, 1)); get_tree().quit(1); return
	var spec: Array = tbl[EID]
	var fld: String = str(spec[0])
	_ok("① 读的是归一化镜像 `can_pct` 而不是原始 `can_charge`",
		fld == "can_pct",
		"实为 %s —— 上限是 maxHp×20/40/100%% 不是常量, 拿原始值当分母会画错" % fld)
	_ok("① ★分母: 满值声明为 100(归一化后的百分比)", absf(float(spec[1]) - 100.0) < 0.01,
		"实为 %.1f" % float(spec[1]))

	# ── ② 走真伤害入口: 挨打 → 读数真的动 ───────────────────────────
	#   3★: 转化 200%, 上限 = maxHp × 100%
	var u := _mk(1000.0, 3)
	var st0: Dictionary = u["eq_state"].get(EID, {})
	_ok("② ★分母: 开局读数为 0(没打之前不该有条)",
		absf(float(st0.get("can_pct", 0.0))) < 0.01,
		"开局就是 %.2f" % float(st0.get("can_pct", 0.0)))

	_s._damage._apply_damage(u, 100, Color(1, 1, 1))    # 真入口(DoT/真伤那条)
	var st: Dictionary = u["eq_state"].get(EID, {})
	var chg: float = float(st.get("can_charge", 0.0))
	var pct: float = float(st.get("can_pct", -1.0))
	_ok("② ★分母: 挨了 100 伤害后原始充能确实涨了(3★ 转化 200%% ⇒ 200)",
		absf(chg - 200.0) < 0.51, "实得 %.2f" % chg)
	_ok("② ★★读数跟着动了(不是恒 0 的死字段)", pct > 0.01,
		"can_pct = %.2f —— 写了没人更新就等于没接" % pct)
	# 上限 = 1000 × 100% = 1000 ⇒ 200/1000 = 20%
	_ok("② ★★读数 = 充能/上限(不是凭空数字): 期望 20.00", absf(pct - 20.0) < 0.05,
		"实得 %.2f (充能 %.1f / 上限 %.1f)" % [pct, chg, 1000.0])

	# ── ③ 封顶后读数正好 100, 不许溢出 ──────────────────────────────
	_s._damage._apply_damage(u, 9999, Color(1, 1, 1))
	var pct2: float = float(u["eq_state"][EID].get("can_pct", -1.0))
	_ok("③ 充能封顶时读数正好 100(溢出会把条画到框外)", absf(pct2 - 100.0) < 0.05,
		"实得 %.2f" % pct2)

	# ── ④ 释放后读数归零 ───────────────────────────────────────────
	#   ★这条守的是"条停在满格骗人": 充能清空了但镜像没清, 玩家会一直看到满条
	var si: int = _s._equip_sys._eq_si(3)
	_s._equip_sys._potion_sys._eq_pressure_release(u, si, u["eq_state"][EID])
	var st3: Dictionary = u["eq_state"][EID]
	_ok("④ ★分母: 释放后原始充能已清空", absf(float(st3.get("can_charge", 1.0))) < 0.01,
		"实得 %.2f" % float(st3.get("can_charge", 1.0)))
	_ok("④ ★★释放后读数也归零(漏了就一直显示满条)",
		absf(float(st3.get("can_pct", 1.0))) < 0.01,
		"实得 %.2f" % float(st3.get("can_pct", 1.0)))

	# ── ⑤ 源码纪律: 写 can_charge 的每一处都要同步写 can_pct ─────────
	#   ★这条是防【以后有人加第三处写入却忘了镜像】—— 那种漏法运行时完全不报错,
	#     条只是"有时候不动", 极难发现。
	var src: String = FileAccess.get_file_as_string(
		"res://scripts/systems/equip/eq_potion_batch.gd")
	var n_chg: int = src.count("\"can_charge\"] =")
	var n_pct: int = src.count("\"can_pct\"] =")
	_ok("⑤ ★分母: 找到了 %d 处 can_charge 赋值" % n_chg, n_chg >= 2,
		"只找到 %d 处 —— 源码结构变了, 这条断言要重写" % n_chg)
	_ok("⑤ ★★每一处写 can_charge 都配了一处写 can_pct(%d vs %d)" % [n_chg, n_pct],
		n_pct >= n_chg,
		"镜像少了 %d 处 ⇒ 那几条路上条不会动" % (n_chg - n_pct))

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 068 充能读数" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
