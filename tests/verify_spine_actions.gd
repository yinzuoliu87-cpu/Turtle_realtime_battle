extends Node
## verify_spine_actions.gd — 动作帧(外包 11 只 + 从头做的龟: 普攻 / 受击 / 阵亡 / 技能 / 形态段)与待机「同一只龟、同一个大小、同一条脚底线」(2026-11-05)。
##
## 由来: 方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.3。动作帧由 tools/assetgen/build_spine_actions.py 在画师 Spine 原骨骼上渲出,
##   表在 scripts/gamedata/turtle_actions.gd(生成)。这套历史上踩过的病(用户 2026-07-21「大小明显不对」/ 08-22「站立的图片和其他动作完全接不上」):
##   动作帧本体只占半帧 ⇒ 一播就缩; 脚底行不同 ⇒ 一播就上下跳。
## 判据(量需求本身, 不读我自己写的配置当答案):
##   ① 表里每张动作图(普攻 / 受击 / 阵亡 / 每个技能的释放动作)都在, 是方帧条(帧高 = 帧宽), 帧数 ≥ 5
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
	var ids: Array = []
	var form_ids: Array = []   # 形态套(如 lava_volcano): 不在 pets.json, 第 0 帧对的是这一套自己的待机
	for k in TA.ATTACK.keys():
		(ids if pets.has(str(k)) else form_ids).append(str(k))
	ids.sort()
	_ok("★分母: 动作表里至少有外包 11 只(另加从头做的龟)", ids.size() >= 11, "%d 只 %s" % [ids.size(), str(ids)])
	_check_forms(form_ids)
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
			## 帧数 ≥ 5: 受击 = 第 0 帧 + 4 帧(15fps ≈ 0.33 秒)是最短的一段(糖果龟 AI 受击 4 帧; 原门槛 6 是随手定的)
			_ok("%s %s 是方帧条, 帧数 ≥ 5" % [id, kind], ai.get_width() % S == 0 and nf >= 5, "%d×%d, %d 帧" % [ai.get_width(), S, nf])
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
	var nstate := 0
	var nstate_rows := 0
	for sid in ids:
		nstate_rows += (TA.STATE.get(sid, []) as Array).size()
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
		## 持续状态循环(缩头乌龟缩壳 / 钻石龟滚球, 11-05): 条件成立 ⇒ 切到状态帧条且脚底线不跳; 条件结束 ⇒ 回待机
		for row in (TA.STATE.get(id, []) as Array):
			var sname: String = str((row as Array)[0])
			if not _set_state(scn, u, sname, true):
				_ok("★%s 状态 %s 在门禁里有触发条件(新状态要在 _set_state 补一行)" % [id, sname], false)
				continue
			nstate += 1
			AttackRhythm.apply_state_idle(scn, u)
			var stex = (u.get("anim_sd", {}) as Dictionary).get("tex", null)
			var sfh: float = float(int((u.get("anim_sd", {}) as Dictionary).get("frame_h", 0)))
			var sfeet: float = (spr.offset.y + sfh * 0.5 - float((TA.NORM[id] as Array)[1])) * spr.pixel_size
			_ok("★★%s 状态 %s 条件成立 ⇒ 播状态帧条, 同一个像素尺寸、同一条脚底线" % [id, sname],
				stex != null and str(stex.resource_path).ends_with(str((row as Array)[1])) and absf(spr.pixel_size - px0) < 1e-7 and absf(sfeet - feet0) < 1e-5,
				"%s · 脚底 %.5f/%.5f" % [str(stex.resource_path).get_file() if stex != null else "无", sfeet, feet0])
			_set_state(scn, u, sname, false)
			AttackRhythm.apply_state_idle(scn, u)
			var btex = (u.get("anim_sd", {}) as Dictionary).get("tex", null)
			_ok("%s 状态 %s 结束 ⇒ 回待机" % [id, sname], btex != null and btex.resource_path == (u["idle_sd"]["tex"] as Texture2D).resource_path)
	_ok("★分母: 运行时每只龟普攻 / 受击 / 阵亡都播了(%d 只 × 3)" % ids.size(), played == ids.size() * 3, "%d 次" % played)
	_ok("★分母: 技能释放动作至少 25 段播过(外包 11 只)", ncast >= 25, "%d 段" % ncast)
	## 至少 2 条 = 缩头乌龟缩壳 + 钻石龟滚球(build_pet_actions.STATE_LOOPS); 0 / 0 不算过
	_ok("★分母: 宠物状态循环每条都触发过(至少缩壳 + 滚球 2 条)", nstate == nstate_rows and nstate_rows >= 2, "%d / %d 条" % [nstate, nstate_rows])
	## 熔岩火山形态: 进火山后播动作, 像素尺寸 / 脚底线仍与普通待机一致
	for e in scn._units:
		if str(e.get("id", "")) == "lava":
			var lspr: Sprite3D = e["sprite"]
			scn._set_anim_sheet(e, e.get("idle_sd", {}), "", true)
			var lfh: float = float(int(e["idle_sd"].get("frame_h", 0)))
			var lpx0: float = lspr.pixel_size
			var lfeet0: float = (lspr.offset.y + lfh * 0.5 - lfh) * lpx0
			e["volcano"] = true
			_ok("火山形态的动画键是 lava_volcano", str(scn._anim_key(e)) == "lava_volcano", str(scn._anim_key(e)))
			for kind in KINDS:
				scn._vfx._play_action(e, kind)
				var vsd: Dictionary = e.get("anim_sd", {})
				var vfeet: float = (lspr.offset.y + float(int(vsd.get("frame_h", 0))) * 0.5 - float((TA.NORM["lava_volcano"] as Array)[1])) * lspr.pixel_size
				_ok("★★火山形态 %s 与普通待机同一个像素尺寸、同一条脚底线" % kind,
					str((vsd.get("tex", null) as Texture2D).resource_path).contains("lava_volcano") and absf(lspr.pixel_size - lpx0) < 1e-7 and absf(vfeet - lfeet0) < 1e-5,
					"%s · pixel_size %.6f/%.6f · 脚底 %.5f/%.5f" % [str((vsd.get("tex", null) as Texture2D).resource_path).get_file(), lspr.pixel_size, lpx0, vfeet, lfeet0])
				scn._set_anim_sheet(e, e.get("idle_sd", {}), "", true)
			e["volcano"] = false
	scn.queue_free()
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 外包 11 只动作帧与待机同框同尺度" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


