extends Node
## verify_spine_actions.gd — 外包 11 只龟的动作帧(普攻 / 受击 / 阵亡)与待机「同一只龟、同一个大小、同一条脚底线」(2026-11-05)。
##
## 由来: 方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.3。动作帧由 tools/assetgen/build_spine_actions.py 在画师 Spine 原骨骼上渲出,
##   表在 scripts/gamedata/turtle_actions.gd(生成)。这套历史上踩过的病(用户 2026-07-21「大小明显不对」/ 08-22「站立的图片和其他动作完全接不上」):
##   动作帧本体只占半帧 ⇒ 一播就缩; 脚底行不同 ⇒ 一播就上下跳。
## 判据(量需求本身, 不读我自己写的配置当答案):
##   ① 表里每张动作图(普攻 / 受击 / 阵亡 / 每个技能的释放动作)都在, 是方帧条(帧高 = 帧宽), 帧数 ≥ 6
##   ② 每个动作的第 0 帧 = 待机第 0 帧摆进方帧(水平居中、格子底边 = 归一表的脚底行)后**逐像素相同** —— 同一只龟、同一个像素尺度
##   ③ 真场景里生成这 11 只, 播普攻 / 受击 / 阵亡: 精灵 pixel_size 与待机相同、脚底线的本地高度与待机相同(不缩、不跳)
##   ④ 主场景 ACTION_* 表里没有这 11 只(否则旧表会盖掉新表 —— 小龟原来挂着旧形象的三张图)
const TA := preload("res://scripts/gamedata/turtle_actions.gd")
const KINDS := ["attack", "hurt", "death"]

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _pets() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/pets.json"))
	var arr: Array = raw.get("pets", []) if raw is Dictionary else raw
	var out := {}
	for p in arr:
		out[str(p.get("id", ""))] = p
	return out


