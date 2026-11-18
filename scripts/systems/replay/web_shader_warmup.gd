extends Node
## 网页播放器 · 开播前预热粒子着色器(2026-11-18 · 方案书 docs/plans/20261118d-网页播放器卡顿.md P1 第二版)。
##
## 病因: 浏览器(Windows 上 Chrome 走 ANGLE → D3D)第一次用到一种粒子设置时当场编译着色器、引擎同步等它 ⇒ 播到一半卡 1~2 秒
##   (开湍流的一次 6~15 秒, 已由 P2 在网页上关掉)。原生版有显卡驱动缓存, App 里不明显。
## 第一版只照「运算材质」去重预热, 播放中还剩 3 次约 1.7 秒: 着色器变体还取决于粒子**节点**的设置(拖尾 / 插值 / 排序 / 朝向对齐…)
##   和**绘制**用的网格材质。⇒ 第二版照流里每个 GPUParticles3D 的 NODE_NEW **原样复刻**:
##   节点上开关 / 枚举类属性照设(位置类不设), 运算材质、绘制网格与它的材质按 RES_DEF 现建(子资源递归);
##   程序生成的贴图 / 网格只影响「有没有」那一位, 用同类空实例代替; 按签名去重(一局 309 个粒子节点 → 几种)。
## 分帧: 每帧只放 PER_FRAME 种, 每种编译卡在它那一帧里 ⇒ 载入那一屏不会一口气冻住几十秒(第一版一帧卡 22 秒, 可能触发「网页无响应」)。
## ★不改画面: 预热用的粒子在单独的 32×32 小视口里、不显示; 真播时的粒子还是流里那一份。
## 用法: `var w := WebShaderWarmup.new(); w.chunks = [...]; w.done.connect(cb); add_child(w)`; 跑完发 `done` 并自删。
## 门禁: tests/verify_web_player.gd(整局块都解了、粒子节点去重后的种数、整局照样播到尾)。

const F := preload("res://scripts/systems/stream/stream_format.gd")
const CHUNKS_PER_FRAME := 6
const PER_FRAME := 1
## 最后一种放下之后再等几帧(编译卡在那一帧里; 多给余量)。
const SETTLE_FRAMES := 4
## 节点上不复刻的属性: 位置 / 显隐 / 时间类, 跟着色器变体无关, 设了反而可能让它不出现在小视口里。
const SKIP_PROPS := ["position", "rotation", "scale", "transform", "global_position", "global_rotation", "global_transform",
	"rotation_degrees", "quaternion", "basis", "visible", "emitting", "preprocess", "speed_scale", "explosiveness", "randomness",
	"lifetime", "one_shot", "amount_ratio", "visibility_aabb", "custom_aabb", "seed", "use_fixed_seed", "top_level", "layers",
	"sorting_offset", "cast_shadow"]
const AMOUNT_CAP := 8

signal done

## 上一次预热的结果(门禁读): {chunks, parsed, nodes, kinds, placed, ms_parse, ms_total}
static var last := {}

var chunks: Array = []                 # PackedByteArray, 按块号
## 观测量
var nodes := 0                         # 流里 GPUParticles3D 建了几个
var kinds := 0                         # 去重后几种
var placed := 0
var parsed := 0
var bad_chunks := 0
var ms_parse := 0.0
var ms_total := 0.0

var _st := {}
var _i := 0
var _rdef := {}                        # rid → [种类, a, b](RES_DEF 原样)
var _built := {}                       # rid → Resource(本次预热现建的)
var _queue: Array = []                 # [类名, props]
var _sigs := {}
var _vp: SubViewport = null
var _settle := -1
var _t0 := 0


func _ready() -> void:
	_t0 = Time.get_ticks_usec()


func _process(_dt: float) -> void:
	if _i < chunks.size():
		_parse_some()
		return
	if _vp == null:
		_open_vp()
	if not _queue.is_empty():
		for _k in range(PER_FRAME):
			if _queue.is_empty():
				break
			_place(_queue.pop_front())
		if _queue.is_empty():
			_settle = SETTLE_FRAMES
		return
	_settle -= 1
	if _settle <= 0:
		_finish()


func _parse_some() -> void:
	var t := Time.get_ticks_usec()
	var n := 0
	while _i < chunks.size() and n < CHUNKS_PER_FRAME:
		var r := F.parse_chunk(chunks[_i] as PackedByteArray, _st)
		_i += 1
		n += 1
		if not bool(r.get("ok", false)):
			bad_chunks += 1
			continue
		parsed += 1
		for step in r["list"]:
			for op in step[2]:
				var code := int(op[0])
				if code == F.OP_RES_DEF:
					if not _rdef.has(int(op[1])):
						_rdef[int(op[1])] = [int(op[2]), op[3], op[4] if op.size() > 4 else null]
				elif code == F.OP_NODE_NEW and str(op[5]) == "GPUParticles3D":
					nodes += 1
					_take(str(op[5]), op[6] as Array)
	ms_parse += (Time.get_ticks_usec() - t) / 1000.0


