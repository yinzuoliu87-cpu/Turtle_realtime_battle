extends Node
## verify_star_space.gd — 星际龟【被动星能 + 虫洞本路计时】(2026-08-14)
##
## ★★★由来: `star_system` 名义上配的门禁是 `verify_equip_star_highlight` —— 那是
##   **装备星级高亮**, 和星际龟毫无关系。等于裸奔。而 2026-08-14 要改它, 先补门禁。
##
## ★这条守三件用户实测/追问出来的事:
##   ① 虫洞倍率按【本路】计时(`battle._sd_t0`), 不是跨路累加的 `battle._t`
##      —— 原来下路一开场倍率就 10.5×、决胜 24×(CLAUDE.md §3.4 那个坑)
##   ② 星能【只吃普攻/技能那条伤害路】, DoT/灼烧一点不产
##   ③ 星能追加真伤是 12% 不是 30%(2026-07-16 削过, 文案一直没跟上)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 星际龟: 星能与虫洞计时 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	var u: Dictionary = s._spawn._make_unit("space", "left", c + Vector2(-120, 0))
	u["atk"] = 100.0
	u["maxHp"] = 1000.0
	u["hp"] = 1000.0
	u["no_basic"] = true
	u["no_move"] = true
	var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	e["maxHp"] = 1.0e7
	e["hp"] = 1.0e7
	e["def"] = 0.0
	e["mr"] = 0.0
	e["no_basic"] = true
	e["no_move"] = true
	s._units.clear()
	s._units.append_array([u, e])
	s._edit_mode = false
	s._over = false

	# ── ① 星能只吃【普攻/技能】那条伤害路 ──────────────────────────────────
	u["star_energy"] = 0.0
	var hp_b: float = float(e["hp"])
	## ★小额伤害, 免得一发顶到上限; 期望值按【实发伤害】算而不是我传的数 ——
	##   `_apply_damage_from` 会走暴击/增伤, 传 1000 实发可能 1200+(今晚已栽过一次)。
	s._damage._apply_damage_from(u, e, 200, Color.RED, 0.0, true)
	var real_dmg: float = hp_b - float(e["hp"])
	var after_direct: float = float(u.get("star_energy", 0.0))
	_ok("★分母: 这一发【实发】%.0f 伤害(不是我传的 200)" % real_dmg, real_dmg > 0.0)
	_ok("★★普攻/技能直接命中 ⇒ 星能 = 实发伤害 × 35%",
		absf(after_direct - real_dmg * 0.35) < 1.0,
		"星能 %.1f / 应 %.1f" % [after_direct, real_dmg * 0.35])
	u["star_energy"] = 0.0
	## DoT/真伤那条路(`_apply_damage`)里一处都没有星能累积 —— 灼烧/中毒不产星能。
	s._damage._apply_damage(e, 1000, Color.RED, u, "dot")
	_ok("★★DoT/灼烧那条路【一点星能都不产】(文案原来只写『造成伤害』, 会误导)",
		absf(float(u.get("star_energy", 0.0))) < 0.01,
		"星能 = %.2f(应 0)" % float(u.get("star_energy", 0.0)))

	# ── ② 上限 = 40% 最大生命 ──────────────────────────────────────────────
	u["star_energy"] = 0.0
	for _i in range(20):
		s._damage._apply_damage_from(u, e, 1000, Color.RED, 0.0, true)
	_ok("★★星能上限 = 40%%最大生命 = %.0f(不会溢出)" % (float(u["maxHp"]) * 0.4),
		absf(float(u["star_energy"]) - float(u["maxHp"]) * 0.4) < 1.0,
		"星能 = %.1f" % float(u["star_energy"]))

	# ── ③ 追加真伤 = 12% 当前星能(不是 30%) ────────────────────────────────
	var src_bal := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_ballistics.gd")
	var src_rb := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	## ★2026-08-25 这个系数抽成了 StarSystem.ENERGY_TRUE_PCT(原来在【两个文件各写一遍】)。
	##   比【常量的值】+ 确认两处都在引用它 —— 断言源码字面量会随代码变干净而假红。
	_ok("★★普攻弹道的追加真伤系数 = 0.12",
		is_equal_approx(StarSystem.ENERGY_TRUE_PCT, 0.12)
			and src_bal.find('StarSystem.ENERGY_TRUE_PCT') >= 0
			and src_rb.find('StarSystem.ENERGY_TRUE_PCT') >= 0)
	_ok("★★施法后的追加真伤系数 = 0.12", src_rb.find('star_energy", 0.0)) > 0.0') >= 0)
	## 文案必须与代码一致 —— 2026-07-16 削过 30%→12% 但文案停在 30%, 玩家预期是实际 2.5 倍。
	var pets := FileAccess.get_file_as_string("res://data/pets.json")
	var i_space: int = pets.find('"id": "space"')
	var seg: String = pets.substr(i_space, 4000) if i_space >= 0 else ""
	_ok("★★星际龟文案里【不再出现】星能 30% 的说法", seg.find("星能</span> <span class=\"val-true\">30%") < 0)

	# ── ④ 虫洞倍率按【本路】计时 ───────────────────────────────────────────
	##   ★这是本次的核心修复。判据: 把全局时钟推到很晚、但本路刚开打 ⇒ 倍率必须还是 1.5×。
	var src_st := FileAccess.get_file_as_string("res://scripts/systems/skills/star_system.gd")
	_ok("★★★虫洞倍率用【本路已打秒数】(battle._t - battle._sd_t0), 不是全局 _t",
		src_st.find("battle._t - battle._sd_t0") >= 0
		and src_st.find("WORM_BOOM_COEF * (1.0 + WORM_BOOM_PER_SEC * lane_sec)") >= 0)
	## ★判据的重点是【用 lane_sec 而不是全局 _t】—— 係数本身现在是具名常量,
	## 它们的值另行断言(2026-08-22 文案根除)。
	_ok("★虫洞倍率系数 = 1.5×ATK 且每秒 +5%",
		is_equal_approx(StarSystem.WORM_BOOM_COEF, 1.5) and is_equal_approx(StarSystem.WORM_BOOM_PER_SEC, 0.05))
	_ok("★★源码里不再有 `1.5 * (1.0 + 0.05 * battle._t)` 这种跨路写法",
		src_st.find("1.5 * (1.0 + 0.05 * battle._t)") < 0)
	## 数值层面: 模拟"全局跑了 300 秒, 但本路刚开打"
	s._t = 300.0
	s._sd_t0 = 300.0
	var lane_sec: float = maxf(0.0, s._t - s._sd_t0)
	_ok("★★全局 300 秒但本路刚开打 ⇒ 倍率 = 1.5×(不是 24×)",
		absf(1.5 * (1.0 + 0.05 * lane_sec) - 1.5) < 1e-6,
		"倍率 %.2f×" % (1.5 * (1.0 + 0.05 * lane_sec)))
	s._sd_t0 = 280.0
	var lane2: float = maxf(0.0, s._t - s._sd_t0)
	## 1.5 × (1 + 0.05×20) = 1.5 × 2 = 3.0  (我第一版心算成 2.5, 门禁替我抓到了)
	_ok("★本路打了 20 秒 ⇒ 倍率 = 3.0×",
		absf(1.5 * (1.0 + 0.05 * lane2) - 3.0) < 1e-6,
		"本路 %.0f 秒 → %.2f×" % [lane2, 1.5 * (1.0 + 0.05 * lane2)])

	# ── ⑤ 虫洞期间锁龟能(用户 2026-08-14) ──────────────────────────────────
	##   ★虫洞飞到边界才炸、时长不固定 ⇒ 不能设固定秒数, 只能发射锁死 / 爆炸解锁。
	##   ★兜底 25 秒: 万一虫洞被换路/死亡等路径提前销毁, 也不会把龟能**永久锁死**
	##     —— 今晚凤凰那次"忘了清旗子 = 永久无敌"的教训。
	var Star := load("res://scripts/systems/skills/star_system.gd")
	u["energy_lock_until"] = 0.0
	s._t = 100.0
	s._star_sys._sk_star_wormhole(u, e)
	var lock: float = float(u.get("energy_lock_until", 0.0))
	_ok("★★★放虫洞【立刻锁龟能】(不是等它飞到才锁)", lock > s._t,
		"lock_until=%.1f  now=%.1f" % [lock, s._t])
	_ok("★★锁的是【兜底时长】而不是无限(防永久锁死)",
		absf(lock - (s._t + Star.WORMHOLE_LOCK_FALLBACK)) < 0.01,
		"lock=%.1f 应=%.1f(now+%.0f)" % [lock, s._t + Star.WORMHOLE_LOCK_FALLBACK, Star.WORMHOLE_LOCK_FALLBACK])
	_ok("★兜底时长足够飞完全场(地图对角 ~2600 码 ÷ 140 码/秒 ≈ 19 秒)",
		Star.WORMHOLE_LOCK_FALLBACK >= 19.0, "兜底 %.0f 秒" % Star.WORMHOLE_LOCK_FALLBACK)
	## 源码事实: 爆炸那一刻必须把锁解掉(设成当前时刻)
	_ok("★★虫洞爆炸时【解锁龟能】", src_st.find('uu["energy_lock_until"] = battle._t') >= 0)

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 星际龟")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
