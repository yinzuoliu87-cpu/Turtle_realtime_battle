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

const VERSION := 1
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


## 读游标(解码器用)
class Rd extends RefCounted:
	var b: PackedByteArray
	var p := 0
	var err := ""
	var strs: Array = [""]

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
