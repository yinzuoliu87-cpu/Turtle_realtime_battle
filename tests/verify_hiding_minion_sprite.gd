extends Node
## #20 缩头龟召出的随从: 待机贴图 = 这只龟本体同一套(pets.json img), 尺寸归一同本体(用户 2026-11-07
##   「有的时候会卡 bug，有的时候是旧出现旧形象」)。
## 根因: 随从走召唤通用路 `_resolve_summon_sprite(pick)` 读旧全身图 pets/<id>.png, 随后 id 改成这只龟, 动作走新帧条
##   ⇒ 待机旧图、动作新图, 大小也不一致。
## 判据走真入口 `_spawn_hiding_minion`(随机挑哪只由本局 _battle_rng 定 ⇒ 换几个种子各生一次, 每只都核):
##   ① 随从待机表(idle_sd)贴图路径 == res://assets/sprites/ + pets.json 里这只龟的 img
##   ② idle_px == TARGET_BODY_H / 帧高(与本体同一归一)
##   ③ 不是旧全身图 pets/<id>.png

var _fail := 0


func _chk(name: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s%s" % ["PASS" if ok else "FAIL", name, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(4):
		await get_tree().process_frame
	print("=== #20 缩头随从待机贴图 = 本体同一套 ===")
	var n := 0
	var seen := {}
	for sd in [11, 23, 37, 41, 59, 73]:
		s._battle_rng.seed = sd
		var host: Dictionary = s._spawn._make_unit("hiding", "left", s.ARENA.position + s.ARENA.size * 0.5, {})
		s._units.append(host)
		var before: int = s._units.size()
		s._spawn._spawn_hiding_minion(host)
		var m = null
		for i in range(before, s._units.size()):
			if str(s._units[i].get("minion_kind", "")) != "":
				m = s._units[i]
		if m == null:
			_chk("分母: 种子 %d 生出了随从" % sd, false)
			continue
		var pick: String = str(m["minion_kind"])
		seen[pick] = true
		n += 1
		var img: String = str((s._data_by_id.get(pick, {}) as Dictionary).get("img", ""))
		var want: String = "res://assets/sprites/" + img
		## 查单位记着的待机表(idle_sd): 有登场动作的龟(钻石 / 海盗…)生成那一刻正在播 enter.png, 播完由渲染切回 idle_sd
		var isd: Dictionary = m.get("idle_sd", {})
		var it = isd.get("tex", null)
		var got: String = str((it as Texture2D).resource_path) if it != null else ""
		_chk("① %s 随从待机贴图 = pets.json img" % pick, img != "" and got == want, "%s vs %s" % [got, want])
		var fh: int = int(isd.get("frame_h", 0))
		_chk("② %s 尺寸归一同本体(idle_px = 2.0 / 帧高 %d)" % [pick, fh],
			fh > 0 and absf(float(m.get("idle_px", 0.0)) - 2.0 / float(fh)) < 1.0e-6, "idle_px %.5f" % float(m.get("idle_px", 0.0)))
		_chk("③ %s 不是旧全身图 pets/%s.png" % [pick, pick], not got.ends_with("pets/%s.png" % pick), got)
		m["alive"] = false
		host["alive"] = false
	_chk("分母: 生出 %d 个随从、%d 种龟" % [n, seen.size()], n >= 6 and seen.size() >= 2, str(seen.keys()))
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — #20 缩头随从待机贴图" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
