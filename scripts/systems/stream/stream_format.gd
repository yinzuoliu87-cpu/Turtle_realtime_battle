class_name StreamFormat
extends RefCounted
## 服务器逐帧直播 · 状态流格式(S1)。方案书 docs/plans/20261019-服务器逐帧直播.md「§2.2 S1 状态流格式 v1」。
##
## 这一个文件管三件事: 格式常量(版本号 / 操作码 / 值标签 / 分块参数)、写字节的编码器 `Enc`、
## 以及读回来的解码器 `decode_chunk`(门禁拿它证明「写出来的每一块都解得开、解到末尾一个字节不多不少」;
## S2 手机播放端从它往下长)。录流器本体在 `stream_recorder.gd`。
##
## ★改格式(加操作码 / 改值标签 / 改量化)必须把 `VERSION` +1, 并同步改方案书 §2.2 那张表。
##   手机端只认同版本的流(方案 R7: 状态流和录像一样绑定版本)。

## v1(S1): 首版。v2(S2, 2026-10-19): 字节语法不变; 单位外观节点进节点层 + 单位合成字段 `@n` + 全局 `seed`(手机选图) ——
##   v1 的流里没有单位外观, v2 的播放器播不出单位, 所以算格式变更。
## v3(S3, 2026-10-19): 资源种类加 `RES_GEN`(程序贴图 / 程序网格带「出处键」= 生成函数 + 参数, 手机调同一个函数现生成);
##   值标签加 `T_F64` / `T_COLF`(出处键的参数要逐位相同: 双精度浮点 / 不量化的颜色)。v2 播放器不认这两样 ⇒ 格式变更。
const VERSION := 3
const MAGIC := "TSTR"
const HEADER_BYTES := 21          # magic 4 + 版本 u16 + 块序号 u32 + 首步 u32 + 步数 u16 + 标志 u8 + 原始长度 u32 —— 不含后面的 ZSTD 负载

const CHUNK_STEPS := 60           # 1 秒一块(60 步)
const KEY_CHUNKS := 10            # 每 10 块的第一块以全量(keyframe)开头 ⇒ 10 秒一个 keyframe
const KEY_STEPS := CHUNK_STEPS * KEY_CHUNKS
const CONT_EVERY := 2             # 连续量(变换 / 颜色 / 标量)每 2 步采一次; 离散量(帧号 / 显隐 / 贴图)逐步
const HZ := 30                    # = 60 步/秒 ÷ CONT_EVERY(方案 U2 定 30 Hz)

## 块标志
const FLAG_KEY := 1               # 本块第一步是 keyframe(字符串表与资源表在本块开头清零, 可以从这一块起独立解码)

## 操作码(块内原始字节流, 一条接一条)
const OP_NODE_NEW := 0x01         # 节点建立: id, 父引用, 类名, n, [属性名, 值]×n(只发与类默认值不同的属性)
const OP_NODE_SET := 0x02         # 节点改属性: id, n, [属性名, 值]×n
const OP_NODE_DEL := 0x03         # 节点删除: id(手机端连同子树一起删)
const OP_RES_DEF := 0x04          # 资源定义: rid, 种类, …(按种类, 见 RES_*)
const OP_EVENT := 0x05            # 一次性事件: 类型, n, [值]×n
const OP_GLOBAL := 0x06           # 全局字段: n, [键, 值]×n
const OP_RES_SET := 0x08          # 资源改属性: rid, n, [属性名, 值]×n
const OP_UNIT_NEW := 0x0A         # 单位登场: idx, 龟 id, 阵营
const OP_UNIT_SET := 0x0B         # 单位字段: idx, n, [键, 值]×n
const OP_UNIT_DEL := 0x0C         # 单位离场: idx
const OP_KEYFRAME := 0xFD         # 紧跟在 STEP 之后: 手机端清空全部镜像状态, 后面跟全量
const OP_STEP := 0xFE             # 一步开始: sim 步号(battle._sim_step_n)