## 状态循环的触发条件(与 AttackRhythm.state_active 一一对应; 认不得的状态名返回 false ⇒ 门禁红)
func _set_state(scn, u: Dictionary, sname: String, on: bool) -> bool:
	match sname:
		"hidingShrink":
			u["channel_until"] = scn._t + 3.0 if on else 0.0
		"diamondRoll":
			u["roll_active"] = on
		_:
			return false
	return true


func _frame0(path: String) -> Image:
	var t: Texture2D = load("res://assets/sprites/" + path)
	if t == null:
		return null
	var im: Image = t.get_image()
	im.convert(Image.FORMAT_RGBA8)
	var h: int = im.get_height()
	return im.get_region(Rect2i(0, 0, h, h))


func _last(path: String) -> Image:
	var t: Texture2D = load("res://assets/sprites/" + path)
	var im: Image = t.get_image()
	im.convert(Image.FORMAT_RGBA8)
	var h: int = im.get_height()
	return im.get_region(Rect2i(im.get_width() - h, 0, h, h))


func _same(a: Image, b: Image) -> bool:
	return a != null and b != null and a.get_data() == b.get_data()


## 形态套(熔岩火山): 每个动作第 0 帧 == 这一套待机第 0 帧; 变身段首帧 == 普通形态动作第 0 帧、末帧 == 火山待机第 0 帧; 变回 = 变身倒放
func _check_forms(form_ids: Array) -> void:
	_ok("★分母: 形态套至少 1 套(熔岩火山)", form_ids.size() >= 1, str(form_ids))
	for fid in form_ids:
		var st: Array = TA.STATE.get(fid, [])
		_ok("%s 有待机循环(STATE)" % fid, not st.is_empty())
		if st.is_empty():
			continue
		var idle0 := _frame0(str((st[0] as Array)[1]))
		var paths: Array = []
		for kind in KINDS:
			paths.append(str((TA.by_kind(kind)[fid] as Array)[0]))
		for cst in (TA.CAST.get(fid, {}) as Dictionary):
			paths.append(str((TA.CAST[fid][cst] as Array)[0]))
		for pth in paths:
			_ok("%s %s 第0帧 == 这一套待机第0帧" % [fid, str(pth).get_file()], _same(_frame0(str(pth)), idle0))
	for tid in TA.FORM:
		var fm: Dictionary = TA.FORM[tid]
		var a0 := _frame0(str((TA.ATTACK[tid] as Array)[0]))
		if fm.has("revive"):
			## 复活段: 首帧 == 阵亡末帧(趴着), 末帧 == 待机第0帧(站起来正好接回待机)
			var rp: String = str((fm["revive"] as Array)[0])
			_ok("%s 复活段首帧 == 阵亡末帧" % tid, _same(_frame0(rp), _last(str((TA.DEATH[tid] as Array)[0]))))
			_ok("%s 复活段末帧 == 待机第0帧" % tid, _same(_last(rp), a0))
		if fm.has("awaken"):
			_ok("%s 觉醒段首帧 == 待机第0帧" % tid, _same(_frame0(str((fm["awaken"] as Array)[0])), a0))
		if not fm.has("transform"):
			continue
		var tr: Array = (TA.FORM[tid] as Dictionary).get("transform", [])
		var rv: Array = (TA.FORM[tid] as Dictionary).get("revert", [])
		var vol_idle: Array = TA.STATE.get(str(tid) + "_volcano", [])
		if tr.is_empty() or rv.is_empty() or vol_idle.is_empty():
			_ok("%s 变身 / 变回 / 火山待机都登记了" % tid, false)
			continue
		var n0 := _frame0(str((TA.ATTACK[tid] as Array)[0]))
		_ok("%s 变身段首帧 == 普通形态第0帧" % tid, _same(_frame0(str(tr[0])), n0))
		_ok("%s 变身段末帧 == 火山待机第0帧" % tid, _same(_last(str(tr[0])), _frame0(str((vol_idle[0] as Array)[1]))))
		_ok("%s 变回段首帧 == 火山待机第0帧、末帧 == 普通形态第0帧" % tid,
			_same(_frame0(str(rv[0])), _frame0(str((vol_idle[0] as Array)[1]))) and _same(_last(str(rv[0])), n0))
