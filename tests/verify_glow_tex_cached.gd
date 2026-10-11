extends Node
## verify_glow_tex_cached.gd —— 发光贴图只建一次(2026-10-11 全项目通读 A8)
## ★原来每次调用逐像素重建 96×96 并上传新纹理(海盗炮弹烟尾每帧调); 结果只取决于常量 ⇒ 缓存。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	var a: ImageTexture = VfxTex._make_glow_texture()
	var b: ImageTexture = VfxTex._make_glow_texture()
	_ok("★分母: 拿到一张 96×96 的贴图", a != null and a.get_width() == 96)
	_ok("★★两次调用拿到的是同一张(不重建)", is_same(a, b))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