## 父引用种类(NODE_NEW 的第二个字段)
const PAR_WORLD := 0              # 直接挂 _world
const PAR_NODE := 1               # 挂在另一个镜像节点下: + 节点 id
const PAR_UNIT := 2               # 挂在单位外观节点下: + 单位 idx + 单位字典里的键名(如 "sprite")
const PAR_PATH := 3               # 兜底: + 相对 _world 的路径(计数进元数据 parent_by_path)

## 资源种类(RES_DEF 的第二个字段)
const RES_PATH := 0               # 有路径的资源: + 路径
const RES_PARAM := 1              # 参数型资源(材质 / 基本网格 / 渐变 …): + 类名 + n + [属性名, 值]×n(只发非默认)
const RES_GEN_TEX := 2            # 程序生成贴图: + 类名 + 宽 + 高(出处键 S3 再补)
const RES_PROC_MESH := 3          # 程序生成网格: + 类名 + 面数(出处键 / 驱动标量 S3 再补; 顶点不传)
const RES_SHADER := 4             # 内联 shader: + 源码
const RES_OTHER := 5              # 其它无路径资源: + 类名
## S3: 带出处键的程序资源(贴图 / 网格): + 类名 + 出处(「res://脚本路径:静态函数名」) + 上一版 rid(0 = 无; 原地重建的网格换代时手机释放旧的)
##   + 方式 + …: GEN_FULL = n + [参数]×n(资源参数写 T_RES, 子资源先定义; 其余 `Enc.gval` 逐位精确写);
##   GEN_ALIAS = rid(参数与本 keyframe 段里那个 rid 的完全相同: 触手本体与外发光壳共用一份);
##   GEN_DELTA = 参照 rid + n + [参数]×n, 参数可以写 T_SAME(= 参照那一个) / T_BXOR(与参照的等长字节数组逐字节异或)
##     / T_IDIFF(与参照的等长整数数组逐个相减)
##   —— 每步重建的网格(触手 / 触须 / 水带)多半只有一两个参数在变。参照必须在本 keyframe 段里定义过。
##   出处键由生成方在资源上挂 meta `stream_gen` = [脚本路径, 函数名, 参数 Array](见 VfxTex.tag); 手机按白名单(StreamMirror.gen_ok)调同一个函数。
const RES_GEN := 6
## S3: 伪节点类名(NODE_NEW 的类名是它 ⇒ 不是引擎类, 手机按它开对应的全屏演出; 见 StreamRecorder._screen_fx)
const FX_TS_SCREEN := "@ts_screen"
const GEN_META := &"stream_gen"
const GEN_ALIAS := 0
const GEN_FULL := 1
const GEN_DELTA := 2

## 值标签(每个值前一个字节)
const T_NIL := 0
const T_FALSE := 1
const T_TRUE := 2
const T_INT := 3                  # zigzag varint
const T_F32 := 4                  # float32 原样
const T_V2 := 5                   # 2 × float32
const T_POS := 6                  # Vector3 位置: 3 × zigzag varint, 量化 1/128
const T_ROT := 7                  # Vector3 欧拉角(弧度): 3 × zigzag varint, 量化 1/1024
const T_V3 := 8                   # 3 × float32
const T_COLOR := 9                # 4 × zigzag varint, 量化 1/255(允许 >1 的 HDR 颜色)
const T_RECT := 10                # 4 × float32
const T_STR := 11                 # 字符串表引用(见 Enc.s)
const T_RES := 12                 # 资源 rid(varint, 0 = null)
const T_RAW := 13                 # 其它类型: varint 长度 + var_to_bytes
const T_SCALE := 14               # Vector3 缩放: 3 × zigzag varint, 量化 1/4096
const T_F64 := 15                 # S3: float64 原样(出处键参数)
const T_COLF := 16                # S3: 颜色 4 × float32 原样(出处键参数; T_COLOR 是 1/255 量化的)
const T_SAME := 17                # S3: 出处键差分 —— 与参照的同一位参数相同(无负载)
const T_BXOR := 18                # S3: 出处键差分 —— varint 长度 + 与参照字节数组逐字节异或
const T_IDIFF := 19               # S3: 出处键差分 —— varint 个数 + 与参照等长 PackedInt32Array 逐个相减(zigzag varint; 触手中心点)

