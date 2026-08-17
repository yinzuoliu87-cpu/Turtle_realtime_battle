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

	# ── ⑥ 087 压载舱: 同族的第二条(2026-08-17 补) ────────────────────────
	##   ★由来: 087 的压载舱是个【看不见的血池】—— 伤害先灌进舱、舱满才真掉血,
	##     而玩家局内完全看不到攒到哪。头顶那个 dive_gauge 是演出层的, 而用户
	##     2026-08-08 定过「充能条和层数不要放头顶, 在装备图标框里」。
	##   ★判据走【面板真正会印的那行字】, 不是读字段 —— 字段对了但表没登记 = 玩家还是看不见。
	var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u87: Dictionary = _s._spawn._make_unit("basic", "left", c2)
	u87["equips"] = [{"id": "p2eq_087", "star": 2}]
	_s._units.clear()
	_s._units.append(u87)
	var gs87 = _s._equip_sys._gadget_sys
	for _i in range(4):
		gs87.tick_unit(u87, 0.5)
	var st87: Dictionary = (u87.get("eq_state", {}) as Dictionary).get("p2eq_087", {})
	_ok("⑥ ★分母: 087 的舱容算出来了(不是 0 ⇒ 下面不是空检查)",
		float(st87.get("cap", 0.0)) > 1.0, "cap=%.0f" % float(st87.get("cap", 0.0)))
	_ok("⑥ ★★087 进了局内充能条表 —— 漏了就是「攒了没人看得见」",
		_s.PANEL_CHARGE.has("p2eq_087"))
	var r0 := str(_s._info_sys._equip_readout_text(u87, "p2eq_087"))
	_ok("⑥ ★分母: 开局读数为 0(没挨打之前舱是空的)", r0.find("0%") >= 0, "实得 '%s'" % r0)
	_s._damage._apply_damage(u87, 300, Color.WHITE)
	for _j in range(2):
		gs87.tick_unit(u87, 0.5)
	var pct87: float = float(((u87.get("eq_state", {}) as Dictionary).get("p2eq_087", {}) as Dictionary).get("ballast_pct", 0.0))
	var r1 := str(_s._info_sys._equip_readout_text(u87, "p2eq_087"))
	_ok("⑥ ★★挨打之后【面板那行字真的变了】(不是恒 0 的死字段)",
		r1 != r0 and pct87 > 1.0, "'%s' → '%s' (镜像 %.1f%%)" % [r0, r1, pct87])
	## 300 / (maxHp × 90%) —— 和系统自己算的舱容对账, 不抄一份公式
	var want87: float = 300.0 / maxf(1.0, float(st87.get("cap", 1.0))) * 100.0
	_ok("⑥ ★读数与真实舱内水量一致(不是随便变一下)", absf(pct87 - want87) < 2.0,
		"面板 %.1f%% vs 应为 %.1f%%" % [pct87, want87])

	# ── ⑧ 015 荆棘海胆: 同族的第三条(2026-08-17 补) ───────────────────────
	##   ★由来: 用脚本重扫 `eq_state` 的写入字段 vs 两张读数表(上一次 2026-08-10 是
	##     **人眼扫的、漏了 068**), 扫出 015 在两张表里【一个字都没有】——
	##     反伤累计满 300/270/230 → 护盾 + 强化下一次普攻, 而玩家既看不到攒到哪,
	##     也不知道下一击有没有被强化。它与 017 完全同构(就绪次数 + 攒进度),
	##     却只有 017 有出口。
	##   ★判据同 ⑥: 量【面板真正会印的那行字】随真实战斗事件变, 不读字段、不查表。
	var u15: Dictionary = _s._spawn._make_unit("basic", "left", c2)
	u15["equips"] = [{"id": "p2eq_015", "star": 1}]   # 1★ 阈值 300, 反伤 12%
	var atk15: Dictionary = _s._spawn._make_unit("basic", "right", c2 + Vector2(40, 0))
	_s._units.clear()
	_s._units.append(u15)
	_s._units.append(atk15)
	## ★装备要真的生效必须走这两步(spawn 期的既有做法, 见 equip_system.gd:896 的注释):
	##   ①属性 ②flag/eq_state 初始状态。少走第二步的话 eq_state 是空的, 下面全是空检查。
	_s._equip_sys._stats._eq_apply_one_stats(u15, "p2eq_015", 1)   # star=1 ⇒ si=0
	_s._equip_sys._stats._eq_apply_flags(u15, "p2eq_015", 1)   # star=1 ⇒ si=0
	var g0 := str(_s._info_sys._equip_readout_text(u15, "p2eq_015"))
	_ok("⑧ ★分母: 015 装上后面板真的会印出一行读数(空串 = 没进表)", g0 != "", "实得 '%s'" % g0)
	_ok("⑧ ★分母: 开局读数是 0 层 0%%(还没挨打)",
		g0.find("0层") >= 0 and g0.find("0%") >= 0, "实得 '%s'" % g0)
	## 挨一发 1000 —— 反伤 12% = 120 点, 占 1★ 阈值 300 的 40%
	_s._equip_sys._eq_on_target(u15, atk15, 1000)
	var g1 := str(_s._info_sys._equip_readout_text(u15, "p2eq_015"))
	var st15: Dictionary = (u15.get("eq_state", {}) as Dictionary).get("p2eq_015", {})
	var acc15: float = float(st15.get("thorn_accum", 0.0))
	_ok("⑧ ★分母: 挨打后系统侧真的攒了(0 = 下面是空检查)", acc15 > 1.0, "accum=%.0f" % acc15)
	_ok("⑧ ★★挨打后【面板那行字真的变了】(不是恒 0 的死字段)", g1 != g0, "'%s' → '%s'" % [g0, g1])
	## 与系统自己的阈值对账, 不抄一份公式
	var want15: float = acc15 / _s._equip_sys.THORN_THRESHOLD[0] * 100.0
	var got15: float = float(st15.get("thorn_pct", -1.0))
	_ok("⑧ ★读数 = 累计/阈值(不是随便变一下)", absf(got15 - want15) < 1.0,
		"镜像 %.1f%% vs 应为 %.1f%%" % [got15, want15])
	## 再挨两发把它推过阈值 ⇒ 强化次数徽章要跳起来, 且进度条要回落(不是卡在 100%)
	_s._equip_sys._eq_on_target(u15, atk15, 1000)
	_s._equip_sys._eq_on_target(u15, atk15, 1000)
	var st15b: Dictionary = (u15.get("eq_state", {}) as Dictionary).get("p2eq_015", {})
	var g2 := str(_s._info_sys._equip_readout_text(u15, "p2eq_015"))
	_ok("⑧ ★分母: 累计已经越过阈值(没越过的话下面两条是空检查)",
		int(st15b.get("thorn_empower", 0)) >= 1, "强化次数=%d" % int(st15b.get("thorn_empower", 0)))
	_ok("⑧ ★★强化次数【印在面板上】了 —— 玩家要知道下一击被强化了", g2.find("0层") < 0,
		"实得 '%s'" % g2)
	_ok("⑧ ★越过阈值后进度条回落(卡在 100%% = 归一化写在了扣减之前)",
		float(st15b.get("thorn_pct", 100.0)) < 99.0,
		"实得 %.1f%%" % float(st15b.get("thorn_pct", -1.0)))

	# ── ⑦ 读数不许长到把槽撑爆(2026-08-17) ──────────────────────────────
	##   ★由来(实拍): 093 香火石两张表里都有 ⇒ 拼出「充能 0 / 4000  层数 0」17 个字,
	##     而槽只有 88px 宽 ⇒ 被 clip_text 从中间截断, 屏幕上印的是「能 0 / 4000  层数」。
	##     两条读数各自都对, 挤在一起就成了乱码。
	##   ★判据量【真实像素宽】(拿槽上那个 Label 的实际字体去算), 不是数字符数 ——
	##     中英文/数字宽度差很多, 数字符数会漏。
	##   ⚠★2026-08-17 订正: 这里【原来写死 font_size 11】, 而槽底读数真实用的是 **9**
	##     ⇒ 量的不是同一个东西(偏保守所以没出事, 但判据和被判对象是两个来源, 迟早漂)。
	##     现在两边都从 `UIPalette.F_MICRO` 取 —— 改字号时这条门禁自动跟着走。
	var probe := Label.new()
	probe.add_theme_font_size_override("font_size", UIPalette.F_MICRO)
	add_child(probe)
	await get_tree().process_frame
	var fnt: Font = probe.get_theme_font("font")
	var fsz: int = probe.get_theme_font_size("font_size")
	_ok("⑦ ★分母: 拿到了槽上读数用的字体(拿不到就是空检查)", fnt != null)
	var too_wide: Array = []
	var checked := 0
	if fnt != null:
		var ids: Array = []
		for k in _s.PANEL_COUNT.keys():
			ids.append(str(k))
		for k2 in _s.PANEL_CHARGE.keys():
			if not ids.has(str(k2)):
				ids.append(str(k2))
		for eid in ids:
			var uu: Dictionary = _s._spawn._make_unit("basic", "left", c2)
			uu["equips"] = [{"id": str(eid), "star": 3}]
			var txt := str(_s._info_sys._equip_readout_text(uu, str(eid)))
			if txt == "":
				continue
			checked += 1
			var w: float = fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
			## 槽 88px, 左右各留 4px 内边距 ⇒ 可用 80px
			if w > 80.0:
				too_wide.append("%s「%s」%.0fpx" % [eid, txt, w])
	probe.queue_free()
	_ok("⑦ ★分母: 逐件量了读数宽度(N=0 是空检查)", checked >= 15, "量了 %d 件" % checked)
	_ok("⑦ ★★没有读数宽到把 88px 的槽撑爆(会被截成乱码)", too_wide.is_empty(),
		"太宽的: %s" % str(too_wide.slice(0, 5)))

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 068 充能读数" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
