class_name StreamMirror
extends RefCounted
## 服务器逐帧直播 · 节点层镜像(S2 手机播放)。方案书 docs/plans/20261019-服务器逐帧直播.md §4「stream_mirror」。
##
## 按录流器发来的 NODE_NEW / NODE_SET / NODE_DEL / RES_DEF / RES_SET 在手机的 `_world` 下建一份同类、同属性的节点。
## 镜像节点是**纯数据节点**: 不挂脚本、不挂 tween, 每个属性只由流来改(粒子由手机自己放, 外观随机性与现状相同)。
##
## ★占位(S3 长尾, 方案 §2.2「程序贴图和程序网格的出处键留给 S3」): 流里只有「这是一张 W×H 的程序贴图 / 一个 N 面的程序网格」,
##   手机造不出原图 ⇒ 程序贴图画一张同尺寸的白色软圆, 程序网格给一个空网格(什么都不画)。每用一次占位都计数(`ph_*`),
##   门禁 verify_stream_parity 把它们列为已知例外并打印数量, S3 清零。
##
## 连续量插值: 每个镜像节点记一份「真值」(最近一次流里给的 position / rotation / scale / modulate)。
##   播放器在两次采样之间用下一个采样值插(`lerp_to`), 插出来的值只写节点、不写真值; 下一帧先 `restore()` 回真值再插。

const F := preload("res://scripts/systems/stream/stream_format.gd")

var world: Node3D
var nodes := {}               # id → Node(镜像节点)
var res := {}                 # rid → Resource(本 keyframe 段)
var _res_prev := {}           # keyframe 重建时: 上一段的资源表(同一个 rid 复用同一个对象, 不闪)
var _truth := {}              # id → [position, rotation, scale, modulate](只记流里给过的)
var _lerped := {}             # 这一帧插过值的 id
var _kf_seen := {}            # keyframe 期间出现过的节点 id
var _ph_tex_cache := {}       # "宽x高" → 占位贴图
## 计数(门禁的分母 / 已知例外)
var built := 0
var deleted := 0
var sets := 0
var ph_gen_tex := 0           # 程序贴图占位(定义次数)
var ph_proc_mesh := 0         # 程序网格占位(定义次数)
var ph_other := 0             # 其它无路径资源(给 null)
var parent_fallback := 0      # 父节点找不到、挂到 _world 的
var reparents := 0            # 跟着服务器换过父节点的次数
var kf_dropped := 0           # keyframe 里没出现、被兜底删掉的(顺播时应为 0)
var unit_parent: Callable = Callable()   # (单位 idx, 键名) → Node; 播放器注入


func _init(w: Node3D) -> void:
	world = w


# ── 资源 ──
func res_def(rid: int, kind: int, a, b, c) -> void:
	var old = _res_prev.get(rid, res.get(rid))
	if old != null and kind != F.RES_GEN_TEX:
		## 同一个 rid 已经有对象(顺播经过 keyframe): 复用, 只把参数再设一遍
		res[rid] = old
		if kind == F.RES_PARAM:
			_apply_props(old as Object, b as Array)
		return
	var r: Resource = null
	match kind:
		F.RES_PATH:
			if ResourceLoader.exists(str(a)):
				r = load(str(a))
		F.RES_PARAM:
			if ClassDB.can_instantiate(str(a)):
				r = ClassDB.instantiate(str(a)) as Resource
				if r != null:
					_apply_props(r, b as Array)
		F.RES_GEN_TEX:
			ph_gen_tex += 1
			if old != null:
				r = old
			else:
				r = _ph_tex(int(b), int(c))
		F.RES_PROC_MESH:
			ph_proc_mesh += 1
			r = ArrayMesh.new()
		F.RES_SHADER:
			var sh := Shader.new()
			sh.code = str(a)
			r = sh
		_:
			ph_other += 1
	res[rid] = r


func res_set(rid: int, props: Array) -> void:
	var r = res.get(rid)
	if r != null:
		_apply_props(r as Object, props)


func _ph_tex(w: int, h: int) -> Texture2D:
	var k := "%dx%d" % [w, h]
	if _ph_tex_cache.has(k):
		return _ph_tex_cache[k]
	var ww := clampi(w, 1, 256)
	var hh := clampi(h, 1, 256)
	var img := Image.create(ww, hh, false, Image.FORMAT_RGBA8)
	var cx := (ww - 1) * 0.5
	var cy := (hh - 1) * 0.5
	for y in range(hh):
		for x in range(ww):
			var d := Vector2((x - cx) / maxf(1.0, cx), (y - cy) / maxf(1.0, cy)).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_ph_tex_cache[k] = t
	return t


# ── 节点 ──
func node_new(id: int, pk: int, pid: int, pkey: String, cls: String, props: Array) -> void:
	_kf_seen[id] = true
	var ex = nodes.get(id)
	if ex != null and is_instance_valid(ex):
		## keyframe 重发一个已经在的节点: 只把属性对一遍(顺播时这些值本来就一样)
		_apply_node_props(ex as Node, id, props)
		return
	if not ClassDB.can_instantiate(cls):
		return
	var n := ClassDB.instantiate(cls) as Node
	if n == null:
		return
	var par: Node = _parent(pk, pid, pkey)
	_apply_node_props(n, id, props)
	par.add_child(n)
	nodes[id] = n
	built += 1