const Q_POS := 128.0
const Q_ROT := 1024.0
const Q_SCALE := 4096.0
const Q_COL := 255.0


## ═══════════════════════════════════════════════════════════════════════
##  编码器: 一块(60 步)的原始字节。字符串表在 keyframe 块开头清零。
## ═══════════════════════════════════════════════════════════════════════
class Enc extends RefCounted:
	var buf := StreamPeerBuffer.new()
	var strs := {}

	func _init() -> void:
		buf.big_endian = false

	func pos() -> int:
		return buf.get_position()

	func rewind(p: int) -> void:
		buf.seek(p)

	func patch_u8(at: int, v: int) -> void:
		var p := buf.get_position()
		buf.seek(at)
		buf.put_u8(v)
		buf.seek(p)

	func u8(v: int) -> void:
		buf.put_u8(v)

	## 无符号 varint(LEB128)
	func vu(v: int) -> void:
		while v >= 0x80:
			buf.put_u8((v & 0x7f) | 0x80)
			v = v >> 7
		buf.put_u8(v)

	## 有符号: zigzag 再 varint
	func vi(v: int) -> void:
		var z: int = (v << 1) ^ (v >> 63)
		while true:
			var b: int = z & 0x7f
			z = (z >> 7) & 0x01ffffffffffffff
			if z == 0:
				buf.put_u8(b)
				return
			buf.put_u8(b | 0x80)

	## 字符串表: 见过的写 id(≥1); 第一次见写 0 + 长度 + UTF-8, 双方各自按出现顺序编号。
	func s(x: String) -> void:
		var id = strs.get(x)
		if id != null:
			vu(int(id))
			return
		strs[x] = strs.size() + 1
		buf.put_u8(0)
		var b := x.to_utf8_buffer()
		vu(b.size())
		buf.put_data(b)

	func take() -> PackedByteArray:
		var out: PackedByteArray = buf.data_array.slice(0, buf.get_position())
		buf.clear()
		return out

	## 写一个值(按 Variant 类型挑标签)。Vector3 默认按 float32; 位置 / 旋转 / 缩放用下面三个专用的。
	## 资源 / 节点这类对象值由调用方先换成 rid 再调 `res()`, 这里遇到对象一律写 nil。
	func val(v) -> void:
		match typeof(v):
			TYPE_NIL:
				buf.put_u8(T_NIL)
			TYPE_BOOL:
				buf.put_u8(T_TRUE if v else T_FALSE)
			TYPE_INT:
				buf.put_u8(T_INT)
				vi(v)
			TYPE_FLOAT:
				buf.put_u8(T_F32)
				buf.put_float(v)
			TYPE_VECTOR2:
				buf.put_u8(T_V2)
				buf.put_float((v as Vector2).x)
				buf.put_float((v as Vector2).y)
			TYPE_VECTOR3:
				buf.put_u8(T_V3)
				buf.put_float((v as Vector3).x)
				buf.put_float((v as Vector3).y)
				buf.put_float((v as Vector3).z)
			TYPE_COLOR:
				col(v)
			TYPE_RECT2:
				var r: Rect2 = v
				buf.put_u8(T_RECT)
				buf.put_float(r.position.x)
				buf.put_float(r.position.y)
				buf.put_float(r.size.x)
				buf.put_float(r.size.y)
			TYPE_STRING, TYPE_STRING_NAME:
				buf.put_u8(T_STR)
				s(str(v))
			TYPE_OBJECT:
				buf.put_u8(T_NIL)
			_:
				var b := var_to_bytes(v)
				buf.put_u8(T_RAW)
				vu(b.size())
				buf.put_data(b)

	func col(c: Color) -> void:
		buf.put_u8(T_COLOR)
		vi(roundi(clampf(c.r, -1.0e6, 1.0e6) * Q_COL))
		vi(roundi(clampf(c.g, -1.0e6, 1.0e6) * Q_COL))
		vi(roundi(clampf(c.b, -1.0e6, 1.0e6) * Q_COL))
		vi(roundi(clampf(c.a, -1.0e6, 1.0e6) * Q_COL))

	func v3q(tag: int, v: Vector3, q: float) -> void:
		buf.put_u8(tag)
		vi(roundi(clampf(v.x, -1.0e9, 1.0e9) * q))
		vi(roundi(clampf(v.y, -1.0e9, 1.0e9) * q))
		vi(roundi(clampf(v.z, -1.0e9, 1.0e9) * q))

	func res(rid: int) -> void:
		buf.put_u8(T_RES)
		vu(rid)

	## S3 出处键参数: 逐位精确(手机拿它调同一个生成函数, 差一位网格 / 贴图就不是同一份)。
	##   float → 双精度; 颜色 → 4 × float32(不量化); 整数 / 布尔 / 字符串 / Vector2 / Vector3 同 val(本来就无损);
	##   其余(Packed 数组 / Array / Dictionary …)走 var_to_bytes。资源由调用方先换成 rid 写 `res()`。
	func gval(v) -> void:
		match typeof(v):
			TYPE_FLOAT:
				buf.put_u8(T_F64)
				buf.put_double(v)
			TYPE_COLOR:
				var c: Color = v
				buf.put_u8(T_COLF)
				buf.put_float(c.r)
				buf.put_float(c.g)
				buf.put_float(c.b)
				buf.put_float(c.a)
			TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_STRING, TYPE_STRING_NAME:
				val(v)
			_:
				var b := var_to_bytes(v)
				buf.put_u8(T_RAW)
				vu(b.size())
				buf.put_data(b)