## 一个粒子节点 → 签名; 新签名进队列。签名 = 节点上开关 / 枚举的取值 + 每个资源属性指向的资源的签名(递归, 数值类只记名字)。
func _take(cls: String, props: Array) -> void:
	var parts: Array = [cls]
	for p in props:
		var nm := str(p[0])
		if nm in SKIP_PROPS:
			continue
		if bool(p[2]):
			parts.append("%s=%s" % [nm, _res_sig(int(p[1]), 0)])
		elif p[1] is bool or p[1] is int:
			parts.append("%s=%s" % [nm, str(p[1])])
		else:
			parts.append(nm)
	parts.sort()
	var sig := "|".join(PackedStringArray(parts))
	if _sigs.has(sig):
		return
	_sigs[sig] = true
	_queue.append([cls, props])


func _res_sig(rid: int, depth: int) -> String:
	var d = _rdef.get(rid)
	if d == null or depth > 3:
		return "?"
	var kind: int = d[0]
	if kind != F.RES_PARAM:
		return "k%d:%s" % [kind, str(d[1]) if kind != F.RES_SHADER else str(str(d[1]).hash())]
	var parts: Array = [str(d[1])]
	for p in (d[2] as Array):
		var nm := str(p[0])
		if bool(p[2]):
			parts.append("%s=%s" % [nm, _res_sig(int(p[1]), depth + 1)])
		elif p[1] is bool or p[1] is int:
			parts.append("%s=%s" % [nm, str(p[1])])
		else:
			parts.append(nm)
	parts.sort()
	return "{" + ",".join(PackedStringArray(parts)) + "}"


## 照 RES_DEF 现建一份资源(子资源递归)。程序生成 / 无路径的给同类空实例(只影响「有没有」那一位)。
func _res(rid: int, depth: int = 0) -> Resource:
	if _built.has(rid):
		return _built[rid]
	var d = _rdef.get(rid)
	var r: Resource = null
	if d != null and depth <= 3:
		var kind: int = d[0]
		match kind:
			F.RES_PARAM:
				if ClassDB.can_instantiate(str(d[1])):
					r = ClassDB.instantiate(str(d[1])) as Resource
					if r != null:
						for p in (d[2] as Array):
							var v = p[1]
							if bool(p[2]):
								v = _res(int(v), depth + 1)
							r.set(str(p[0]), v)
						if r is ParticleProcessMaterial:
							(r as ParticleProcessMaterial).turbulence_enabled = false   # 与播放时一致(StreamMirror.no_turb)
			F.RES_SHADER:
				var sh := Shader.new()
				sh.code = str(d[1])
				r = sh
			F.RES_PATH:
				r = _stand_in("Texture2D") if str(d[1]).get_extension() in ["png", "webp", "jpg", "svg"] else (load(str(d[1])) if ResourceLoader.exists(str(d[1])) else null)
			_:
				r = _stand_in(str(d[1]))
	_built[rid] = r
	return r


func _stand_in(cls: String) -> Resource:
	if cls.contains("Mesh"):
		return QuadMesh.new()
	if cls.contains("Texture") or cls == "" or cls == "?":
		return ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	if ClassDB.can_instantiate(cls):
		return ClassDB.instantiate(cls) as Resource
	return null


func _open_vp() -> void:
	kinds = _queue.size()
	_vp = SubViewport.new()
	_vp.size = Vector2i(32, 32)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 6)
	_vp.add_child(cam)
	if _queue.is_empty():
		_settle = 0


func _place(item: Array) -> void:
	var n := ClassDB.instantiate(str(item[0])) as GPUParticles3D
	if n == null:
		return
	for p in (item[1] as Array):
		var nm := str(p[0])
		if nm in SKIP_PROPS:
			continue
		var v = p[1]
		if bool(p[2]):
			v = _res(int(v))
		n.set(nm, v)
	n.amount = clampi(n.amount, 1, AMOUNT_CAP)
	n.lifetime = 0.5
	n.one_shot = false
	n.position = Vector3(float(placed % 5) - 2.0, floorf(placed / 5.0) * 0.5 - 1.0, 0.0)
	n.emitting = true
	_vp.add_child(n)
	placed += 1


func _finish() -> void:
	ms_total = (Time.get_ticks_usec() - _t0) / 1000.0
	last = {"chunks": chunks.size(), "parsed": parsed, "nodes": nodes, "kinds": kinds, "placed": placed, "ms_parse": ms_parse, "ms_total": ms_total}
	print("[warmup] 块 %d/%d · 粒子节点 %d 个 → %d 种(放了 %d)· 解块 %.0f ms · 合计 %.0f ms" % [parsed, chunks.size(), nodes, kinds, placed, ms_parse, ms_total])
	set_process(false)
	done.emit()
	queue_free()
