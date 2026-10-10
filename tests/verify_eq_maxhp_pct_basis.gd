extends Node
## verify_eq_maxhp_pct_basis.gd — 装备/羁绊「X% 自身最大生命值」按【真实 maxHp】算, 不除 HP_MULT
##
## 起因(2026-10-04): 047 重击锤 / 039 竹箭 / 020 哑铃 / 盾羁绊冲击波的代码都写成
##   `maxHp / HP_MULT × pct` —— 早期 ×3 血量缩放的遗留, 实发只有文案的 1/3;
##   而 079 珊瑚急救塔、039 自己的回血那一半都是按真实 maxHp 算的, 同一句文案两种口径。
##   用户原话:「肯定是代码去掉除以3啊」「不需要列表给我看，强度都输没问题的」。
##   ⇒ 文案一直是对的, 改的是代码。CLAUDE.md §3.1 同步改成「HP_MULT 只用于召唤物 raw 值」。
##
## ★期望值一律写成【文案字面量 × 真实 maxHp】, 不读被测常量(百分比写死在本文件里)。
## ★再加一条静态扫描: scripts/ 与 autoload/ 的代码行里不许再出现 `/ HP_MULT` 这种除法。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 文案字面量(data/phase2-equipment.json 与 盾羁绊文案, 2026-10-04)
const TXT_HAMMER_PCT_3 := 0.08      # 047「获得 4/6/8% 自身最大生命值的攻击力」3★(2026-10-10 15%→8%)
const TXT_BAMBOO_FLAT_3 := 35       # 039「（25/30/35 + 6% 自身最大生命值）魔法伤害」3★
const TXT_BAMBOO_PCT := 0.06
const TXT_WAVE_PCT_3 := 0.08        # 盾羁绊冲击波「自身最大生命的 4/6/8%」第 3 档
const TXT_DUMBBELL_PCT_3 := 0.10    # 020「5/7/10% 自身最大生命值的物理伤害」3★
const TXT_DUMBBELL_GAIN_3 := 110.0  # 020「每层最大生命值与当前生命 +40/75/110」(投掷前先加)
const MHP := 2000.0

