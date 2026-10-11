extends Node
## verify_spirit_synergy_dodge.gd —— 灵物羁绊「每件灵物 +N% 闪避率」要真的进到判定读的 dodge_bonus(2026-10-11 全项目通读第二条)
##
## ★读码疑点: `synergy_system._add` 把 dodgePct 写进 `u["dodge"]`, 而闪避判定(battle_damage)只读
##   `dodge_bonus`, `dodge_bonus` 的唯一写入点 `_recalc_stats` 只累加 stat=="dodge" 的 buff。
##   第一条(攻速)读码结论被探针推翻过 ⇒ 这条也只认量出来的数: 走产品的 `_apply_to`, 量 `dodge_bonus`。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/gamedata/equip_stats.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物羁绊闪避 ⇒ dodge_bonus ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var spirit_id := ""
	for k in ES.STATS:
		if s.Phase2Types.type_of(str(k)) == "灵物" and not (ES.STATS[k][0] as Dictionary).has("dodgePct"):
			spirit_id = str(k)
			break
	_ok("★分母: 找到一件本身不带闪避的灵物装备", spirit_id != "", spirit_id)
	var per: float = float((s.Phase2Types.TYPES["灵物"]["stats"][0] as Dictionary)["dodgePct"]) / 100.0
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c)
	u["equips"] = [{"id": spirit_id, "star": 1}, {"id": spirit_id, "star": 1}]
	s._recalc_stats(u)
	var before: float = float(u.get("dodge_bonus", 0.0))
	s._synergy._apply_to(u, {"灵物": 1})
	var after: float = float(u.get("dodge_bonus", 0.0))
	_ok("★★2 件灵物 × 第 1 档 %.0f%% ⇒ dodge_bonus 涨 %.0f%%" % [per * 100.0, per * 200.0],
		absf((after - before) - per * 2.0) < 1e-4, "dodge_bonus %.3f → %.3f" % [before, after])
	s._recalc_stats(u)
	_ok("★再重算一次属性(换装/上 buff 都会触发)后仍在", absf(float(u.get("dodge_bonus", 0.0)) - after) < 1e-4,
		"%.3f" % float(u.get("dodge_bonus", 0.0)))

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
