extends Node
## verify_brew_glow_sheet_swap.gd —— 066 鲸涎浓浆金红光: 龟换动作表后不越界(60 人实操台账 A3)
## 原现象: brew_glow_tick 只抄 frame, 不抄贴图/切格 ⇒ 龟换到帧数更多的表时光晕那张表越界, 每帧报 p_frame out of bounds。
## 判据: 光晕建在 1 帧的表上 → 本体换成 6 帧表并停在第 5 帧 → tick 一次 ⇒ 光晕的切格跟上、帧号在界内、等于本体帧号。
const VFX := preload("res://scripts/scenes/battle/potion_eq_vfx.gd")
var _n := 0
var _fail := 0
func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", t, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", t, "  ", d)
func _tex(w: int, h: int) -> ImageTexture:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(im)
func _ready() -> void:
	await get_tree().process_frame
	print("=== 066 金红光: 龟换动作表不越界 ===")
	var spr := Sprite3D.new()
	add_child(spr)
	spr.texture = _tex(32, 32); spr.hframes = 1; spr.vframes = 1; spr.frame = 0
	var u := {"sprite": spr}
	var fx = VFX.new(self)
	fx.brew_glow_start(u)
	var g = u.get("_brew_glow", null)
	_ok("★分母: 光晕真的建出来了", is_instance_valid(g))
	if not is_instance_valid(g):
		_end(); return
	spr.texture = _tex(192, 32); spr.hframes = 6; spr.vframes = 1; spr.frame = 5
	fx.brew_glow_tick(u, 0.5)
	_ok("★★光晕的切格跟上了本体(6×1)", g.hframes == 6 and g.vframes == 1, "%d×%d" % [g.hframes, g.vframes])
	_ok("★★光晕帧号 = 本体帧号 5 且在界内", g.frame == 5 and g.frame < g.hframes * g.vframes, str(g.frame))
	spr.texture = _tex(32, 32); spr.hframes = 1; spr.vframes = 1; spr.frame = 0
	fx.brew_glow_tick(u, 0.6)
	_ok("换回 1 帧表 ⇒ 光晕也回到 1×1、帧号 0", g.hframes == 1 and g.frame == 0, "%d×%d f=%d" % [g.hframes, g.vframes, g.frame])
	_end()
func _end() -> void:
	print("")
	if _fail == 0 and _n >= 4:
		print("ALL PASS — 066 金红光换表不越界 (%d 条)" % _n); get_tree().quit(0)
	else:
		print("FAILED %d / %d" % [_fail, _n]); get_tree().quit(1)
