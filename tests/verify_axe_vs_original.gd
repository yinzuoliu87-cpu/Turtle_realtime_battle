extends Node
## verify_axe_vs_原话.gd — 拿【用户原话】逐条对实现 (2026-09-01)
##
## ══════════════════════════════════════════════════════════════════
##  ★为什么要有这一份
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-01：「我要你一句句看我的原话，到底有多少东西做失败了」。
##
## 我此前的门禁都是**对着我自己的实现**写的 —— 我实现了什么就验什么，
## 于是「原话里有、我没实现」的那些**根本不会被任何门禁提到**。
## 逐条对完抓到 6 条做失败的：
##   ① 「一层效率提供…**2%移动速度**」   → 常量在表里、**零消费者**
##   ② 「余烬…**这期间不会锁龟能**」      → **完全没做**
##   ③ 「全息斧…**50%龟能充能速率**」    → 数值表里躺着、**零消费者**
##   ④ 「**免疫控制**」                  → 我写 `cc_immune`，引擎读 `cc_immune_until`
##                                        ⇒ 全仓没人读我写的那个字段，免控**根本不生效**
##   ⑤/⑥ 见下方逐条断言
##
## ★★这份门禁的判据**落在原话的字面上**，不落在我的实现上：
##   每条断言的名字就是原话的一句，做不到就红。这样"原话里有、我没做"也会被抓。
##
## ★原话全文存档：docs/plans/20260831-用户原话-小木斧.txt（sha1 焊在下面）
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const ORIG := "res://docs/plans/20260831-用户原话-小木斧.txt"

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _mk(final_key: String) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "left", c)
	_s._units.append(u)
	u["_eq_axe"] = true
	u["_axe_pv"] = 4
	u["_axe_final"] = final_key
	u["id"] = "__probe__"
	u["maxHp"] = 10000.0
	u["hp"] = 5000.0
	u["maxEnergy"] = 1000.0
	u["energy"] = 0.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 拿用户原话逐条对实现 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── ★分母: 原话存档还在, 且没被人改过 ──
	var txt: String = FileAccess.get_file_as_string(ORIG) if ResourceLoader.exists(ORIG) \
		else (FileAccess.get_file_as_string(ORIG) if FileAccess.file_exists(ORIG) else "")
	_ok("★分母: 用户原话存档读得到(%d 字) —— 读不到的话下面全是空对照" % txt.length(),
		txt.length() > 1900)
	_ok("★分母: 存档确实是那一份(含「小木斧（1费）」与「余烬之光」两处锚点)",
		txt.contains("小木斧（1费）") and txt.contains("余烬之光"))

	_t_missed(txt)

	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12)" % _n)
		_fail += 1
	print("ALL PASS — 原话逐条对照(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ★这六条是逐条对照时**抓到做失败的** —— 每条的名字就是原话那一句
# ══════════════════════════════════════════════════════════════
func _t_missed(txt: String) -> void:
	print("--- 逐条对照(原话 → 实现) ---")
	var pas = _s._equip_sys._axe._pas
	var fin = _s._equip_sys._axe._fin

	# ① 「一层效率提供4%攻击速度和2%移动速度」
	_ok("★分母: 原话里确实写着「一层效率提供4%攻击速度和2%移动速度」",
		txt.contains("一层效率提供4%攻击速度和2%移动速度"))
	var ax: Dictionary = _mk("")
	ax["_axe_pv"] = 3
	pas.add_eff(ax)
	pas.add_eff(ax)
	_ok("★★2 层效率 → 移速 ×%.2f 真的写进了移动通道(move_buff_mult)"
		% AE.eff_move_mult(2),
		is_equal_approx(float(ax.get("move_buff_mult", 1.0)), AE.eff_move_mult(2))
		and float(ax.get("move_buff_until", 0.0)) > _s._t,
		"实测 %.3f" % float(ax.get("move_buff_mult", -1.0)))
	## ★分母: 移动公式真的在读这个字段(不读的话上面那条是空的)
	var rb_src: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★★分母: 主场景移动公式真的乘了 move_buff_mult(不读 = 写了也没用)",
		rb_src.contains("move_buff_mult"))

	# ② 「这期间不会锁龟能」
	_ok("★分母: 原话里确实写着「这期间不会锁龟能」", txt.contains("这期间不会锁龟能"))
	var ex: Dictionary = _mk("ember")
	ex["energy_lock_until"] = _s._t + 999.0        # 先被别的机制锁上
	fin.ember_light_cast(ex)
	_ok("★★余烬之光期间【龟能锁被解开】(锁 999 秒 → %.1f)"
		% float(ex.get("energy_lock_until", -1.0)),
		float(ex.get("energy_lock_until", 1.0)) <= _s._t)
	_ok("★★分母: 引擎的龟能 tick 真的读 energy_lock_until", rb_src.contains("energy_lock_until"))

	# ③ 「50%龟能充能速率」
	_ok("★分母: 原话里确实写着「50%龟能充能速率」", txt.contains("50%龟能充能速率"))
	var hx: Dictionary = _mk("")
	fin.apply_stats(hx, "holo")
	_ok("★★全息斧的充能速率写进了引擎真读的 echarge_perm(×%.2f)"
		% (1.0 + AF.stat("holo", "energy_rate_pct")),
		is_equal_approx(float(hx.get("echarge_perm", 1.0)),
			1.0 + AF.stat("holo", "energy_rate_pct")),
		"实测 %.3f" % float(hx.get("echarge_perm", -1.0)))
	_ok("★★分母: 引擎冷却推进真的乘了 echarge_perm", rb_src.contains("echarge_perm"))

	# ④ 「免疫控制」—— 字段名写错过
	_ok("★分母: 原话里确实写着「免疫控制」", txt.contains("免疫控制"))
	var cx: Dictionary = _mk("ember")
	fin.ember_light_cast(cx)
	_ok("★★免控写进了引擎真读的 cc_immune_until(而不是我编的 cc_immune)",
		float(cx.get("cc_immune_until", 0.0)) > _s._t,
		"实测 %.2f (现在 %.2f)" % [float(cx.get("cc_immune_until", 0.0)), _s._t])
	var dmg_src: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_damage.gd")
	_ok("★★分母: 引擎的眩晕/免控真的读 cc_immune_until", dmg_src.contains("cc_immune_until"))
	## ★真走一次眩晕入口: 挂着余烬之光时 `_stun` 不许生效
	cx["stun_until"] = 0.0
	_s._damage._stun(cx, 3.0, "probe")
	_ok("★★★走真入口 `_stun()` 也眩晕不了它(只验字段写对 ≠ 引擎真的挡住)",
		float(cx.get("stun_until", 0.0)) <= _s._t,
		"stun_until=%.2f" % float(cx.get("stun_until", 0.0)))

	# ⑤ 「80%攻击速度和20%移速」(余烬) —— 移速走 move_perm, 与效率层不是同一条通道
	_ok("★分母: 原话里确实写着余烬的「80%攻击速度和20%移速」",
		txt.contains("80%攻击速度和20%移速"))
	var mx: Dictionary = _mk("")
	fin.apply_stats(mx, "ember")
	_ok("★★余烬的 +%.0f%% 移速写进了 move_perm(引擎移动公式读它)"
		% (AF.stat("ember", "move_pct") * 100.0),
		is_equal_approx(float(mx.get("move_perm", 1.0)), 1.0 + AF.stat("ember", "move_pct")),
		"实测 %.3f" % float(mx.get("move_perm", -1.0)))

	# ⑥ 「300码射程」(炽天使) —— 是设成不是加
	_ok("★分母: 原话里确实写着「300码射程」", txt.contains("300码射程"))
	var sx: Dictionary = _mk("")
	sx["atk_range"] = 120.0
	fin.apply_stats(sx, "seraph")
	_ok("★炽天使射程**设成** 300 而不是加到 420",
		is_equal_approx(float(sx.get("atk_range", 0.0)), 300.0),
		"实测 %.0f" % float(sx.get("atk_range", -1.0)))
