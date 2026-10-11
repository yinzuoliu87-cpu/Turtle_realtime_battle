extends Node
## verify_star_delta_matches_apply.gd —— 财神招财临时装备升星的「差量」= 直接装那个星级(2026-10-11 全项目通读 A6)
##
## ★读码发现: `_eq_star_delta_stats` 是 `apply_stat_dict` 的手抄子集, 只处理 11 个老字段,
##   漏攻速/移速/射程/反伤/闪避/治疗增幅/护盾增幅 ⇒ 临时装备升到 2★/3★ 后这些仍是 1★, 面板却按 3★ 显示。
## ★判据: 装备表里每一件, 「装 1★ 再升到 3★」与「直接装 3★」在全部属性字段上逐个相等。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const FIELDS := ["base_atk", "maxHp", "crit", "armor_pen", "magic_pen", "lifesteal", "base_def", "base_mr", "crit_dmg",
	"init_energy_bonus", "echarge_perm", "aspd_perm", "move_perm", "range_perm", "range_add", "reflect",
	"heal_amp", "shield_amp", "dodge_bonus"]

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 临时装备升星差量 = 直接装 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var ap = s._equip_sys._stats
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var checked := 0
	var bad: Array = []
	for iid in s.EquipStats.STATS:
		var arr: Array = s.EquipStats.STATS[iid]
		if arr.size() < 3:
			continue
		var u1: Dictionary = s._spawn._make_unit("basic", "left", c)
		var u3: Dictionary = s._spawn._make_unit("basic", "left", c)
		ap.apply_stat_dict(u1, arr[0], str(iid))
		ap._eq_star_delta_stats(u1, str(iid), 1, 3)
		ap.apply_stat_dict(u3, arr[2], str(iid))
		checked += 1
		s._recalc_stats(u1)
		s._recalc_stats(u3)
		for f in FIELDS:
			var dflt: float = 1.0 if str(f).ends_with("_perm") else 0.0   # *_perm 缺省 = 1.0(乘区)
			if absf(float(u1.get(f, dflt)) - float(u3.get(f, dflt))) > 1e-4:
				bad.append("%s.%s %.3f≠%.3f" % [iid, f, float(u1.get(f, dflt)), float(u3.get(f, dflt))])
	_ok("★分母: 比了 %d 件三星装备" % checked, checked >= 50)
	_ok("★★「装 1★ 再升 3★」与「直接装 3★」全字段一致", bad.is_empty(), "%d 处不一致: %s" % [bad.size(), str(bad.slice(0, 6))])
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
