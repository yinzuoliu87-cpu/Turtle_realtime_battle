extends Node
## verify_execution_vfx.gd — 处决演出(药水【斩首】+ 弓箭【处决】共用一套) 2026-08-14
##
## ★由来: 这两条羁绊在此之前**只有一句 `-999999` 浮字** —— 和普通真伤大字长得一模一样,
##   玩家读不出"这是处决"。两条同族(都是血线以下直接抹杀), 所以做**一套**覆盖两条。
##
## ★判据数的是【产品自己造的节点】(世界里带 `synergy_vfx` 元数据的刀身/碎片),
##   不是我插的标记 —— 那正是 v0.19.141 凤凰那个洞的形状。
## ★演出用 tween 没关系, 但**落刀那一拍走 `_pending_shots`(sim 时钟)**,
##   否则无头下碎片永远数不到(今天已在法器上踩过两次)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SynVfx := preload("res://scripts/scenes/battle/synergy_vfx.gd")
const VfxTex := preload("res://scripts/util/vfx_textures.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 数世界里某一类演出节点 —— 走 `_adopt` 打的元数据, 是产品自己的账。
func _count(s, kind: String) -> int:
	var n := 0
	if s._world == null or not is_instance_valid(s._world):
		return 0
	for c in s._world.get_children():
		if c.has_meta("synergy_vfx") and str(c.get_meta("synergy_vfx")) == kind:
			n += 1
	return n


func _ready() -> void:
	await get_tree().process_frame
	print("=== 处决演出 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	s._edit_mode = false
	s._over = false

	# ── ① 原语本身: 落刀 → 切割线 + 碎片 ────────────────────────────────────
	_ok("★分母: 开场世界里没有任何处决节点",
		_count(s, "exec_blade") == 0 and _count(s, "exec_shard") == 0,
		"刀 %d / 碎片 %d" % [_count(s, "exec_blade"), _count(s, "exec_shard")])
	var blade = s._vfx._syn.execution(c, SynVfx.COL_POTION)
	_ok("★★调用后立刻有【铡刀】(不用等任何动画)", blade != null and _count(s, "exec_blade") == 1,
		"刀=%d" % _count(s, "exec_blade"))
	_ok("★此刻还【没有】碎片(碎裂要等落刀那一拍, 不是同帧全出)",
		_count(s, "exec_shard") == 0, "碎片=%d" % _count(s, "exec_shard"))
	## 推进到落刀时刻。★走 sim 时钟 —— 判据不依赖 tween 跑完。
	for _f in range(int((SynVfx.EXEC_FALL_SEC + 0.05) * 60.0)):
		s._sim_step(1.0 / 60.0, false, false)
	_ok("★★落刀那一拍: 轮廓崩裂出 %d 片碎块" % SynVfx.EXEC_SHARDS,
		_count(s, "exec_shard") == SynVfx.EXEC_SHARDS,
		"碎片=%d(应 %d)" % [_count(s, "exec_shard"), SynVfx.EXEC_SHARDS])
	_ok("★★同一拍还有【横向切割线】", _count(s, "exec_cut") == 1,
		"切割线=%d" % _count(s, "exec_cut"))
	## 碎片纹理必须是【带尖角的碎块】, 不是圆 —— 用户 2026-08-06 明确反对无含义的圆。
	##   判据: 六种形状里任取两片, 纹理必须不同(圆的话六片一模一样)。
	var t0: Texture2D = VfxTex._make_shard_texture(Color.WHITE, 0)
	var t1: Texture2D = VfxTex._make_shard_texture(Color.WHITE, 1)
	var img0: Image = t0.get_image()
	var img1: Image = t1.get_image()
	var diff := 0
	for y in range(img0.get_height()):
		for x in range(img0.get_width()):
			if img0.get_pixel(x, y).a != img1.get_pixel(x, y).a:
				diff += 1
	_ok("★★碎片是【六种不同形状】而不是同一个圆(逐像素差 %d 个)" % diff, diff > 20,
		"两片形状差 %d 像素" % diff)

	# ── ② 药水【斩首】真的会放这套演出吗 ────────────────────────────────────
	##   ★走真入口 `try_behead`, 不直接调演出 —— 直接调等于绕过"够不够条件"那条链。
	var before_b: int = _count(s, "exec_blade")
	var src: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-100, 0))
	var tgt: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(100, 0))
	tgt["maxHp"] = 1000.0
	tgt["hp"] = 50.0                       # 远低于斩首线
	s._units.clear()
	s._units.append_array([src, tgt])
	## ★配齐斩首的两个前提, 否则 `try_behead` 直接 return false ——
	##   第一版没配, 分母那条就红了(而且它红得对: 它就是用来抓"局面没配对"的)。
	##   ① 药水羁绊要到 BEHEAD_TIER 档 ② 目标必须是本方的【猎物】
	s._potion_syn._prey["left"] = tgt
	## 直接把本方羁绊档位写进 `_by_side` —— `tier_for` 读的就是它。
	## ★为什么不去凑 8 件药水装备: 那要连商店/阵容/roster 一起搭, 而这条门禁验的是
	##   **"斩首成立时演出放不放"**, 不是"羁绊档位怎么算"(那是 verify_synergy_* 的地盘)。
	##   走真入口 `try_behead` 才是重点, 前提条件用最短路径配齐即可。
	s._synergy._by_side["left"] = {"药水": s._potion_syn.BEHEAD_TIER}
	var _tier: int = int(s._synergy.tier_for(src, "药水"))
	_ok("★分母: 药水羁绊已到斩首档(%d ≥ %d)" % [_tier, s._potion_syn.BEHEAD_TIER],
		_tier >= s._potion_syn.BEHEAD_TIER, "档位=%d" % _tier)
	_ok("★分母: 目标已被标为本方猎物", s._potion_syn.is_prey_of("left", tgt))
	var fired: bool = s._potion_syn.try_behead(src, tgt)
	_ok("★分母: 药水【斩首】在这个局面下确实触发了", fired, "try_behead=%s" % str(fired))
	_ok("★★斩首触发 ⇒ 处决演出【真的放了】(不是只跳个字)",
		_count(s, "exec_blade") == before_b + 1,
		"刀 %d → %d" % [before_b, _count(s, "exec_blade")])

	# ── ③ 反面: 血线以上不该处决, 也不该有演出 ──────────────────────────────
	var before_n: int = _count(s, "exec_blade")
	var tgt2: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
	tgt2["maxHp"] = 1000.0
	tgt2["hp"] = 999.0                     # 满血
	s._units.append(tgt2)
	var fired2: bool = s._potion_syn.try_behead(src, tgt2)
	_ok("★反面: 满血目标不该被斩首", not fired2, "try_behead=%s" % str(fired2))
	_ok("★★反面: 没触发就【一把刀都不许多】(否则是恒放)",
		_count(s, "exec_blade") == before_n,
		"刀 %d → %d" % [before_n, _count(s, "exec_blade")])

	# ── ④ 弓箭【处决】走的是同一套(两条同族做一套的意义就在这) ────────────────
	var src_bow := FileAccess.get_file_as_string("res://scripts/systems/equip/bow_synergy_system.gd")
	var src_pot := FileAccess.get_file_as_string("res://scripts/systems/equip/potion_synergy_system.gd")
	_ok("★★弓箭【处决】接的是同一个 `execution` 原语", src_bow.find("_syn.execution(") >= 0)
	_ok("★★药水【斩首】接的也是它(同族同演出)", src_pot.find("_syn.execution(") >= 0)

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 处决演出")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
