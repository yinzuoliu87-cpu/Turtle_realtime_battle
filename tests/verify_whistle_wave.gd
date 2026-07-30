extends Node
## verify_whistle_wave.gd — 口哨②灵体气波：真 skillshot（2026-07-30 重做）
##
## 用户原话：「这灵体小龟我都没看到啊，而且灵体小龟不要蓄力放的吗，不是命中才造成伤害吗」
##          「气波飞行距离改为2000，伤害改为100+15%目标最大生命值的真实伤害」
##
## ★★改前是【出手瞬间就把线上所有敌人全打完】—— 探针实测：敌人放在 400 码处
##   （气波 300 码/秒 → 视觉上 1.33 秒后才到），出手【同一帧】hp 就从 100000 掉到 99924。
##   与 2026-07-30 修掉的钩锁【同一类 bug】：判定与演出脱钩、出手即判定。
##
## ★期望值全部写【需求字面值】，不引用 WAVE_* / WHISTLE_WAVE_* 常量 —— 引用常量就是
##   拿代码跟它自己比 = 恒真式（verify_trainer_magicstone 第一版栽过这个）。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_whistle_wave.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

# ── 需求字面值 ──
const WANT_RANGE := 2000.0      # 「气波飞行距离改为2000」
const WANT_FLAT := 100.0        # 「伤害改为100+…」
const WANT_MAXHP_PCT := 0.15    # 「…+15%目标最大生命值的真实伤害」
const WANT_SHRED_SEC := 5.0     # 削甲持续
const WANT_KB := 100.0          # 击飞距离

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	print("=== 口哨②灵体气波·真 skillshot ===")

	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame
	var ts = s._trainer_sys
	var tr = null
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			tr = u; break
	if tr == null:
		print("  [FAIL] ★分母: 没有我方大师 —— 后面全是空检查"); _fail += 1; _done(s); return

	# ── ① 常量对上需求 ──
	print("")
	print("  ① 射程 %.0f 码(需求 %.0f) / 定值 %.0f(需求 %.0f) / 百分比 %.0f%%(需求 %.0f%%)" % [
		ts.WAVE_RANGE, WANT_RANGE, ts.WHISTLE_WAVE_DMG, WANT_FLAT,
		ts.WHISTLE_WAVE_MAXHP_PCT * 100.0, WANT_MAXHP_PCT * 100.0])
	_chk("① 射程 = %.0f 码" % WANT_RANGE, absf(ts.WAVE_RANGE - WANT_RANGE) < 0.5)
	_chk("① 定值段 = %.0f" % WANT_FLAT, absf(ts.WHISTLE_WAVE_DMG - WANT_FLAT) < 0.5)
	_chk("① 百分比段 = %.0f%% 目标最大生命" % (WANT_MAXHP_PCT * 100.0),
		absf(ts.WHISTLE_WAVE_MAXHP_PCT - WANT_MAXHP_PCT) < 0.0005)
	print("     蓄力 %.2f 秒 / 速度 %.0f 码每秒 → 满程 %.2f 秒" % [
		ts.WAVE_WINDUP, ts.WAVE_SPD, ts.WAVE_RANGE / ts.WAVE_SPD])
	_chk("① 有蓄力段(>0·用户:「不要蓄力放的吗」)", ts.WAVE_WINDUP > 0.05)

	# ── ② 造三个干净合成敌: 带满减伤(真伤该穿透) ──
	# ★用合成单位而不是场上随机敌 —— memory fb-ci-vs-local-divergence:
	#   随机 spawn 的敌可能带盾/减伤/按 id 的分支 → CI 偶发红。
	var foes: Array = []
	for k in range(3):
		var u: Dictionary = s._spawn._make_unit("basic", "right",
			tr["pos"] + Vector2(300.0 + 300.0 * float(k), 0.0), {})
		u["maxHp"] = 4000.0; u["hp"] = 4000.0
		u["def"] = 200.0; u["mr"] = 200.0; u["flat_dr"] = 50.0; u["shield"] = 0.0
		u["dodge_bonus"] = 0.0; u["_wave_hit_n"] = 0; u["def_shred_until"] = 0.0
		foes.append(u); s._units.append(u)
	var want_dmg: int = int(round(WANT_FLAT + 4000.0 * WANT_MAXHP_PCT))
	print("")
	print("  ② 三敌在 300/600/900 码, 各 4000 血 + def200/mr200/flat_dr50")
	print("     每个该扣 %.0f + %.0f%%×4000 = %d (真伤 → 满减伤原样穿透)" % [
		WANT_FLAT, WANT_MAXHP_PCT * 100.0, want_dmg])

	# ── ★核心: 出手那一帧【一点血都不该掉】 ──
	var hp_before: Array = [4000.0, 4000.0, 4000.0]
	_chk("② ★分母: 施放返回成功", ts._whistle_spirit_wave(tr) == 1)
	await get_tree().process_frame
	var moved := 0
	for k in range(3):
		if absf(float(foes[k]["hp"]) - float(hp_before[k])) > 0.5:
			moved += 1
	print("     出手【同一帧】掉血的敌人数 = %d (需求 0 —— 改前这里是 3)" % moved)
	_chk("② ★★出手瞬间一个都不掉血(判定不再与演出脱钩)", moved == 0)
	_chk("② 灵体小龟真的现身(_world 有 spirit-turtle billboard)", _has(s, "spirit-turtle.png"))
	_chk("② 蓄力期【气波还没出】(_world 里还没有 spirit-wave)", not _has(s, "spirit-wave.png"))

	# ── ③ 逐帧推进: 各敌被击中的时刻 + 扣血量 ──
	var t0: float = s._t
	var seen: Array = []
	var fired_at: float = -1.0
	for step in range(400):
		s._t = t0 + float(step + 1) * (1.0 / 60.0)
		ts._tick_wave_flights(1.0 / 60.0)
		if fired_at < 0.0 and _has(s, "spirit-wave.png"):
			fired_at = s._t - t0
		for k in range(3):
			if int(foes[k].get("_wave_hit_n", 0)) > 0 and not seen.has(k):
				seen.append(k)
				var dealt: float = 4000.0 - float(foes[k]["hp"])
				print("     t=%.2fs 第%d个(%.0f码) 命中: 扣 %.0f (需求 %d)" % [
					s._t - t0, k + 1, 300.0 + 300.0 * float(k), dealt, want_dmg])
				_chk("③ 第%d个 扣 %d(=%.0f+%.0f%%最大生命·真伤穿满减伤)" % [k + 1, want_dmg, WANT_FLAT, WANT_MAXHP_PCT * 100.0],
					absf(dealt - float(want_dmg)) < 1.5)
				_chk("③ 第%d个 被削甲(def_shred_until 在未来)" % (k + 1),
					float(foes[k].get("def_shred_until", 0.0)) > s._t)
	print("     气波节点在 t=%.2fs 出现 (蓄力 %.2fs 之后 —— 小龟先单独现身)" % [fired_at, ts.WAVE_WINDUP])
	_chk("③ ★气波在蓄力结束后才出现(不是与小龟同帧)", fired_at >= ts.WAVE_WINDUP - 0.02)
	_chk("③ 三个全命中(贯穿)", seen.size() == 3)
	_chk("③ ★同一敌人只吃一次(不许每帧重复打)",
		int(foes[0].get("_wave_hit_n", 0)) == 1 and int(foes[1].get("_wave_hit_n", 0)) == 1
		and int(foes[2].get("_wave_hit_n", 0)) == 1,
		"次数 %d/%d/%d" % [int(foes[0].get("_wave_hit_n", 0)), int(foes[1].get("_wave_hit_n", 0)), int(foes[2].get("_wave_hit_n", 0))])

	# ── ④ ★能躲: 蓄力期闪开 → 一发不中 ──
	for k in range(3):
		foes[k]["hp"] = 4000.0
		foes[k]["_wave_hit_n"] = 0
	ts._whistle_spirit_wave(tr)
	var t1: float = s._t
	for step in range(400):
		s._t = t1 + float(step + 1) * (1.0 / 60.0)
		if step == 10:                      # 蓄力期(0.55s=33帧)内就闪开
			for k in range(3):
				foes[k]["pos"] = tr["pos"] + Vector2(300.0 + 300.0 * float(k), 900.0)
		ts._tick_wave_flights(1.0 / 60.0)
	var hits: int = int(foes[0].get("_wave_hit_n", 0)) + int(foes[1].get("_wave_hit_n", 0)) + int(foes[2].get("_wave_hit_n", 0))
	print("")
	print("  ④ 蓄力期侧移 900 码后: 总命中 %d (需求 0 = 真能躲)" % hits)
	_chk("④ ★★蓄力期躲开就打空(这才叫 skillshot)", hits == 0)

	# ── ⑤ 死演出函数不许回来(钩锁那个坑: 留着会让 VFXPREVIEW 指过去 = 无效目视验证) ──
	var src := FileAccess.get_file_as_string("res://scripts/systems/trainer/trainer_system.gd")
	print("")
	_chk("⑤ ★旧的 _whistle_spirit_dramatize 已删",
		not src.contains("func _whistle_spirit_dramatize("))
	_chk("⑤ 判定不靠 tween(逐帧推进函数在位)", src.contains("func _tick_wave_flights("))
	_chk("⑤ 纯效果抽成独立函数(门禁可直接调·不等飞到)", src.contains("func _wave_apply("))
	var rb := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_chk("⑤ ★主循环真的每帧调 _tick_wave_flights(否则气波永远不动)",
		rb.contains("_trainer_sys._tick_wave_flights(dt)"))
	# ★素材不许复用(用户铁律) —— chiwave-fly.png 是【小龟龟派气波】的素材,
	#   而且它本体是橙红火球, 与"灵体小龟的青蓝气波"完全不搭(注释一路写"蓝气波"骗了我一轮)。
	_chk("⑤ ★气波用本技能专属素材 spirit-wave.png(不复用小龟的 chiwave-fly)",
		src.contains("vfx/spirit-wave.png") and not src.contains("vfx/chiwave-fly.png"))
	_chk("⑤ ★分母: 该素材真在磁盘上(缺图会 push_warning 后不画 → 下面全是空检查)",
		ResourceLoader.exists("res://assets/sprites/vfx/spirit-wave.png"))
	_chk("⑤ 气波尺寸走常量 WAVE_D_M(不再是 (150*WS)/128 那个魔数=3.60m 盖住小龟)",
		src.contains("WAVE_D_M / float(") and not src.contains("(150.0 * battle.WS) / 128.0"))

	_done(s)


func _has(s, f: String) -> bool:
	for c in s._world.get_children():
		if c is Sprite3D and (c as Sprite3D).texture != null \
			and str((c as Sprite3D).texture.resource_path).ends_with(f):
			return true
	return false


func _chk(what: String, ok: bool, extra: String = "") -> void:
	if not ok:
		_fail += 1
	print("     %s %s%s" % ["[PASS]" if ok else "[FAIL]", what, ("  " + extra) if extra != "" else ""])


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 口哨②灵体气波·真 skillshot" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