## ═══════════════════════════════════════════════════════════════════════
##  解码器: 一块文件 → {ok, err, version, seq, first_step, steps, key, raw_len, ops{op: 次数}, op_bytes{op: 字节},
##  step_marks, events{类型: 次数}}。只解析结构(不建节点), 用来证明格式自洽; 播放端(S2)在这条路上加「应用」。
##  `st` = 跨块状态(字符串表): 同一个 keyframe 段里的块要按顺序解、共用一个 st; 遇到 keyframe 块自动清零。
##  ⇒ 从任意 keyframe 块开始往后解都解得开(拖进度 / 迟到入场), 从段中间开始解不开(字符串表缺前文)。
## ═══════════════════════════════════════════════════════════════════════
static func decode_chunk(data: PackedByteArray, st: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "err": "", "ops": {}, "op_bytes": {}, "events": {}, "step_marks": 0}
	if data.size() < HEADER_BYTES:
		out["err"] = "short"
		return out
	if data.slice(0, 4).get_string_from_ascii() != MAGIC:
		out["err"] = "magic"
		return out
	var hb := StreamPeerBuffer.new()
	hb.big_endian = false
	hb.data_array = data.slice(4, HEADER_BYTES)
	out["version"] = hb.get_u16()
	out["seq"] = hb.get_u32()
	out["first_step"] = hb.get_u32()
	out["steps"] = hb.get_u16()
	out["key"] = (hb.get_u8() & FLAG_KEY) != 0
	var raw_len := int(hb.get_u32())
	out["raw_len"] = raw_len
	if int(out["version"]) != VERSION:
		out["err"] = "version %d != %d" % [int(out["version"]), VERSION]
		return out
	var raw := data.slice(HEADER_BYTES).decompress(raw_len, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_len:
		out["err"] = "zstd %d != %d" % [raw.size(), raw_len]
		return out
	var r := Rd.new(raw)
	if bool(out["key"]) or not st.has("strs"):
		st["strs"] = [""]
	r.strs = st["strs"]
	var ops: Dictionary = out["ops"]
	var obs: Dictionary = out["op_bytes"]
	var evs: Dictionary = out["events"]
	var last_op := -1
	var last_p := 0
	while not r.eof() and r.err == "":
		if last_op >= 0:
			obs[last_op] = int(obs.get(last_op, 0)) + r.p - last_p
		last_p = r.p
		var op := r.u8()
		last_op = op
		ops[op] = int(ops.get(op, 0)) + 1
		match op:
			OP_STEP:
				r.vu()
				out["step_marks"] = int(out["step_marks"]) + 1
			OP_KEYFRAME:
				pass
			OP_NODE_NEW:
				r.vu()
				var pk := r.u8()
				match pk:
					PAR_NODE:
						r.vu()
					PAR_UNIT:
						r.vu()
						r.s()
					PAR_PATH:
						r.s()
				r.s()
				r.props()
			OP_NODE_SET:
				r.vu()
				r.props()
			OP_NODE_DEL, OP_UNIT_DEL:
				r.vu()
			OP_RES_DEF:
				r.vu()
				var kind := r.u8()
				match kind:
					RES_PATH, RES_SHADER, RES_OTHER:
						r.s()
					RES_PARAM:
						r.s()
						r.props()
					RES_GEN_TEX:
						r.s()
						r.vu()
						r.vu()
					RES_PROC_MESH:
						r.s()
						r.vu()
					RES_GEN:
						r.s()
						r.s()
						r.vu()
						var gmode := r.vu()
						if gmode == GEN_ALIAS:
							r.vu()
						else:
							if gmode == GEN_DELTA:
								r.vu()
							var gn := r.vu()
							for _g in range(gn):
								r.val()
					_:
						r.err = "res kind %d" % kind
			OP_RES_SET:
				r.vu()
				r.props()
			OP_EVENT:
				var et := r.s()
				evs[et] = int(evs.get(et, 0)) + 1
				var n := r.vu()
				for _i in range(n):
					r.val()
			OP_GLOBAL:
				r.props()
			OP_UNIT_NEW:
				r.vu()
				r.s()
				r.s()
			OP_UNIT_SET:
				r.vu()
				r.props()
			_:
				r.err = "op 0x%02x @%d" % [op, r.p - 1]
	if last_op >= 0:
		obs[last_op] = int(obs.get(last_op, 0)) + r.p - last_p
	if r.err != "":
		out["err"] = r.err
		return out
	if int(out["step_marks"]) != int(out["steps"]):
		out["err"] = "step marks %d != header %d" % [int(out["step_marks"]), int(out["steps"])]
		return out
	out["ok"] = true
	return out


## ═══════════════════════════════════════════════════════════════════════
##  播放用的完整解码(S2): 一块 → {ok, err, version, seq, first_step, steps, key, list}。
##  list = 按步排好的 [步号, 是否 keyframe, ops]; 每条 op 是一个 Array, 第一个元素是操作码:
##    [GLOBAL, {键: 值}] · [UNIT_NEW, idx, 龟id, 阵营] · [UNIT_SET, idx, {键: 值}] · [UNIT_DEL, idx]
##    [NODE_NEW, id, 父种类, 父id, 父键, 类名, props] · [NODE_SET, id, props] · [NODE_DEL, id]
##    [RES_DEF, rid, 种类, a, b, c](按种类: PATH 路径 / PARAM 类名+props / GEN_TEX 类名+宽+高 / PROC_MESH 类名+面数 / SHADER 源码 / OTHER 类名
##      / GEN 类名+出处+[上一版 rid, [[参数, 是否资源 rid], …] 或 null(别名), 别名 rid])
##    [RES_SET, rid, props] · [EVENT, 类型, 参数 Array]
##  props = [[属性名, 值, 是否资源 rid], …](资源值是 rid 整数, 第三项为 true)。
##  `st` 与 decode_chunk 同一个约定(字符串表跨块、keyframe 块清零)。
## ═══════════════════════════════════════════════════════════════════════
static func parse_chunk(data: PackedByteArray, st: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "err": "", "list": []}
	if data.size() < HEADER_BYTES:
		out["err"] = "short"
		return out
	if data.slice(0, 4).get_string_from_ascii() != MAGIC:
		out["err"] = "magic"
		return out
	var hb := StreamPeerBuffer.new()
	hb.big_endian = false
	hb.data_array = data.slice(4, HEADER_BYTES)
	out["version"] = hb.get_u16()
	out["seq"] = hb.get_u32()
	out["first_step"] = hb.get_u32()
	out["steps"] = hb.get_u16()
	out["key"] = (hb.get_u8() & FLAG_KEY) != 0
	var raw_len := int(hb.get_u32())
	if int(out["version"]) != VERSION:
		out["err"] = "version %d != %d" % [int(out["version"]), VERSION]
		return out
	var raw := data.slice(HEADER_BYTES).decompress(raw_len, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_len:
		out["err"] = "zstd %d != %d" % [raw.size(), raw_len]
		return out
	var r := Rd.new(raw)
	if bool(out["key"]) or not st.has("strs"):
		st["strs"] = [""]
	r.strs = st["strs"]
	var list: Array = out["list"]
	var cur: Array = []
	while not r.eof() and r.err == "":
		var op := r.u8()
		match op:
			OP_STEP:
				cur = [r.vu(), false, []]
				list.append(cur)
			OP_KEYFRAME:
				if not cur.is_empty():
					cur[1] = true
			OP_GLOBAL:
				_push(cur, [op, r.kv()], r)
			OP_UNIT_NEW:
				_push(cur, [op, r.vu(), r.s(), r.s()], r)
			OP_UNIT_SET:
				_push(cur, [op, r.vu(), r.kv()], r)
			OP_UNIT_DEL, OP_NODE_DEL:
				_push(cur, [op, r.vu()], r)
			OP_NODE_NEW:
				var id := r.vu()
				var pk := r.u8()
				var pid := 0
				var pkey := ""
				match pk:
					PAR_NODE:
						pid = r.vu()
					PAR_UNIT:
						pid = r.vu()
						pkey = r.s()
					PAR_PATH:
						pkey = r.s()
				var cls := r.s()
				_push(cur, [op, id, pk, pid, pkey, cls, r.plist()], r)
			OP_NODE_SET, OP_RES_SET:
				_push(cur, [op, r.vu(), r.plist()], r)
			OP_RES_DEF:
				var rid := r.vu()
				var kind := r.u8()
				match kind:
					RES_PATH, RES_SHADER, RES_OTHER:
						_push(cur, [op, rid, kind, r.s(), null, null], r)
					RES_PARAM:
						var c2 := r.s()
						_push(cur, [op, rid, kind, c2, r.plist(), null], r)
					RES_GEN_TEX:
						var c3 := r.s()
						var w := r.vu()
						_push(cur, [op, rid, kind, c3, w, r.vu()], r)
					RES_PROC_MESH:
						var c4 := r.s()
						_push(cur, [op, rid, kind, c4, r.vu(), null], r)
					RES_GEN:
						## [op, rid, 种类, 类名, 出处, [上一版 rid, 参数表 或 null(别名), 别名 / 差分参照 rid, 方式]]
						##   参数表 = [[值, 是否资源 rid, 0 原样 / 1 同参照 / 2 与参照异或 / 3 与参照相减], …]
						var c5 := r.s()
						var gid := r.s()
						var prev := r.vu()
						var gmode := r.vu()
						var gref := 0
						var gargs = null
						if gmode == GEN_ALIAS:
							gref = r.vu()
						else:
							if gmode == GEN_DELTA:
								gref = r.vu()
							gargs = []
							var gn := r.vu()
							for _g in range(gn):
								var gv = r.val()
								var gop := 1 if r.last_tag == T_SAME else (2 if r.last_tag == T_BXOR else (3 if r.last_tag == T_IDIFF else 0))
								(gargs as Array).append([gv, r.last_tag == T_RES, gop])
						_push(cur, [op, rid, kind, c5, gid, [prev, gargs, gref, gmode]], r)
					_:
						r.err = "res kind %d" % kind
			OP_EVENT:
				var et := r.s()
				var n := r.vu()
				var args: Array = []
				for _i in range(n):
					args.append(r.val())
				_push(cur, [op, et, args], r)
			_:
				r.err = "op 0x%02x @%d" % [op, r.p - 1]
	if r.err != "":
		out["err"] = r.err
		return out
	if list.size() != int(out["steps"]):
		out["err"] = "step marks %d != header %d" % [list.size(), int(out["steps"])]
		return out
	out["st"] = st
	out["ok"] = true
	return out


static func _push(cur: Array, op: Array, r: Rd) -> void:
	if cur.is_empty():
		r.err = "op before step"
		return
	(cur[2] as Array).append(op)


## 读游标(解码器用)
class Rd extends RefCounted:
	var b: PackedByteArray
	var p := 0
	var err := ""
	var strs: Array = [""]
	var last_tag := 0             # 最近一次 val() 读到的值标签(播放端据此分辨「资源 rid」和「普通整数」)

	func _init(data: PackedByteArray) -> void:
		b = data

	func eof() -> bool:
		return p >= b.size()

	func u8() -> int:
		if p >= b.size():
			err = "eof @%d" % p
			return 0
		p += 1
		return b[p - 1]

	func vu() -> int:
		var v := 0
		var sh := 0
		while true:
			var x := u8()
			if err != "":
				return 0
			v |= (x & 0x7f) << sh
			if x < 0x80:
				return v
			sh += 7
			if sh > 63:
				err = "varint @%d" % p
				return 0
		return v

	func vi() -> int:
		var z := vu()
		return (z >> 1) ^ -(z & 1)

	func f32() -> float:
		if p + 4 > b.size():
			err = "eof f32 @%d" % p
			return 0.0
		var f := b.decode_float(p)
		p += 4
		return f

	func s() -> String:
		var id := vu()
		if id == 0:
			var n := vu()
			if p + n > b.size():
				err = "eof str @%d" % p
				return ""
			var x := b.slice(p, p + n).get_string_from_utf8()
			p += n
			strs.append(x)
			return x
		if id >= strs.size():
			err = "str id %d >= %d @%d" % [id, strs.size(), p]
			return ""
		return str(strs[id])

	func val():
		var t := u8()
		last_tag = t
		match t:
			T_NIL:
				return null
			T_FALSE:
				return false
			T_TRUE:
				return true
			T_INT:
				return vi()
			T_F32:
				return f32()
			T_V2:
				return Vector2(f32(), f32())
			T_POS:
				return Vector3(vi(), vi(), vi()) / Q_POS
			T_ROT:
				return Vector3(vi(), vi(), vi()) / Q_ROT
			T_SCALE:
				return Vector3(vi(), vi(), vi()) / Q_SCALE
			T_V3:
				return Vector3(f32(), f32(), f32())
			T_COLOR:
				return Color(vi() / Q_COL, vi() / Q_COL, vi() / Q_COL, vi() / Q_COL)
			T_F64:
				if p + 8 > b.size():
					err = "eof f64 @%d" % p
					return 0.0
				var d := b.decode_double(p)
				p += 8
				return d
			T_COLF:
				return Color(f32(), f32(), f32(), f32())
			T_SAME:
				return null
			T_BXOR:
				var nb := vu()
				if p + nb > b.size():
					err = "eof bxor @%d" % p
					return null
				var xb := b.slice(p, p + nb)
				p += nb
				return xb
			T_IDIFF:
				var ni := vu()
				var dv := PackedInt32Array()
				for _k in range(ni):
					dv.append(vi())
					if err != "":
						return null
				return dv
			T_RECT:
				return Rect2(f32(), f32(), f32(), f32())
			T_STR:
				return s()
			T_RES:
				return vu()
			T_RAW:
				var n := vu()
				if p + n > b.size():
					err = "eof raw @%d" % p
					return null
				var v = bytes_to_var(b.slice(p, p + n))
				p += n
				return v
		err = "tag %d @%d" % [t, p - 1]
		return null

	func props() -> void:
		var n := vu()
		for _i in range(n):
			s()
			val()
			if err != "":
				return

	## 播放端: [[名, 值, 是否资源 rid], …]
	func plist() -> Array:
		var out: Array = []
		var n := vu()
		for _i in range(n):
			var k := s()
			var v = val()
			if err != "":
				return out
			out.append([k, v, last_tag == T_RES])
		return out

	## 播放端: {名: 值}(全局 / 单位字段: 没有资源值)
	func kv() -> Dictionary:
		var out := {}
		var n := vu()
		for _i in range(n):
			var k := s()
			var v = val()
			if err != "":
				return out
			out[k] = v
		return out