func _parent(pk: int, pid: int, pkey: String) -> Node:
	match pk:
		F.PAR_NODE:
			var p = nodes.get(pid)
			if p != null and is_instance_valid(p):
				return p
			parent_fallback += 1
		F.PAR_UNIT:
			var p2 = unit_parent.call(pid, pkey) if unit_parent.is_valid() else null
			if p2 != null and is_instance_valid(p2) and p2 is Node:
				return p2
			parent_fallback += 1
		F.PAR_PATH:
			var p3 := world.get_node_or_null(NodePath(pkey))
			if p3 != null:
				return p3
			parent_fallback += 1
	return world


func node_set(id: int, props: Array) -> void:
	var n = nodes.get(id)
	if n == null or not is_instance_valid(n):
		return
	sets += 1
	_apply_node_props(n as Node, id, props)


func node_del(id: int) -> void:
	var n = nodes.get(id)
	nodes.erase(id)
	_truth.erase(id)
	_lerped.erase(id)
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()
		deleted += 1


## keyframe 开始: 资源表换新(旧对象留着给同 rid 复用), 记下这一帧出现过哪些节点。
func kf_begin() -> void:
	_res_prev = res
	res = {}
	_kf_seen = {}


## keyframe 结束: 这一帧里没出现的镜像节点删掉(录流器删节点本来就会发 DEL; 这里是拖进度 / 丢块后的兜底)。
func kf_end() -> void:
	for id in nodes.keys():
		if not _kf_seen.has(id):
			kf_dropped += 1
			node_del(int(id))
	_res_prev = {}
	_kf_seen = {}


func clear() -> void:
	for id in nodes.keys():
		node_del(int(id))
	res = {}
	_res_prev = {}


## Sprite3D 的帧号要等 hframes / vframes 设好再设(setter 立即按新乘积校验, 见 RealtimeBattle3DScene._set_anim_sheet 的长注释)。
func _apply_node_props(n: Node, id: int, props: Array) -> void:
	var fr = null
	var spr := n is Sprite3D
	if spr:
		for e in props:
			if str(e[0]) == "hframes" or str(e[0]) == "vframes":
				(n as Sprite3D).frame = 0
				break
	var tr: Array = _truth.get(id, [null, null, null, null])
	for e in props:
		var nm := str(e[0])
		var v = e[1]
		if bool(e[2]):
			v = res.get(int(v))
		if spr and nm == "frame":
			fr = v
			continue
		if nm == "@par":
			## 服务器那边换了父节点(先挪到世界上让粒子放完再删原父节点那一类)
			var np := _parent(int(v[0]), int(v[1]), str(v[2]))
			if n.get_parent() != np and n.is_inside_tree():
				n.reparent(np, false)
				reparents += 1
			continue
		match nm:
			"position": tr[0] = v
			"rotation": tr[1] = v
			"scale": tr[2] = v
			"modulate": tr[3] = v
		n.set(nm, v)
	if fr != null:
		var sp := n as Sprite3D
		sp.frame = clampi(int(fr), 0, maxi(0, sp.hframes * sp.vframes - 1))
	_truth[id] = tr
	_lerped.erase(id)


func _apply_props(o: Object, props: Array) -> void:
	for e in props:
		var v = e[1]
		if bool(e[2]):
			v = res.get(int(v))
		o.set(str(e[0]), v)


# ── 插值 ──
## 上一帧插过值的节点先回到真值(这一帧可能没有下一个采样了)。
func restore() -> void:
	for id in _lerped:
		var n = nodes.get(id)
		var tr = _truth.get(id)
		if n == null or not is_instance_valid(n) or tr == null:
			continue
		var only: Array = _lerped[id]
		var w: Array = [null, null, null, null]
		for i in only:
			w[i] = tr[i]
		_write(n as Node, w)
	_lerped.clear()


## 在「当前真值」和「下一次采样的值」之间插: k ∈ [0, 1]。角度用 lerp_angle; 只插 position / rotation / scale / modulate。
func lerp_to(id: int, props: Array, k: float) -> void:
	var n = nodes.get(id)
	var tr = _truth.get(id)
	if n == null or not is_instance_valid(n) or tr == null:
		return
	var out: Array = [null, null, null, null]   # ★只写这次插的那几项: 别的属性可能已被手机渲染步改过(活单位的立绘), 不许拿旧真值盖回去
	var any := false
	var done: Array = []
	for e in props:
		var nm := str(e[0])
		var v = e[1]
		var i := -1
		match nm:
			"position": i = 0
			"rotation": i = 1
			"scale": i = 2
			"modulate": i = 3
		if i < 0 or tr[i] == null:
			continue
		var a = tr[i]
		if i == 1 and a is Vector3 and v is Vector3:
			out[i] = Vector3(lerp_angle(a.x, v.x, k), lerp_angle(a.y, v.y, k), lerp_angle(a.z, v.z, k))
		elif typeof(a) == typeof(v) and (a is Vector3 or a is Color):
			out[i] = a.lerp(v, k)
		else:
			continue
		any = true
		done.append(i)
	if any:
		_write(n as Node, out)
		_lerped[id] = done


func _write(n: Node, v: Array) -> void:
	if v[0] != null:
		n.set("position", v[0])
	if v[1] != null:
		n.set("rotation", v[1])
	if v[2] != null:
		n.set("scale", v[2])
	if v[3] != null and (n is SpriteBase3D or n is Label3D):
		n.set("modulate", v[3])
