extends Node
## verify_vfx_tiers.gd — 特效 / 打击感重要度分级表(2026-11-04 · 方案书 docs/plans/20261104b-特效对标商业做法.md P2)
## 学的是 Riot「每个技能 1~10 视觉重要度, 特效按分做」「什么都重要就什么都不重要」。
##   ① 28 龟 × 技能池 112 格全部落在 1~10 档; 至少分出 3 种档位(全落一档 = 空表)
##   ② 档位随龟能消耗单调不降(60 < 100 < 120 < 160)
##   ③ ★真入口 _cast_skill: 大招级(无头龟·万千触须 160)比轻技(天使龟·祝福 80)的放技能声大 2~4.5 dB(档位 1.0 vs 0.7)
##   ④ ★真入口 _apply_damage_from: 普攻命中的火花比技能命中的小一号(0.75 倍)
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_vfx_tiers.tscn --quit-after 2000

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SkillEnergy := preload("res://scripts/systems/skill_energy.gd")   # 没有 class_name, 主场景也是 preload

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	## ① 技能池全覆盖
	var n_slot := 0
	var bad: Array = []
	var seen := {}
	for p in DataRegistry.launch_pets:
		var pool: Array = (p as Dictionary).get("skillPool", [])
		for i in range(pool.size()):
			n_slot += 1
			var tier: int = VfxTiers.BASIC
			if i > 0:
				var st := str((pool[i] as Dictionary).get("type", ""))
				tier = VfxTiers.of_skill(st, SkillEnergy.cost_of(st))
			seen[tier] = true
			if tier < 1 or tier > 10:
				bad.append("%s#%d=%d" % [str((p as Dictionary).get("id", "")), i, tier])
	_ok("① 技能池 %d 格全部落在 1~10 档、至少 3 种档位" % n_slot, n_slot >= 112 and bad.is_empty() and seen.size() >= 3,
		"档位 %s · 越界 %s" % [str(seen.keys()), str(bad)])
	## ② 单调
	var t60: int = VfxTiers.of_skill("_x", 60.0)
	var t100: int = VfxTiers.of_skill("_x", 100.0)
	var t120: int = VfxTiers.of_skill("_x", 120.0)
	var t160: int = VfxTiers.of_skill("_x", 160.0)
	_ok("② 档位随消耗单调: 60→%d · 100→%d · 120→%d · 160→%d" % [t60, t100, t120, t160], t60 < t100 and t100 < t120 and t120 < t160)

	var au = get_node_or_null("/root/Audio")
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene._edit_mode = false
	scene._dl_state = "fight"

	## ③ 放技能声按档位
	if au != null:
		au.mute_sfx = false
		var _sv: float = au.sfx_volume
		au.sfx_volume = 0.8   # 门禁 QUIET 跑时是 0 ⇒ 音量全是 −inf; 量的这两下临时用默认音量
		var vols := {}
		for c in [["headless", "headlessTendrils"], ["angel", "angelBless"]]:
			scene._units.clear()
			scene._t += 10.0
			scene._audio_sys._cast_ts.clear()
			scene._audio_sys._ev_last_t.clear()
			var caster: Dictionary = scene._spawn._make_unit(str(c[0]), "left", Vector2(600, 400))
			var foe: Dictionary = scene._spawn._make_unit("basic", "right", Vector2(700, 400))
			foe["maxHp"] = 1.0e7
			foe["hp"] = 1.0e7
			scene._units.append(caster)
			scene._units.append(foe)
			au.recent.clear()
			scene._cast_skill(caster, foe, str(c[1]))
			vols[c[0]] = _player_db(au, "cast_" + str(c[0]))
		au.sfx_volume = _sv
		var d: float = float(vols["headless"]) - float(vols["angel"])
		_ok("③ ★大招级放技能声比轻技大 2~4.5 dB(真入口 _cast_skill)", d > 2.0 and d < 4.5,
			"万千触须 %.1f dB · 祝福 %.1f dB · 差 %.1f" % [float(vols["headless"]), float(vols["angel"]), d])
	else:
		_ok("③ 分母: Audio 在", false)

	## ④ 普攻火花小一号
	scene._units.clear()
	var src: Dictionary = scene._spawn._make_unit("stone", "left", Vector2(600, 400))
	var tgt: Dictionary = scene._spawn._make_unit("basic", "right", Vector2(680, 400))
	tgt["maxHp"] = 1.0e7
	tgt["hp"] = 1.0e7
	scene._units.append(src)
	scene._units.append(tgt)
	var sizes := {}
	for basic in [true, false]:
		tgt["_spark_t"] = 0.0
		var before: Array = _sparks(scene)
		scene._damage._apply_damage_from(src, tgt, 30, Color.WHITE, 0.0, false, false, false, false, false, basic)
		var ps := -1.0
		for sp in _sparks(scene):
			if not before.has(sp):
				ps = float((sp as Sprite3D).pixel_size)
		sizes[basic] = ps
	_ok("④ ★普攻命中火花比技能命中小(0.75 倍; 真入口 _apply_damage_from)",
		float(sizes[true]) > 0.0 and float(sizes[false]) > 0.0 and absf(float(sizes[true]) / float(sizes[false]) - 0.75) < 0.01,
		"普攻 %.4f · 技能 %.4f" % [float(sizes[true]), float(sizes[false])])

	print("分母: %d 项" % _n)
	if _fail == 0:
		print("ALL PASS — 重要度分级表接上了(放技能声 / 命中火花)")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## Audio 里最后一个播 name 的临时播放器的音量(play_sfx 每次 add_child 一个)
func _player_db(au, name: String) -> float:
	var want = au._sfx_cache.get(name)
	for i in range(au.get_child_count() - 1, -1, -1):
		var c = au.get_child(i)
		if c is AudioStreamPlayer and c.stream != null and c.stream == want:
			return float(c.volume_db)
	return -999.0


func _sparks(scene) -> Array:
	var out: Array = []
	for c in scene._world.get_children():
		if c is Sprite3D and (c as Sprite3D).has_meta("spark_tier"):
			out.append(c)
	return out