func _ready() -> void:
	await get_tree().process_frame
	print("=== 外包 11 只龟动作帧 ↔ 待机 ===")
	var pets := _pets()
	var ids: Array = TA.ATTACK.keys()
	ids.sort()
	_ok("★分母: 动作表里有 11 只龟", ids.size() == 11, str(ids))
	## ── ①② 文件 ──
	for id in ids:
		var p: Dictionary = pets.get(id, {})
		var sp: Dictionary = p.get("sprite", {})
		var idle_t: Texture2D = load("res://assets/sprites/" + str(p.get("img", "")))
		_ok("★分母: %s 待机图加载到了" % id, idle_t != null and not sp.is_empty())
		if idle_t == null or sp.is_empty():
			continue
		var fw: int = int(sp["frameW"])
		var fh: int = int(sp["frameH"])
		var idle0: Image = idle_t.get_image().get_region(Rect2i(0, 0, fw, fh))
		idle0.convert(Image.FORMAT_RGBA8)
		var norm: Array = TA.NORM.get(id, [])
		_ok("%s 归一表有这一行" % id, norm.size() == 3)
		if norm.size() != 3:
			continue
		var feet: int = int(norm[1])
		var kinds: Array = KINDS.duplicate()
		for st in (TA.CAST.get(id, {}) as Dictionary):
			kinds.append("cast:" + str(st))
		for kind in kinds:
			var ent: Array = (TA.CAST[id][str(kind).substr(5)] as Array) if str(kind).begins_with("cast:") else TA.by_kind(kind).get(id, [])
			var at: Texture2D = load("res://assets/sprites/" + str(ent[0])) if ent.size() >= 2 else null
			_ok("★分母: %s %s 动作图加载到了" % [id, kind], at != null)
			if at == null:
				continue
			var ai: Image = at.get_image()
			ai.convert(Image.FORMAT_RGBA8)
			var S: int = ai.get_height()
			var nf: int = ai.get_width() / S
			_ok("%s %s 是方帧条, 帧数 ≥ 6" % [id, kind], ai.get_width() % S == 0 and nf >= 6, "%d×%d, %d 帧" % [ai.get_width(), S, nf])
			## 待机格子在方帧里的位置: 水平居中, 底边 = 脚底行
			var ox: int = (S - fw) / 2
			var oy: int = feet - fh
			var diff := 0
			var opaque := 0
			for y in range(S):
				for x in range(S):
					var a: Color = ai.get_pixel(x, y)
					var ix: int = x - ox
					var iy: int = y - oy
					var b := Color(0, 0, 0, 0)
					if ix >= 0 and iy >= 0 and ix < fw and iy < fh:
						b = idle0.get_pixel(ix, iy)
					if a.a > 0.0 or b.a > 0.0:
						opaque += 1
						if not a.is_equal_approx(b):
							diff += 1
			_ok("★★%s %s 第0帧 == 待机第0帧(摆进方帧后逐像素)" % [id, kind], diff == 0 and opaque > 1000,
				"不同 %d / 不透明 %d" % [diff, opaque])
	## ── ④ 主表不盖 ──
	var rb = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var cs: Dictionary = rb.get_script_constant_map()
	var shadowed: Array = []
	for tbl in ["ACTION_ATTACK", "ACTION_HURT", "ACTION_DEATH", "ANIM_NORM"]:
		for id in ids:
			if (cs.get(tbl, {}) as Dictionary).has(id):
				shadowed.append("%s.%s" % [tbl, id])
	_ok("★主场景 ACTION_* / ANIM_NORM 里没有这 11 只(否则旧表盖掉新表)", shadowed.is_empty(), str(shadowed))
	## ── ③ 运行时: 真场景里播动作, 量精灵自己的 pixel_size 与脚底线 ──
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	for u0 in scn._units.duplicate():
		var sp0 = u0.get("sprite", null)
		if sp0 != null and is_instance_valid(sp0):
			sp0.queue_free()
	scn._units.clear()
	var cx: float = scn.ARENA.position.x + scn.ARENA.size.x * 0.5
	var cy: float = scn.ARENA.position.y + scn.ARENA.size.y * 0.5
	var played := 0
	var ncast := 0
	for i in range(ids.size()):
		var id: String = str(ids[i])
		var u: Dictionary = scn._spawn._make_unit(id, "left", Vector2(cx - 400.0 + 70.0 * i, cy))
		u["no_move"] = true
		u["no_basic"] = true
		scn._units.append(u)
		var spr: Sprite3D = u.get("sprite", null)
		if spr == null:
			_ok("★分母: %s 生成出了精灵" % id, false)
			continue
		var ifh: float = float(int(u["idle_sd"].get("frame_h", 0)))
		var px0: float = spr.pixel_size
		var feet0: float = (spr.offset.y + ifh * 0.5 - ifh) * px0   # 待机格子底边的本地高度
		for kind in KINDS:
			scn._vfx._play_action(u, kind)
			var asd: Dictionary = u.get("anim_sd", {})
			if str(u.get("anim_action", "")) != kind:
				_ok("★分母: %s 播起了 %s" % [id, kind], false, "anim_action=%s" % str(u.get("anim_action", "")))
				continue
			played += 1
			var afh: float = float(int(asd.get("frame_h", 0)))
			var feet_row: float = float((TA.NORM[id] as Array)[1])
			var feet1: float = (spr.offset.y + afh * 0.5 - feet_row) * spr.pixel_size
			_ok("★★%s %s 与待机同一个像素尺寸、同一条脚底线" % [id, kind],
				absf(spr.pixel_size - px0) < 1e-7 and absf(feet1 - feet0) < 1e-5,
				"pixel_size %.6f/%.6f · 脚底 %.5f/%.5f m" % [spr.pixel_size, px0, feet1, feet0])
			## 回待机再播下一个(动作之间互不打断的闸不在这条门禁的范围)
			scn._set_anim_sheet(u, u.get("idle_sd", {}), "", true)
		for st in (TA.CAST.get(id, {}) as Dictionary):
			AttackRhythm.cast_begin(scn, u, str(st), 0.34)
			if str(u.get("anim_action", "")) != "cast":
				_ok("★分母: %s 释放动作 %s 播起来了" % [id, st], false)
				continue
			ncast += 1
			var cfh: float = float(int((u.get("anim_sd", {}) as Dictionary).get("frame_h", 0)))
			var cfeet: float = (spr.offset.y + cfh * 0.5 - float((TA.NORM[id] as Array)[1])) * spr.pixel_size
			_ok("★★%s 释放 %s 与待机同一个像素尺寸、同一条脚底线" % [id, st],
				absf(spr.pixel_size - px0) < 1e-7 and absf(cfeet - feet0) < 1e-5,
				"pixel_size %.6f/%.6f · 脚底 %.5f/%.5f m" % [spr.pixel_size, px0, cfeet, feet0])
			scn._set_anim_sheet(u, u.get("idle_sd", {}), "", true)
			u["_cast_wind"] = false
	_ok("★分母: 运行时一共播了 33 次动作(11 只 × 3)", played == 33, "%d 次" % played)
	_ok("★分母: 技能释放动作至少 25 段播过(外包 11 只)", ncast >= 25, "%d 段" % ncast)
	scn.queue_free()
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 外包 11 只动作帧与待机同框同尺度" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
