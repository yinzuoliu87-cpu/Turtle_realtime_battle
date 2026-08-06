extends Node
## 横排序列图不得被当单帧渲染。
##
## 由来〖用户 2026-08-02〗:「龟蛋碎裂我之前看有个那几个贴图还是啥序列图应该用错了」
##   实查: boom-wave-anim.png(480×96 = 5帧) 与 electric-zap.png(480×96 = 5帧) 被丢给
##   `_burst_vfx` —— 而它当时【不识别横排帧】(同项目的 `_fly_vfx` 一直识别)。
##   后果: 5 帧并排同时显示、横着摊成一条。破一次蛋出现 5 个并排爆炸。
##
## ★根因不是"调用方写错了", 是【同类助手函数行为不一致】: 同样一张横条图,
##   _fly_vfx 对、_burst_vfx 错, 调用方没理由知道这个区别。所以修在助手函数里。
##
## 本门禁守两条:
##   ① 助手函数层: 拿一张真的横排图喂给 _burst_vfx → 生成的 Sprite3D 必须 hframes == 帧数
##   ② 全仓扫描: 任何传给 _burst_vfx / _map_billboard 的贴图, 若是横条(宽 = 高的整数倍且≥2),
##      则该助手必须能识别帧 —— 否则报出来。这条防的是【将来新增的助手函数又忘了识别】。
var _n := 0
var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond: _fail += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("  " + detail) if detail != "" else ""])

const STRIP := "res://assets/sprites/vfx/boom-wave-anim.png"

func _ready() -> void:
	await get_tree().process_frame
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for i in range(30):
		await get_tree().process_frame

	# ── ★分母: 这张图真的是横排多帧(否则下面是空检查)
	var tex: Texture2D = load(STRIP)
	_ok("★分母: 测试用图存在", tex != null)
	if tex == null:
		_finish(); return
	var fh: int = tex.get_height()
	var nf: int = tex.get_width() / maxi(1, fh)
	_ok("★分母: 它是 %d 帧横排(%dx%d)" % [nf, tex.get_width(), fh],
		nf >= 2 and tex.get_width() % fh == 0, "%dx%d" % [tex.get_width(), fh])

	# ── ① 助手函数必须识别帧
	# ★★2026-08-07 修【偶发假红】: 原来按【子节点索引区间】倒查(从 count-1 数到 before),
	#   而战场每帧都在建/放别的特效节点 ⇒ 别人先被 free 掉时索引整体前移, 这一段窗口就错位,
	#   找不到刚建的那个 ⇒ 同一份代码连跑两次一次红一次绿。
	#   ⇒ 改成【全量扫 + 按贴图认】: 不依赖索引, 只认 texture == tex。
	#   ⚠ 全量扫要先记下"扫之前就已经存在的同贴图节点", 否则上一次跑剩的会让它恒真。
	var pre: Array = []
	for c0 in s._world.get_children():
		if c0 is Sprite3D and (c0 as Sprite3D).texture == tex:
			pre.append(c0)
	s._burst_vfx(STRIP, s._arena_center, 200.0, 0.5)
	await get_tree().process_frame
	var made: Sprite3D = null
	for c in s._world.get_children():
		if c is Sprite3D and (c as Sprite3D).texture == tex and not (c in pre):
			made = c; break
	_ok("★分母: _burst_vfx 真的建出了 Sprite3D", made != null)
	if made != null:
		_ok("① ★横排图经 _burst_vfx → hframes == %d(不是当单帧摊开)" % nf,
			made.hframes == nf, "hframes=%d" % made.hframes)

	# ── ② 全仓扫描: 传给不识别帧的助手的横条图
	var offenders: Array = []
	for pair in _scan_calls():
		var p: String = str(pair[0])
		var t2: Texture2D = load(p) if ResourceLoader.exists(p) else null
		if t2 == null: continue
		var h2: int = maxi(1, t2.get_height())
		if t2.get_width() > h2 and t2.get_width() % h2 == 0:
			offenders.append("%s (%dx%d=%d帧) ← %s" % [p, t2.get_width(), h2, t2.get_width() / h2, pair[1]])
	_ok("② 没有横条序列图被丢给【不识别帧】的助手", offenders.is_empty(),
		"; ".join(offenders))
	_finish()

## 扫源码: 目前 _map_billboard 不识别帧(它画地图道具, 本来就该是单帧)。
## _burst_vfx 已在 2026-08-02 补上识别, 所以不在名单里。
func _scan_calls() -> Array:
	# ★不用 RegEx —— GDScript 字符串里那串转义(\( \s \.)过不了解析器("Invalid escape in string")。
	#   这里要找的东西很固定, 直接扫字面量前缀即可, 比跟转义较劲稳。
	var out: Array = []
	const MARK := '_map_billboard("'
	for f in _gd_files("res://scripts"):
		var src: String = FileAccess.get_file_as_string(f)
		if src == "":
			continue
		var at: int = src.find(MARK)
		while at != -1:
			var st: int = at + MARK.length()
			var en: int = src.find('"', st)
			if en > st:
				out.append([src.substr(st, en - st), f.get_file()])
			at = src.find(MARK, st)
	return out


func _gd_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null: return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := dir + "/" + n
		if d.current_is_dir():
			out.append_array(_gd_files(full))
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	return out

func _finish() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 横排序列图不被当单帧渲染" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
