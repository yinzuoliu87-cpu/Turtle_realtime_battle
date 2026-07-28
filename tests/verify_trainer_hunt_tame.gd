extends Node
## verify_trainer_hunt_tame.gd — 训龟大师两个新技能：猎龟令 / 驯服
##
## 需求原文（用户 2026-07-28）：
##   猎龟令 30 秒 CD，600 码内指定敌方目标，给它挂 15 秒「猎龟令」：
##     嘲讽 400 码内我方友军优先攻击它、它受到 15% 额外伤害，圈跟着目标走
##   驯服 60 秒 CD，600 码内指定敌方目标：它死后以 30% 最大生命重生并归顺我方，
##     重生 2.5 秒无敌不可选中，此后每秒损失 2% 最大生命，可跨入终极战场
##
## ★★ 期望值全部写【字面需求值】，不许引用 battle.HUNT_* / battle.TAME_* ★★
##    否则就是拿代码跟它自己比 = 恒真式（verify_trainer_magicstone 第一版就栽在这，
##    把常量改坏测试照样 ALL PASS）。实现改了而需求没改 → 这里就该红。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_trainer_hunt_tame.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

# ── 需求字面值 ──
const WANT_HUNT_CD := 30.0
const WANT_HUNT_RANGE := 600.0
const WANT_HUNT_SEC := 15.0
const WANT_HUNT_TAUNT_R := 400.0
const WANT_HUNT_VULN := 1.15        # 受到 15% 额外伤害
const WANT_TAME_CD := 60.0
const WANT_TAME_RANGE := 600.0
const WANT_TAME_REVIVE := 0.30      # 30% 最大生命重生
const WANT_TAME_INVULN := 2.5       # 重生演出 2.5 秒
const WANT_TAME_DECAY := 0.02       # 每秒 2% 最大生命

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	print("=== 训龟大师·猎龟令 / 驯服 ===")

	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame

	# ── ① 技能表参数 ──
	var h: Dictionary = s.TRAINER_SKILLS.get("hunt_order", {})
	var t: Dictionary = s.TRAINER_SKILLS.get("tame", {})
	print("")
	print("  ① 技能表:")
	print("     猎龟令 cd=%s range=%s aim=%s" % [str(h.get("cd")), str(h.get("range")), str(h.get("aim"))])
	print("     驯服   cd=%s range=%s aim=%s" % [str(t.get("cd")), str(t.get("range")), str(t.get("aim"))])
	_chk("① 猎龟令 CD=%.0f / 射程=%.0f / aim=target" % [WANT_HUNT_CD, WANT_HUNT_RANGE],
		absf(float(h.get("cd", 0.0)) - WANT_HUNT_CD) < 0.01
		and absf(float(h.get("range", 0.0)) - WANT_HUNT_RANGE) < 0.01
		and str(h.get("aim", "")) == "target")
	_chk("① 驯服 CD=%.0f / 射程=%.0f / aim=target" % [WANT_TAME_CD, WANT_TAME_RANGE],
		absf(float(t.get("cd", 0.0)) - WANT_TAME_CD) < 0.01
		and absf(float(t.get("range", 0.0)) - WANT_TAME_RANGE) < 0.01
		and str(t.get("aim", "")) == "target")

	var tr = _my_trainer(s)
	if tr == null:
		print("  [FAIL] ★分母: 场上没有我方训龟大师 —— 后面全是空检查"); _fail += 1; _done(s); return
	var foe = _foe(s)
	if foe.is_empty():
		print("  [FAIL] ★分母: 场上没有敌方单位"); _fail += 1; _done(s); return
	print("")
	print("  ★分母: 大师 @%s / 靶子「%s」maxHp=%.0f" % [str(tr["pos"].round()), str(foe.get("name", "?")), float(foe["maxHp"])])

	# ── ② 猎龟令: 标记 + 受伤放大 ──
	foe["pos"] = tr["pos"] + Vector2(300.0, 0.0)          # 放进 600 码射程
	tr["_active_cd"] = 0.0
	s._trainer_sys._hunt_mark(tr, foe)                     # 直接调纯效果, 不等弹道/演出
	var marked: bool = bool(foe.get("_hunt_marked", false))
	var left: float = float(foe.get("hunt_until", 0.0)) - s._t
	print("")
	print("  ② 标记证据 _hunt_marked=%s   剩余 %.2f 秒 (需求 %.0f)" % [str(marked), left, WANT_HUNT_SEC])
	_chk("② 猎龟令标记生效且持续 %.0f 秒" % WANT_HUNT_SEC, marked and absf(left - WANT_HUNT_SEC) < 0.3)

	# 受伤放大: 同一发伤害, 有标记 vs 无标记
	foe["def"] = 0.0; foe["mr"] = 0.0; foe["shield"] = 0.0; foe["flat_dr"] = 0.0
	foe["id"] = "_dummy_target"
	var base: float = s._mitigate_incoming(foe, 1000.0, false, false)
	foe["hunt_until"] = 0.0
	var plain: float = s._mitigate_incoming(foe, 1000.0, false, false)
	foe["hunt_until"] = s._t + WANT_HUNT_SEC
	print("")
	print("  ③ 同一发 1000 伤害: 无标记 %.1f → 有标记 %.1f  (比值 %.4f, 需求 %.2f)" % [
		plain, base, base / maxf(1.0, plain), WANT_HUNT_VULN])
	_chk("③ 被标记者受到伤害 ×%.2f (走 _mitigate_incoming 唯一入口)" % WANT_HUNT_VULN,
		absf(base / maxf(1.0, plain) - WANT_HUNT_VULN) < 0.005)

	# ── ④ 嘲讽: 圈内我方友军优先打它 ──
	var ally = _my_ally(s)
	if ally.is_empty():
		print("  [FAIL] ★分母: 场上没有我方非大师单位"); _fail += 1
	else:
		ally["pos"] = foe["pos"] + Vector2(200.0, 0.0)     # 圈内(200 < 400)
		s._trainer_sys._tick_hunt_taunt(0.016)
		var in_r: bool = s._t < float(ally.get("taunt_until", 0.0)) and is_same(ally.get("taunt_by", null), foe)
		ally["pos"] = foe["pos"] + Vector2(900.0, 0.0)     # 圈外(900 > 400)
		ally["taunt_until"] = 0.0; ally["taunt_by"] = null
		s._trainer_sys._tick_hunt_taunt(0.016)
		var out_r: bool = s._t < float(ally.get("taunt_until", 0.0))
		print("")
		print("  ④ 友军距目标 200 码(圈内 %.0f) → 被嘲讽=%s" % [WANT_HUNT_TAUNT_R, str(in_r)])
		print("     友军距目标 900 码(圈外)      → 被嘲讽=%s (应为 false)" % str(out_r))
		_chk("④ 嘲讽只对 %.0f 码内我方友军生效(圈随目标移动)" % WANT_HUNT_TAUNT_R, in_r and not out_r)

	# ── ⑤ 驯服: 死亡 → 30% 重生 + 归顺 ──
	var f2 = _foe(s)
	if f2.is_empty():
		print("  [FAIL] ★分母: 找不到第二个敌人做驯服测试"); _fail += 1; _done(s); return
	var orig_side := str(f2.get("side", ""))
	s._trainer_sys._tame_mark(tr, f2)
	print("")
	print("  ⑤ 驯服标记: _tamed_marked=%s  (标记【无 until】—— 持续到战斗结束或死亡)" % str(f2.get("_tamed_marked", false)))
	_chk("⑤ 驯服标记生效且不带定时", bool(f2.get("_tamed_marked", false)) and not f2.has("tame_until"))

	var mx: float = float(f2["maxHp"])
	f2["hp"] = 1.0
	s._kill(f2)                                            # 走真实死亡路径
	var alive_after: bool = bool(f2.get("alive", false))
	var hp_frac: float = float(f2["hp"]) / mx
	print("")
	print("  ⑥ 死亡后: alive=%s  hp=%.0f/%.0f = %.1f%% (需求 %.0f%%)" % [
		str(alive_after), float(f2["hp"]), mx, hp_frac * 100.0, WANT_TAME_REVIVE * 100.0])
	print("     阵营: side=%s(未改写) → 有效阵营 _eff_side=%s (需求 left)" % [orig_side, s._eff_side(f2)])
	_chk("⑥ 不真死, 以 %.0f%% 最大生命重生" % (WANT_TAME_REVIVE * 100.0), alive_after and absf(hp_frac - WANT_TAME_REVIVE) < 0.02)
	_chk("⑥ ★归顺我方且【没有改写 side】", s._eff_side(f2) == "left" and str(f2.get("side", "")) == orig_side)
	_chk("⑥ 对我方不再敌对(真换队, 不是赛博那种孤军)", not s._is_hostile(f2, tr) and not s._is_hostile(tr, f2))

	# ── ⑦ 重生演出期无敌 + 不可选中 ──
	var inv: float = float(f2.get("_tame_invuln_until", 0.0)) - s._t
	var untg: float = float(f2.get("untargetable_until", 0.0)) - s._t
	var mit: float = s._mitigate_incoming(f2, 1000.0, false, false)
	print("")
	print("  ⑦ 无敌剩余 %.2f 秒 / 不可选中剩余 %.2f 秒 (需求 %.1f)" % [inv, untg, WANT_TAME_INVULN])
	print("     演出期挨 1000 伤害 → 实际 %.1f (应为 0)" % mit)
	_chk("⑦ 重生 %.1f 秒内无敌且不可选中" % WANT_TAME_INVULN,
		absf(inv - WANT_TAME_INVULN) < 0.3 and absf(untg - WANT_TAME_INVULN) < 0.3 and mit < 0.01)

	# ── ⑧ 归顺后每秒掉 2% ──
	f2["_tame_invuln_until"] = 0.0                          # 跳过演出期
	f2["hp"] = mx
	f2["def"] = 0.0; f2["mr"] = 0.0; f2["shield"] = 0.0; f2["flat_dr"] = 0.0
	f2["id"] = "_dummy_target"      # ★同上: _mitigate_incoming 有按 id 的减伤分支(钻石×0.82/石头岩石之躯),
	                                #   靶子是随机 spawn 的敌人 → 抽到那几只就偶发红
	s._trainer_sys._tick_tame_decay(1.0)                    # 模拟整 1 秒
	var lost: float = (mx - float(f2["hp"])) / mx
	print("")
	print("  ⑧ 1 秒掉血 %.2f%% (需求 %.0f%%)" % [lost * 100.0, WANT_TAME_DECAY * 100.0])
	_chk("⑧ 归顺后每秒损失 %.0f%% 最大生命" % (WANT_TAME_DECAY * 100.0), absf(lost - WANT_TAME_DECAY) < 0.004)

	_done(s)


func _my_trainer(s):
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			return u
	return null


## 一个还没被标记过的敌方单位(每次调返回不同的)
func _foe(s) -> Dictionary:
	for u in s._units:
		if str(u.get("side", "")) != "right" or u.get("is_trainer", false) or not u.get("alive", false):
			continue
		if u.get("_hunt_marked", false) or u.get("_tamed_marked", false):
			continue
		return u
	return {}


func _my_ally(s) -> Dictionary:
	for u in s._units:
		if str(u.get("side", "")) == "left" and not u.get("is_trainer", false) and u.get("alive", false):
			return u
	return {}


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 猎龟令 / 驯服" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