var _s
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(px: float, py: float, side: String, mhp: float) -> Dictionary:
	## ★不用 "basic": 小龟【不屈】被动按稀有度增伤 +20%(battle_damage.gd), 会混进测量(同 verify_shield_synergy)
	var u: Dictionary = _s._spawn._make_unit("green", side, Vector2(px, py))
	u["hp"] = mhp
	u["maxHp"] = mhp
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0
	u["equips"] = []
	u["eq_state"] = {}
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 装备「X% 最大生命」口径 = 真实 maxHp ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	# ── ① 047 重击锤 3★: ATK 增量 == maxHp × 8%(2026-10-10 15%→8%) ──
	_s._units.clear()
	var c1: Dictionary = _mk(500.0, 400.0, "left", MHP)
	c1["equips"] = []; c1["eq_state"] = {}; c1["hammer_pct"] = 0.0
	_s._units.append(c1)
	_s._recalc_stats(c1)
	var atk0: float = float(c1["atk"])
	var mhp1: float = float(c1["maxHp"])
	c1["hammer_pct"] = TXT_HAMMER_PCT_3
	_s._recalc_stats(c1)
	var got1: float = float(c1["atk"]) - atk0
	_ok("① 分母: 重击锤 maxHp=%.0f" % mhp1, mhp1 > 100.0)
	_ok("① 047 3★ ATK 增量 %.1f == 真实maxHp %.0f × 8%% = %.1f" % [got1, mhp1, mhp1 * TXT_HAMMER_PCT_3],
		absf(got1 - mhp1 * TXT_HAMMER_PCT_3) < 1.0, "若是 %.1f 就是又除了 3" % (mhp1 * TXT_HAMMER_PCT_3 / 3.0))

	# ── ② 039 竹箭 3★: 强化竹箭伤害 == 35 + maxHp × 6% ──
	_s._units.clear()
	var c2: Dictionary = _mk(500.0, 400.0, "left", MHP)
	c2["equips"] = [{"id": "p2eq_039", "star": 3}]
	_s._units.append(c2)
	_s._equip_sys._stats._eq_apply_one_stats(c2, "p2eq_039", 3)
	var foe2: Dictionary = _mk(700.0, 400.0, "right", 90000.0)
	_s._units.append(foe2)
	var mhp2: float = float(c2["maxHp"])
	var np0: int = _s._projectiles.size()
	for _k in range(3):
		_s._equip_sys._eq_on_basic_attack(c2, foe2)
	var arrow = null
	for i in range(np0, _s._projectiles.size()):
		if bool(_s._projectiles[i].get("bamboo", false)):
			arrow = _s._projectiles[i]
	_ok("② 分母: 第 3 段普攻射出了强化竹箭", arrow != null, "新增弹道 %d" % (_s._projectiles.size() - np0))
	if arrow != null:
		var want2: int = TXT_BAMBOO_FLAT_3 + int(mhp2 * TXT_BAMBOO_PCT)
		_ok("② 039 3★ 竹箭伤害 %d == 35 + 真实maxHp %.0f × 6%% = %d" % [int(arrow["dmg"]), mhp2, want2],
			int(arrow["dmg"]) == want2)

	# ── ③ 盾羁绊冲击波(第 3 档): 真伤 == maxHp × 8% ──
	_s._units.clear()
	var c3: Dictionary = _mk(500.0, 400.0, "left", MHP)
	var foe3: Dictionary = _mk(700.0, 400.0, "right", 100000.0)
	_s._units.append(c3); _s._units.append(foe3)
	var mhp3: float = float(c3["maxHp"])
	_s._shield_syn._shockwave(c3, 3)
	var got3: float = 100000.0 - float(foe3["hp"])
	_ok("③ 盾冲击波 第3档 真伤 %.0f == 真实maxHp %.0f × 8%% = %d" % [got3, mhp3, int(mhp3 * TXT_WAVE_PCT_3)],
		absf(got3 - float(int(mhp3 * TXT_WAVE_PCT_3))) < 1.0)

	# ── ④ 020 哑铃 3★: 砸中物理伤害(0 护甲) == (maxHp + 110) × 10% ──
	_s._units.clear()
	var c4: Dictionary = _mk(500.0, 400.0, "left", MHP)
	c4["eq_state"] = {}
	var foe4: Dictionary = _mk(700.0, 400.0, "right", 100000.0)
	_s._units.append(c4); _s._units.append(foe4)
	var mhp4: float = float(c4["maxHp"])
	_s._equip_sys._eq_dumbbell_routine(c4, 2)
	for _k in range(60):
		_s._sim_step(_s.SIM_DT, false, false)
		if float(foe4["hp"]) < 100000.0:
			break
	var got4: float = 100000.0 - float(foe4["hp"])
	var want4: int = int((mhp4 + TXT_DUMBBELL_GAIN_3) * TXT_DUMBBELL_PCT_3)
	_ok("④ 分母: 哑铃砸中了(敌掉血 > 0)", got4 > 0.0)
	_ok("④ 020 3★ 哑铃伤害 %.0f == (真实maxHp %.0f + 110) × 10%% = %d" % [got4, mhp4, want4],
		absf(got4 - float(want4)) < 1.0)

	# ── ⑤ 静态: 代码行里不许再有 `/ HP_MULT` ──
	var re := RegEx.new()
	re.compile("/\\s*([A-Za-z_]+\\.)?HP_MULT\\b")
	var files: Array = []
	_collect("res://scripts", files)
	_collect("res://autoload", files)
	var bad: Array = []
	for p in files:
		var txt: String = FileAccess.get_file_as_string(p)
		var ln := 0
		for line in txt.split("\n"):
			ln += 1
			if line.strip_edges().begins_with("#"):
				continue
			if re.search(line) != null:
				bad.append("%s:%d" % [p, ln])
	_ok("⑤ 分母: 扫了 %d 个 .gd" % files.size(), files.size() > 50)
	_ok("⑤ 代码里没有 `/ HP_MULT`(装备 % 最大生命按真实 maxHp)", bad.is_empty(), ", ".join(bad))

	print("ALL PASS — %d 项" % _n if _fail == 0 else "FAILED: %d / %d" % [_fail, _n])
	_s.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)
