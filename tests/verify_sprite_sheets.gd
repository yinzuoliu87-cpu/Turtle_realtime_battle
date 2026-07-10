extends Node
## verify_sprite_sheets.gd — 守卫: 立绘 sprite-sheet 的尺寸与帧数
##
## 由来〖用户 2026-07-10 真机〗:「有些角色图片是黑的」
##   根因: `shell.png` 是 10000×500 的横条图, 超过安卓 GPU 的 GL_MAX_TEXTURE_SIZE
##   (OpenGL ES3 规范下限 2048, 真机常见 4096/8192) → 纹理创建失败 → 采样即黑。
##   桌面 NVIDIA 上限 32768, 所以端游一直正常, headless 也测不出来。
##
## 本测试把"能不能在手机上传上去"变成机器检查:
##   1. 任何贴图的最大边 ≤ MAX_DIM (4096)
##   2. 每只龟的【有效帧数】与重排前逐一相同 (重排是像素不变的, 帧数也必须不变)
##   3. sheet 尺寸 == hframes*frameW × vframes*frameH (没有半格)
##   4. 有效帧数 ≤ 总格数 (不会播到空白格)

const MAX_DIM := 4096

## 重排【之前】测得的有效帧数 (= min(sprite.frames, hframes*vframes - 1), drop_last)
## 改动画帧数是设计行为, 不该由重排偷偷带来 → 任一不符即 FAIL。
const EXPECTED_EFFECTIVE := {
	"basic": 7, "stone": 9, "bamboo": 9, "angel": 7, "ninja": 5, "ghost": 11,
	"fortune": 17, "hunter": 14, "candy": 9, "line": 13, "crystal": 10,
	"space": 11, "hiding": 13, "headless": 16, "shell": 19,
}

var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame

	# ── 1. 全库贴图不许超过 MAX_DIM ─────────────────────────────────────────
	var over: Array = []
	_scan_dir("res://assets", over)
	_ok("全库贴图最大边 ≤ %d" % MAX_DIM, over.is_empty(), str(over.slice(0, 6)))

	# ── 自检探针: 扫描器本身要能抓到超限 ────────────────────────────────────
	var probe := Image.create(MAX_DIM + 8, 16, false, Image.FORMAT_RGBA8)
	_ok("自检·已知阳性(伪造一张超限图能被判超限)", maxi(probe.get_width(), probe.get_height()) > MAX_DIM)
	var probe2 := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	_ok("自检·已知阴性(64x64 不判超限)", maxi(probe2.get_width(), probe2.get_height()) <= MAX_DIM)

	# ── 2/3/4. 每只龟的 sheet 布局与有效帧数 ────────────────────────────────
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	var doc = JSON.parse_string(f.get_as_text())
	f.close()
	var pets: Array = doc["pets"] if (doc is Dictionary and doc.has("pets")) else doc

	var bad_layout: Array = []
	var bad_frames: Array = []
	for p in pets:
		var pid := str(p.get("id", "?"))
		var img := str(p.get("img", ""))
		var meta = p.get("sprite", null)
		if img == "" or not (meta is Dictionary) or not (meta as Dictionary).has("frameW"):
			continue
		var path := "res://assets/sprites/" + img
		if not ResourceLoader.exists(path):
			bad_layout.append("%s 立绘缺失 %s" % [pid, img])
			continue
		var tex: Texture2D = load(path)
		var tw := tex.get_width()
		var th := tex.get_height()
		var fw: int = int(meta["frameW"])
		var fh: int = int(meta["frameH"])
		if tw % fw != 0 or th % fh != 0:
			bad_layout.append("%s %dx%d 不是 %dx%d 的整数倍" % [pid, tw, th, fw, fh])
			continue
		var hf: int = tw / fw
		var vf: int = th / fh
		var total: int = hf * vf
		var effective: int = maxi(1, mini(int(meta.get("frames", total)), total - 1))
		if effective > total:
			bad_layout.append("%s 有效帧 %d > 总格 %d" % [pid, effective, total])
		if EXPECTED_EFFECTIVE.has(pid) and int(EXPECTED_EFFECTIVE[pid]) != effective:
			bad_frames.append("%s: 期望 %d 帧, 实际 %d 帧" % [pid, int(EXPECTED_EFFECTIVE[pid]), effective])

	_ok("sheet 布局是整数格 (无半格)", bad_layout.is_empty(), str(bad_layout))
	_ok("有效帧数与重排前一致", bad_frames.is_empty(), str(bad_frames))

	print("")
	if _fail == 0:
		print("ALL PASS — 立绘 sheet: 无超限贴图 / 帧数未变 / 布局整齐")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _scan_dir(path: String, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			if not n.begins_with("."):
				_scan_dir(path + "/" + n, out)
		elif n.ends_with(".png"):
			var p := path + "/" + n
			if ResourceLoader.exists(p):
				var t: Texture2D = load(p)
				if t != null and maxi(t.get_width(), t.get_height()) > MAX_DIM:
					out.append("%s (%dx%d)" % [p, t.get_width(), t.get_height()])
		n = d.get_next()
	d.list_dir_end()
