extends Node
## verify_headless_rage_once.gd —— 无头龟「亡灵怒: 每损 1% 生命攻击 +1%(上限 +100%)」只许算一次、不许冲掉 buff
##   (2026-10-11 全项目通读第六条)
##
## ★读码疑点: 周期被动已把 `base_atk = 基准 ×(1+损血)` 并重算; `_on_basic_hit` 每次普攻又写
##   `atk = base_atk ×(1+损血)` ⇒ 平方(满损 ×4, 超出文案上限 +100%), 且直接覆盖 atk 冲掉所有攻击 buff/羁绊。
## ★判据: 半血 ⇒ 普攻之后攻击 = 基准 × 1.5 × (buff 倍率), 不是 × 2.25、也不丢 buff。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 无头龟亡灵怒只算一次 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._units.clear()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("headless", "left", c)
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(60, 0))
	foe["maxHp"] = 1.0e6
	foe["hp"] = 1.0e6
	s._units.append(u)
	s._units.append(foe)
	s._edit_mode = false
	s._over = false
	## 正式对局由 battle_spawn(双路 spawn)登场时记下基准; `_make_unit` 那条路不经过它 ⇒ 照它的写法补上
	if float(u.get("headless_base_atk", 0.0)) <= 0.0:
		u["headless_base_atk"] = float(u.get("base_atk", u.get("atk", 0.0)))
	var hb: float = float(u.get("headless_base_atk", 0.0))
	_ok("★分母: 登场记下了亡灵怒基准攻击", hb > 0.0, "%.2f" % hb)
	u["hp"] = float(u["maxHp"]) * 0.5
	s._tick_periodic_passive(u, 0.016)
	var want: float = hb * 1.5
	_ok("★半血 ⇒ 周期被动把攻击抬到基准 ×1.5", absf(float(u["atk"]) - want) < 0.05,
		"atk %.2f 应 %.2f" % [float(u["atk"]), want])
	s._on_basic_hit(u, foe)
	_ok("★★普攻之后仍是 ×1.5(不是 ×2.25)", absf(float(u["atk"]) - want) < 0.05,
		"atk %.2f 应 %.2f(×2.25 = %.2f)" % [float(u["atk"]), want, hb * 2.25])
	s._damage._buff(u, "atk", 0.20, true, 30.0)
	var with_buff: float = float(u["atk"])
	s._on_basic_hit(u, foe)
	_ok("★★挂了 +20% 攻击 buff 后普攻 ⇒ buff 不被冲掉", absf(float(u["atk"]) - with_buff) < 0.05,
		"普攻前 %.2f → 普攻后 %.2f" % [with_buff, float(u["atk"])])

	# ── 亡灵(首次濒死 5 秒免死)两条伤害路径都要触发(CLAUDE.md §3.3) ──
	##   原来只写在 `_apply_damage_from`(普攻/技能); 第一下致命伤来自 DoT/真伤(`_apply_damage`)就直接死。
	for path in ["dot", "hit"]:
		var h: Dictionary = s._spawn._make_unit("headless", "left", c + Vector2(0, 80))
		s._units.append(h)
		h["hp"] = 10.0
		h["undead_used"] = false
		if path == "dot":
			s._damage._apply_damage(h, 500, Color.WHITE, foe)
		else:
			s._damage._apply_damage_from(foe, h, 500, Color.WHITE, 0.0, true)
		_ok("★★亡灵: 第一下致命伤走【%s】那条路 ⇒ 不死、锁 1 血" % ("DoT/真伤 _apply_damage" if path == "dot" else "普攻/技能 _apply_damage_from"),
			bool(h.get("alive", false)) and float(h["hp"]) >= 1.0 and bool(h.get("undead_used", false)),
			"alive=%s hp=%.1f undead_used=%s" % [str(h.get("alive")), float(h["hp"]), str(h.get("undead_used"))])

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
