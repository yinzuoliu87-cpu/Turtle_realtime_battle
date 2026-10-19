class_name StreamRecorder
extends RefCounted
## 服务器逐帧直播 · 录流器(S1)。方案书 docs/plans/20261019-服务器逐帧直播.md §1 / §2.2。
##
## 三层(方案「路线 C」):
##   ① 单位层: 单位字典里画面要的字段(30 Hz; 存活 / 动作逐步)
##   ② 节点层: **sim 步里**挂进 `_world` 子树的特效节点(单位外观除外) —— 建 / 改 / 删。
##      跟踪的属性 = S0 实测白名单(`TRACKED`) ∪ 所有 Node3D 的 position / rotation / scale / visible;
##      离散量(帧号 / 贴图 / 显隐 / 网格 / 发射)逐步比, 连续量(变换 / 颜色 / 标量)每 2 步(30 Hz)比。
##      其余属性只在建节点时发一次(只发与类默认值不同的), 再在每个 keyframe 与节点删除时**全量核一次**:
##      白名单外的属性变了 ⇒ 报警(计数进元数据 `alarm`, 门禁 verify_stream_whitelist_alarm 要求为 0)。
##   ③ 事件层: 飘字 / 震屏 / 顿帧 / 闪屏 / 音效 / 换路幕布, 由各自唯一的实现函数调 `ev()` 录下。
##
## 挂点(S0 修正): 由驱动方在 `_sim_step` 前后各调一次 `pre_step()` / `post_step()` ——
##   采样在 `_sim_step` **返回之后**, 所以 `sim_stepped` 上同步醒来的协程续段建的节点也算「sim 步生的」。
##   每 2 步用 rd = 2·SIM_DT 跑一次渲染步(方案「渲染步对齐」), 战斗场 `_process` 里那次按真实帧长的渲染步
##   在录流时不跑(`RealtimeBattle3DScene._process` 看 `_replay.stream`)。渲染步不改结果由 verify_stream_capture_inert 证明。
##
## 性能(S0: 朴素录流把最重一局拖到 1.0 倍实时): 每个节点按类走一条**手写的、强类型**的取值路径
##   (不走 ClassDB 属性表、不按名字 get), 先比原值、变了才量化写; 写节点改动用「先写、没变就回退」省掉中间数组。
##
## 输出: `opts.dir` 非空 ⇒ 每块一个文件 `<dir>/<块序号>.bin`(格式见 stream_format.gd), 收尾写 `<dir>/end.json`(元数据)。
##   `opts.keep` = true ⇒ 块字节也留在内存(`chunks`), 门禁拿来解码核对。

const F := preload("res://scripts/systems/stream/stream_format.gd")

## 正在录的那一个(事件总闸从这里找它; 裁判进程一次只跑一局)。
static var cur: StreamRecorder = null

const SIM_DT := 1.0 / 60.0
const PH_OUT := 0
const PH_SIM := 1
const PH_REN := 2

const K_OTHER := 0       # 非 Node3D(只做白名单外核对)
const K_N3D := 1         # 其它 Node3D: 变换 + 显隐
const K_SPRITE := 2
const K_MESH := 3
const K_PART := 4
const K_LABEL := 5

## 跟踪属性(S0 实测「建出来之后真的变过」的 30 种, 2026-10-19; Node3D 的变换 / 显隐另算, 见 N3D_TRACKED)。
## ShaderMaterial 的 shader_parameter/* 全部跟踪(参数表本来就是拿来每步改的)。
## ★加一项 = 改对应的取值路径(`_samp` / `_res_check`) + 方案书 §2.2 白名单那一行。
const TRACKED := {
	"Sprite3D": ["frame", "texture", "hframes", "region_enabled", "flip_h", "modulate", "region_rect", "offset", "pixel_size"],
	"Label3D": ["modulate"],
	"MeshInstance3D": ["mesh"],
	"GPUParticles3D": ["emitting"],
	"StandardMaterial3D": ["albedo_color", "uv1_offset"],
}
const N3D_TRACKED := ["position", "rotation", "scale", "visible"]
const SKIP_PROPS := ["frame_coords", "resource_local_to_scene", "resource_path", "resource_name",
	"resource_scene_unique_id", "script", "draw_pass_2", "draw_pass_3", "draw_pass_4"]

## 单位层字段: S0 静态扫 battle_render.gd + hp_bar.gd 读到的键(2026-10-19)。
## ★方案要求最终名单由「读记录」量出来(S2 门禁 verify_stream_render_fields), 这里先用这份。
const UKEYS := ["_active_cd", "_anemoneShield", "_appearance", "_atk_voff", "_auraEnergy", "_auraShieldVal",
	"_bear_voff", "_body_tint", "_ebb_until", "_ghostShieldVal", "_hhot_owner", "_hidingShellVal", "_hidingShieldVal",
	"_holyShieldVal", "_initDef", "_isEgg", "_lavaRage", "_lavaShieldVal", "_manaShieldVal", "_manual_anim",
	"_mark_until", "_ms_stacks", "_ninja_dash_until", "_ninja_mark_pulse", "_phase_ai_t", "_slam_voff", "_starEnergy",
	"_stoneDefGained", "_tr_active", "_tr_face", "_tr_passive", "_tr_speed", "_tr_throw_t0", "_tr_throw_until",
	"_tr_throw_vec", "_ultShieldVal", "anim_t", "anim_t0", "baseDef", "base_def",
	"baton_zap_until", "bubbleShieldVal", "bubbleStore", "bubble_store", "def", "energy", "energyMaxStorePct",
	"face_right", "flash_col", "flash_t", "height", "hp", "is_big_bear", "is_summon", "is_trainer",
	"magic_shield", "maxChargePct", "maxEnergy", "maxHp", "phase_until", "pos", "rage", "rageMax", "rum_glow_until",
	"shield", "size_mult", "skill_cd", "spd_dbf_until", "star_energy", "stone_init_def", "store_energy",
	"true_fire_until", "type", "urchin_sh_left", "stacks", "_eff_side", "level"]
const UKEYS_STEP := ["alive", "anim_action", "side"]   # 逐步(离散)


class TN extends RefCounted:
	var n: Node
	var iid := 0
	var id := 0
	var kind := K_OTHER
	var cls := ""
	var org := Vector3.ZERO
	var bas := Basis.IDENTITY
	var rot := Vector3.ZERO
	var scl := Vector3.ONE
	var vis := true
	var tex: Object = null
	var fr := 0
	var hf := 1
	var reg := false
	var fh := false
	var mod := Color.WHITE
	var rr := Rect2()
	var off := Vector2.ZERO
	var ps := 0.0
	var mesh: Object = null
	var emit := false
	var mats := PackedInt32Array()
	var base: Array = []      # 报警基线: 与类规格逐项对齐的原值(只核白名单外那些项)
	var base_x := {}          # 报警基线: 规格外的伪属性(MeshInstance3D 的 surface_material_override/i)


var battle: Node
var out_dir := ""
var keep := false
var chunks: Array = []        # keep 时: 每块文件字节
var meta := {}

var _world: Node = null
var _gs: Node = null
var _ph := PH_OUT
var _step_n := 0              # 已录的步数(本录流器自己数; 步号另写 battle._sim_step_n)
var enc := F.Enc.new()
var _seq := 0
var _chunk_first := 0
var _chunk_steps := 0
var _chunk_key := false
var _sn := 0                  # 当前「改属性」操作已写的属性数(0 = 操作头还没写)
var _spc := 0                 # 当前「改属性」操作计数字节的位置
var _node_sets := 0
var _alarm := 0
var _alarm_checked := 0
## 节点层
var _tn: Array = []
var _tn_by_iid := {}
var _pending: Array = []
var _add_step := {}           # 本步新生节点 iid → true(判单位外观用)
var _next_id := 1
var _ua := {}                 # 单位外观节点 iid → [单位字典, 键]
var _ua_n := -1
var _ua_step := -999
## 资源
var _rid_of := {}             # 资源 iid → rid
var _res_ref: Array = [null]  # rid → WeakRef(不替引擎续命: 触手每步一个新网格)
var _res_kind := PackedByteArray([0])
var _res_ck := PackedInt32Array([-1])   # rid → 最近一次比对的步
var _res_ak := PackedInt32Array([-1])   # rid → 最近一次报警核对的步
var _res_sent := {}           # 本 keyframe 段已发过定义的 rid
var _res_track := {}          # rid → PackedStringArray(逐 30Hz 比的属性)
var _res_last := {}           # rid → Array(上次发出的原值)
var _res_base := {}           # rid → Dictionary(白名单外属性 → 比较键)
## 规格缓存
var _specs := {}              # 类名 → Array[[StringName, 类型, 跟踪?]]
var _defs := {}               # 类名 → Array(默认值)
## 单位层
var _uk: Array = []           # idx → 单位字典(见过的全部)
var _ucache: Array = []       # idx → Dictionary(键 → 上次发出的值)
var _ucur: Array = []         # 上一步 battle._units 的顺序
var _ucur_idx := PackedInt32Array()
var _gcache := {}
var _ukeys_all: Array = UKEYS_STEP + UKEYS
var _cur_id := 0
## 事件
var _evs: Array = []
## 计时(微秒)
var _us_render := 0
var _us_units := 0
var _us_new := 0
var _us_nodes := 0
var _us_sample := 0


func _init(b: Node, opts: Dictionary = {}) -> void:
	battle = b
	out_dir = str(opts.get("dir", ""))
	keep = bool(opts.get("keep", false))
	meta = {"format": F.VERSION, "hz": F.HZ, "chunk_steps": F.CHUNK_STEPS, "key_steps": F.KEY_STEPS,
		"chunks": 0, "steps": 0, "first_step": -1, "last_step": -1, "raw_bytes": 0, "z_bytes": 0, "max_chunk_bytes": 0,
		"nodes_new": 0, "nodes_del": 0, "nodes_peak": 0, "node_sets": 0, "res_defs": {}, "events": {},
		"ev_render_dropped": 0, "alarm": 0, "alarm_props": {}, "alarm_first": {}, "alarm_checked": 0,
		"parent_by_path": 0, "unit_owned": 0, "ephemeral": 0, "world_add_outside_sim": 0, "units": 0,
		"us_render": 0, "us_sample": 0, "us_units": 0, "us_new": 0, "us_nodes": 0}


## 开录: 接 node_added, 登记成当前录流器。战斗场已在树里(`_ready` 之后)才调。
func start() -> void:
	_world = battle.get("_world")
	_gs = battle.get_node_or_null("/root/GameState")
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	battle.get_tree().node_added.connect(_on_added)
	cur = self


func pre_step() -> void:
	_ph = PH_SIM


## 一步 sim 返回之后(含 sim_stepped 上同步醒来的协程续段)调。
func post_step() -> void:
	_ph = PH_OUT
	_step_n += 1
	var t0 := Time.get_ticks_usec()
	if _step_n % F.CONT_EVERY == 0:
		_ph = PH_REN
		battle._render._render_step(F.CONT_EVERY * SIM_DT, float(battle._hitstop) > 0.0,
			not (battle._timestop._ts_active as Array).is_empty())
		_ph = PH_OUT
	var t1 := Time.get_ticks_usec()
	_sample(int(battle._sim_step_n))
	_us_render += t1 - t0
	_us_sample += Time.get_ticks_usec() - t1


## 收尾: 封最后一块、写 end.json、卸挂点。`extra` 并进元数据(结果单里的胜方 / 指纹等)。返回元数据。
func finish(extra: Dictionary = {}) -> Dictionary:
	_flush()
	var tr: SceneTree = null
	if is_instance_valid(battle) and battle.is_inside_tree():
		tr = battle.get_tree()
	if tr != null and tr.node_added.is_connected(_on_added):
		tr.node_added.disconnect(_on_added)
	if cur == self:
		cur = null
	meta["steps"] = _step_n
	meta["units"] = _uk.size()
	meta["us_render"] = _us_render
	meta["us_sample"] = _us_sample
	meta["node_sets"] = _node_sets
	meta["alarm"] = _alarm
	meta["alarm_checked"] = _alarm_checked
	meta["us_units"] = _us_units
	meta["us_new"] = _us_new
	meta["us_nodes"] = _us_nodes
	for k in extra:
		meta[k] = extra[k]
	if out_dir != "":
		var f := FileAccess.open(out_dir.path_join("end.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(meta))
			f.close()
	return meta


## ── 事件层 ── 各总闸调: `if StreamRecorder.cur != null: StreamRecorder.cur.ev("float", [...])`
## 渲染步里发生的不录(手机自己跑渲染步, 录了会重一遍), 只计数。
func ev(kind: String, args: Array) -> void:
	if _ph == PH_REN:
		meta["ev_render_dropped"] = int(meta["ev_render_dropped"]) + 1
		return
	_evs.append([kind, args])


func _on_added(n: Node) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if _ph == PH_SIM:
		if _world.is_ancestor_of(n):
			_pending.append(n)
			_add_step[n.get_instance_id()] = true
	elif _ph == PH_OUT and _step_n > 0 and _world.is_ancestor_of(n):
		meta["world_add_outside_sim"] = int(meta["world_add_outside_sim"]) + 1


# ═══════════════════════════════════════════════════════════════════════
#  每步采样
# ═══════════════════════════════════════════════════════════════════════
func _sample(step_n: int) -> void:
	var cont := (_step_n % F.CONT_EVERY) == 0
	var key := false
	if _chunk_steps == 0:
		_chunk_first = step_n
		_chunk_key = (_seq % F.KEY_CHUNKS) == 0
		if _chunk_key:
			key = true
			enc.strs.clear()
			_res_sent.clear()
	if int(meta["first_step"]) < 0:
		meta["first_step"] = step_n
	meta["last_step"] = step_n
	enc.u8(F.OP_STEP)
	enc.vu(step_n)
	if key:
		cont = true
		enc.u8(F.OP_KEYFRAME)
		_gcache.clear()
	_globals(cont)
	var t0 := Time.get_ticks_usec()
	_units(cont, key)
	var t1 := Time.get_ticks_usec()
	_take_pending(key)
	var t2 := Time.get_ticks_usec()
	if key:
		_keyframe_nodes()
	else:
		_nodes(cont)
	_us_units += t1 - t0
	_us_new += t2 - t1
	_us_nodes += Time.get_ticks_usec() - t2
	_events()
	meta["nodes_peak"] = maxi(int(meta["nodes_peak"]), _tn.size())
	_chunk_steps += 1
	if _chunk_steps >= F.CHUNK_STEPS:
		_flush()


func _flush() -> void:
	if _chunk_steps == 0:
		return
	var raw := enc.take()
	var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var h := StreamPeerBuffer.new()
	h.big_endian = false
	h.put_data(F.MAGIC.to_ascii_buffer())
	h.put_u16(F.VERSION)
	h.put_u32(_seq)
	h.put_u32(_chunk_first)
	h.put_u16(_chunk_steps)
	h.put_u8(F.FLAG_KEY if _chunk_key else 0)
	h.put_u32(raw.size())
	var file: PackedByteArray = h.data_array
	file.append_array(z)
	meta["chunks"] = int(meta["chunks"]) + 1
	meta["raw_bytes"] = int(meta["raw_bytes"]) + raw.size()
	meta["z_bytes"] = int(meta["z_bytes"]) + file.size()
	meta["max_chunk_bytes"] = maxi(int(meta["max_chunk_bytes"]), file.size())
	if out_dir != "":
		var f := FileAccess.open(out_dir.path_join("%06d.bin" % _seq), FileAccess.WRITE)
		if f != null:
			f.store_buffer(file)
			f.close()
	if keep:
		chunks.append(file)
	_seq += 1
	_chunk_steps = 0


# ── 全局 ──
func _globals(cont: bool) -> void:
	var p0 := enc.pos()
	enc.u8(F.OP_GLOBAL)
	var pc := enc.pos()
	enc.u8(0)
	var n := 0
	n += _g("dl", str(battle._dl_state))
	n += _g("lane", str(_gs.current_lane) if _gs != null else "")
	n += _g("over", bool(battle._over))
	n += _g("ts", (battle._timestop._ts_active as Array).size())
	if cont:
		n += _g("t", float(battle._t))
		n += _g("hs", float(battle._hitstop))
	if n == 0:
		enc.rewind(p0)
	else:
		enc.patch_u8(pc, n)


func _g(k: String, v) -> int:
	var old = _gcache.get(k)
	if old != null and typeof(old) == typeof(v) and old == v:
		return 0
	_gcache[k] = v
	enc.s(k)
	enc.val(v)
	return 1


# ── 单位层 ──
func _units(cont: bool, key: bool) -> void:
	var ul: Array = battle._units
	var same := (not key) and ul.size() == _ucur.size()
	if same:
		for i in range(ul.size()):
			if not is_same(ul[i], _ucur[i]):
				same = false
				break
	if not same:
		var nidx := PackedInt32Array()
		var seen := {}
		for u in ul:
			var idx := _uidx(u)
			if idx < 0:
				idx = _uk.size()
				_uk.append(u)
				_ucache.append({})
				_unit_new(idx, u)
			elif key:
				_ucache[idx] = {}
				_unit_new(idx, u)
			nidx.append(idx)
			seen[idx] = true
		for oi in _ucur_idx:
			if not key and not seen.has(oi):
				enc.u8(F.OP_UNIT_DEL)
				enc.vu(oi)
		_ucur = ul.duplicate()
		_ucur_idx = nidx
	for i in range(ul.size()):
		_unit_fields(ul[i], _ucur_idx[i], cont)


func _uidx(u) -> int:
	for i in range(_uk.size()):
		if is_same(_uk[i], u):
			return i
	return -1


func _unit_new(idx: int, u: Dictionary) -> void:
	enc.u8(F.OP_UNIT_NEW)
	enc.vu(idx)
	enc.s(str(u.get("id", "")))
	enc.s(str(u.get("side", "")))


## 一个单位这一步变了的字段。操作头等到第一个变化才写(没变的单位一个字节都不写、也不回退)。
## 名单 < 128 项 ⇒ 计数恒为一字节, 可以事后回填。
func _unit_fields(u: Dictionary, idx: int, cont: bool) -> void:
	var c: Dictionary = _ucache[idx]
	var n := 0
	var pc := 0
	for k in (_ukeys_all if cont else UKEYS_STEP):
		var v = u.get(k)
		var t := typeof(v)
		var old = c.get(k)
		if typeof(old) == t and (t == TYPE_NIL or old == v):
			continue
		if t == TYPE_OBJECT or t == TYPE_ARRAY or t == TYPE_CALLABLE:
			continue
		c[k] = v.duplicate() if t == TYPE_DICTIONARY else v
		if n == 0:
			enc.u8(F.OP_UNIT_SET)
			enc.vu(idx)
			pc = enc.pos()
			enc.u8(0)
		enc.s(k)
		enc.val(v)
		n += 1
	if n > 0:
		enc.patch_u8(pc, n)


# ── 节点层 ──
func _take_pending(key: bool) -> void:
	if _pending.is_empty():
		return
	var ul: Array = battle._units
	if ul.size() != _ua_n or _step_n - _ua_step >= 60:
		_refresh_ua()
	for n in _pending:
		if not is_instance_valid(n):
			meta["ephemeral"] = int(meta["ephemeral"]) + 1
			continue
		var nd: Node = n
		if nd.is_queued_for_deletion() or not nd.is_inside_tree():
			meta["ephemeral"] = int(meta["ephemeral"]) + 1
			continue
		var iid := nd.get_instance_id()
		if _tn_by_iid.has(iid):
			continue
		if _unit_owned(nd):
			meta["unit_owned"] = int(meta["unit_owned"]) + 1
			continue
		var t := TN.new()
		t.n = nd
		t.iid = iid
		t.id = _next_id
		_next_id += 1
		t.cls = nd.get_class()
		match t.cls:
			"Sprite3D": t.kind = K_SPRITE
			"MeshInstance3D": t.kind = K_MESH
			"GPUParticles3D": t.kind = K_PART
			"Label3D": t.kind = K_LABEL
			_: t.kind = K_N3D if nd is Node3D else K_OTHER
		_tn.append(t)
		_tn_by_iid[iid] = t
		meta["nodes_new"] = int(meta["nodes_new"]) + 1
		if not key:
			_node_new(t)
	_pending.clear()
	_add_step.clear()


func _refresh_ua() -> void:
	_ua.clear()
	for u in battle._units:
		var d: Dictionary = u
		for k in d:
			var v = d[k]
			if typeof(v) == TYPE_OBJECT and is_instance_valid(v) and v is Node:
				_ua[(v as Node).get_instance_id()] = [d, str(k)]
	_ua_n = (battle._units as Array).size()
	_ua_step = _step_n


## 单位外观: 这个节点(或它某个祖先)挂在单位字典上、而且和它同一步生 ⇒ 单位登场时一起建的, 手机按单位层自己造。
func _unit_owned(n: Node) -> bool:
	var a: Node = n
	while a != null and a != _world:
		var ai := a.get_instance_id()
		if _ua.has(ai) and _add_step.has(ai):
			return true
		a = a.get_parent()
	return false


func _nodes(cont: bool) -> void:
	var j := 0
	for i in range(_tn.size()):
		var t: TN = _tn[i]
		if not is_instance_valid(t.n):
			_node_del(t, false)
			continue
		if t.n.is_queued_for_deletion() or not t.n.is_inside_tree():
			_node_del(t, true)
			continue
		_samp(t, cont)
		_tn[j] = t
		j += 1
	_tn.resize(j)


func _node_del(t: TN, check: bool) -> void:
	if check:
		_alarm_node(t)
	_tn_by_iid.erase(t.iid)
	enc.u8(F.OP_NODE_DEL)
	enc.vu(t.id)
	meta["nodes_del"] = int(meta["nodes_del"]) + 1


## keyframe: 先把所有活节点按「上次以来」核一遍白名单外属性(报警), 再整份重发。
func _keyframe_nodes() -> void:
	var j := 0
	for i in range(_tn.size()):
		var t: TN = _tn[i]
		if not is_instance_valid(t.n):
			_node_del(t, false)
			continue
		if t.n.is_queued_for_deletion() or not t.n.is_inside_tree():
			_node_del(t, true)
			continue
		if not t.base.is_empty() or not t.base_x.is_empty():
			_alarm_node(t)
		_tn[j] = t
		j += 1
	_tn.resize(j)
	_prune_res()
	for t in _tn:
		_node_new(t as TN)


## 一个节点的强类型取值路径。先处理资源型属性(可能要先写资源定义), 再开「改属性」操作。
func _samp(t: TN, cont: bool) -> void:
	var tex_rid := -1
	var mesh_rid := -1
	if t.kind == K_SPRITE:
		var sp0: Sprite3D = t.n
		if sp0.texture != t.tex:
			t.tex = sp0.texture
			tex_rid = _rid(t.tex)
			_ensure(tex_rid)
	elif t.kind == K_MESH:
		var mi0: MeshInstance3D = t.n
		if mi0.mesh != t.mesh:
			t.mesh = mi0.mesh
			mesh_rid = _rid(t.mesh)
			_ensure(mesh_rid)
			t.mats = _collect_mats(t.n)
	_cur_id = t.id
	_sn = 0
	if t.kind != K_OTHER:
		var v3: Node3D = t.n
		if v3.visible != t.vis:
			t.vis = v3.visible
			_k(&"visible")
			enc.val(t.vis)
		if cont:
			var xf := v3.transform
			if xf.origin != t.org:
				t.org = xf.origin
				_k(&"position")
				enc.v3q(F.T_POS, t.org, F.Q_POS)
			if xf.basis != t.bas:
				t.bas = xf.basis
				var rot := v3.rotation
				var scl := v3.scale
				if rot != t.rot:
					t.rot = rot
					_k(&"rotation")
					enc.v3q(F.T_ROT, rot, F.Q_ROT)
				if scl != t.scl:
					t.scl = scl
					_k(&"scale")
					enc.v3q(F.T_SCALE, scl, F.Q_SCALE)
	match t.kind:
		K_SPRITE:
			var sp: Sprite3D = t.n
			if tex_rid >= 0:
				_k(&"texture")
				enc.res(tex_rid)
			if sp.frame != t.fr:
				t.fr = sp.frame
				_k(&"frame")
				enc.val(t.fr)
			if sp.hframes != t.hf:
				t.hf = sp.hframes
				_k(&"hframes")
				enc.val(t.hf)
			if sp.region_enabled != t.reg:
				t.reg = sp.region_enabled
				_k(&"region_enabled")
				enc.val(t.reg)
			if sp.flip_h != t.fh:
				t.fh = sp.flip_h
				_k(&"flip_h")
				enc.val(t.fh)
			if cont:
				if sp.modulate != t.mod:
					t.mod = sp.modulate
					_k(&"modulate")
					enc.col(t.mod)
				if sp.region_rect != t.rr:
					t.rr = sp.region_rect
					_k(&"region_rect")
					enc.val(t.rr)
				if sp.offset != t.off:
					t.off = sp.offset
					_k(&"offset")
					enc.val(t.off)
				if sp.pixel_size != t.ps:
					t.ps = sp.pixel_size
					_k(&"pixel_size")
					enc.val(t.ps)
		K_LABEL:
			if cont:
				var lb: Label3D = t.n
				if lb.modulate != t.mod:
					t.mod = lb.modulate
					_k(&"modulate")
					enc.col(t.mod)
		K_MESH:
			if mesh_rid >= 0:
				_k(&"mesh")
				enc.res(mesh_rid)
		K_PART:
			var gp: GPUParticles3D = t.n
			if gp.emitting != t.emit:
				t.emit = gp.emitting
				_k(&"emitting")
				enc.val(t.emit)
	if _sn > 0:
		enc.patch_u8(_spc, _sn)
		_node_sets += 1
	if cont:
		for rid in t.mats:
			if _res_ck[rid] != _step_n:
				_res_check(rid)


## 写一个属性名; 本节点这一步的第一个变化才写「改属性」操作头(没变的节点零开销)。属性 < 128 项 ⇒ 计数一字节、事后回填。
func _k(name: StringName) -> void:
	if _sn == 0:
		enc.u8(F.OP_NODE_SET)
		enc.vu(_cur_id)
		_spc = enc.pos()
		enc.u8(0)
	enc.s(name)
	_sn += 1


func _cache_tracked(t: TN) -> void:
	if t.kind == K_OTHER:
		return
	var v3: Node3D = t.n
	var xf := v3.transform
	t.org = xf.origin
	t.bas = xf.basis
	t.rot = v3.rotation
	t.scl = v3.scale
	t.vis = v3.visible
	match t.kind:
		K_SPRITE:
			var sp: Sprite3D = t.n
			t.tex = sp.texture
			t.fr = sp.frame
			t.hf = sp.hframes
			t.reg = sp.region_enabled
			t.fh = sp.flip_h
			t.mod = sp.modulate
			t.rr = sp.region_rect
			t.off = sp.offset
			t.ps = sp.pixel_size
		K_LABEL:
			t.mod = (t.n as Label3D).modulate
		K_MESH:
			t.mesh = (t.n as MeshInstance3D).mesh
		K_PART:
			t.emit = (t.n as GPUParticles3D).emitting


## 节点建立(或 keyframe 重发): 只发与类默认值不同的属性; 同时记下白名单外属性的比较键(报警基线)。
func _node_new(t: TN) -> void:
	var n: Node = t.n
	var spec: Array = _spec(t.cls, t.kind != K_OTHER)
	var defs: Array = _defs[t.cls]
	var vals: Array = []
	t.base = []
	t.base.resize(spec.size())
	t.base_x = {}
	for i in range(spec.size()):
		var p: Array = spec[i]
		var v = n.get(p[0])
		t.base[i] = v
		var d = defs[i]
		if typeof(v) == typeof(d) and v == d:
			continue
		if typeof(v) == TYPE_OBJECT:
			var rid := _rid(v)
			if rid > 0:
				_ensure(rid)
				vals.append([p[0], null, rid])
		else:
			vals.append([p[0], v, -1])
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for si in range(mi.get_surface_override_material_count()):
			var nm := StringName("surface_material_override/%d" % si)
			var m := mi.get_surface_override_material(si)
			t.base_x[nm] = m
			if m != null:
				var rid2 := _rid(m)
				_ensure(rid2)
				vals.append([nm, null, rid2])
	_cache_tracked(t)
	t.mats = _collect_mats(n)
	## 父引用(先算好: 可能要写字符串)
	var par: Node = n.get_parent()
	var pk := F.PAR_PATH
	var pid := 0
	var pkey := ""
	if par == _world:
		pk = F.PAR_WORLD
	elif par != null and _tn_by_iid.has(par.get_instance_id()):
		pk = F.PAR_NODE
		pid = (_tn_by_iid[par.get_instance_id()] as TN).id
	elif par != null and _ua.has(par.get_instance_id()):
		var ua: Array = _ua[par.get_instance_id()]
		pid = _uidx(ua[0])
		if pid >= 0:
			pk = F.PAR_UNIT
			pkey = str(ua[1])
	if pk == F.PAR_PATH:
		pkey = str(_world.get_path_to(par)) if par != null else ""
		meta["parent_by_path"] = int(meta["parent_by_path"]) + 1
	enc.u8(F.OP_NODE_NEW)
	enc.vu(t.id)
	enc.u8(pk)
	if pk == F.PAR_NODE:
		enc.vu(pid)
	elif pk == F.PAR_UNIT:
		enc.vu(pid)
		enc.s(pkey)
	elif pk == F.PAR_PATH:
		enc.s(pkey)
	enc.s(t.cls)
	enc.vu(vals.size())
	for e in vals:
		var nm2: StringName = e[0]
		enc.s(nm2)
		if int(e[2]) >= 0:
			enc.res(int(e[2]))
		elif nm2 == &"position":
			enc.v3q(F.T_POS, e[1], F.Q_POS)
		elif nm2 == &"rotation":
			enc.v3q(F.T_ROT, e[1], F.Q_ROT)
		elif nm2 == &"scale":
			enc.v3q(F.T_SCALE, e[1], F.Q_SCALE)
		else:
			enc.val(e[1])


func _collect_mats(n: Node) -> PackedInt32Array:
	var out := PackedInt32Array()
	if n is GeometryInstance3D:
		var gi: GeometryInstance3D = n
		_add_mat(out, gi.material_override)
		_add_mat(out, gi.material_overlay)
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for si in range(mi.get_surface_override_material_count()):
			_add_mat(out, mi.get_surface_override_material(si))
		if mi.mesh != null:
			for si in range(mi.mesh.get_surface_count()):
				_add_mat(out, mi.mesh.surface_get_material(si))
	elif n is GPUParticles3D:
		var gp: GPUParticles3D = n
		_add_mat(out, gp.process_material)
		if gp.draw_pass_1 != null:
			for si in range(gp.draw_pass_1.get_surface_count()):
				_add_mat(out, gp.draw_pass_1.surface_get_material(si))
	return out


func _add_mat(out: PackedInt32Array, m: Material) -> void:
	if m == null:
		return
	var rid := _rid(m)
	_ensure(rid)
	if rid > 0 and not out.has(rid):
		out.append(rid)


# ── 资源 ──
func _rid(o) -> int:
	if o == null or not is_instance_valid(o) or not (o is Resource):
		return 0
	var iid: int = (o as Object).get_instance_id()
	var r = _rid_of.get(iid)
	if r != null:
		return int(r)
	var rid := _res_ref.size()
	_rid_of[iid] = rid
	_res_ref.append(weakref(o))
	_res_kind.append(_kind_of(o))
	_res_ck.append(-1)
	_res_ak.append(-1)
	return rid


static func _kind_of(r: Resource) -> int:
	if r.resource_path != "" and r.resource_path.find("::") < 0:
		return F.RES_PATH
	if r is Texture2D:
		if r is AtlasTexture or r is GradientTexture1D or r is GradientTexture2D or r is CurveTexture:
			return F.RES_PARAM
		if r is ImageTexture:
			return F.RES_GEN_TEX
		return F.RES_OTHER
	if r is PrimitiveMesh:
		return F.RES_PARAM
	if r is ArrayMesh or r is ImmediateMesh:
		return F.RES_PROC_MESH
	if r is Shader:
		return F.RES_SHADER
	if r is Material or r is Gradient or r is Curve or r is SpriteFrames or r is Font or r is LabelSettings:
		return F.RES_PARAM
	return F.RES_OTHER


## 资源定义(本 keyframe 段第一次被引用时写)。子资源先定义。
func _ensure(rid: int) -> void:
	if rid <= 0 or _res_sent.has(rid):
		return
	_res_sent[rid] = true
	var o = (_res_ref[rid] as WeakRef).get_ref()
	var kind := int(_res_kind[rid])
	if o == null:
		kind = F.RES_OTHER
	var rd: Dictionary = meta["res_defs"]
	rd[kind] = int(rd.get(kind, 0)) + 1
	match kind:
		F.RES_PATH:
			enc.u8(F.OP_RES_DEF)
			enc.vu(rid)
			enc.u8(kind)
			enc.s((o as Resource).resource_path)
		F.RES_PARAM:
			var vals := _res_param_vals(rid, o)
			enc.u8(F.OP_RES_DEF)
			enc.vu(rid)
			enc.u8(kind)
			enc.s((o as Object).get_class())
			enc.vu(vals.size())
			for e in vals:
				enc.s(str(e[0]))
				if int(e[2]) >= 0:
					enc.res(int(e[2]))
				else:
					enc.val(e[1])
		F.RES_GEN_TEX:
			var tx: Texture2D = o
			enc.u8(F.OP_RES_DEF)
			enc.vu(rid)
			enc.u8(kind)
			enc.s(tx.get_class())
			enc.vu(tx.get_width())
			enc.vu(tx.get_height())
		F.RES_PROC_MESH:
			var m: Mesh = o
			enc.u8(F.OP_RES_DEF)
			enc.vu(rid)
			enc.u8(kind)
			enc.s(m.get_class())
			enc.vu(m.get_surface_count())
		F.RES_SHADER:
			enc.u8(F.OP_RES_DEF)
			enc.vu(rid)
			enc.u8(kind)
			enc.s((o as Shader).code)
		_:
			enc.u8(F.OP_RES_DEF)
			enc.vu(rid)
			enc.u8(F.RES_OTHER)
			enc.s((o as Object).get_class() if o != null else "")


## 参数型资源的非默认属性(子资源先 _ensure), 顺便登记跟踪属性的原值与报警基线。返回 [[名, 值, 子 rid 或 -1]]。
func _res_param_vals(rid: int, o: Object) -> Array:
	var vals: Array = []
	var base: Array = []
	var bx := {}
	var track := PackedStringArray()
	var last: Array = []
	var cls := o.get_class()
	if o is ShaderMaterial:
		var sm: ShaderMaterial = o
		var srid := _rid(sm.shader)
		_ensure(srid)
		if srid > 0:
			vals.append(["shader", null, srid])
		bx[&"shader"] = sm.shader
		bx[&"render_priority"] = sm.render_priority
		bx[&"next_pass"] = sm.next_pass
		for p in sm.get_property_list():
			var nm: String = str((p as Dictionary)["name"])
			if not nm.begins_with("shader_parameter/"):
				continue
			var v = sm.get(nm)
			track.append(nm)
			last.append(v)
			_push_val(vals, nm, v)
	else:
		var spec: Array = _spec(cls, false)
		var defs: Array = _defs[cls]
		base.resize(spec.size())
		for i in range(spec.size()):
			var p: Array = spec[i]
			var v = o.get(p[0])
			base[i] = v
			if bool(p[2]):
				track.append(str(p[0]))
				last.append(v)
			var d = defs[i]
			if typeof(v) == typeof(d) and v == d:
				continue
			_push_val(vals, str(p[0]), v)
	_res_base[rid] = [cls, base, bx]
	if not track.is_empty():
		_res_track[rid] = track
		_res_last[rid] = last
	return vals


func _push_val(vals: Array, nm: String, v) -> void:
	if typeof(v) == TYPE_OBJECT:
		var r := _rid(v)
		if r > 0:
			_ensure(r)
			vals.append([nm, null, r])
	else:
		vals.append([nm, v, -1])


## 30 Hz 比材质的跟踪属性(同一步同一份材质只比一次)。
func _res_check(rid: int) -> void:
	if _res_ck[rid] == _step_n:
		return
	_res_ck[rid] = _step_n
	var tr = _res_track.get(rid)
	if tr == null:
		return
	var o = (_res_ref[rid] as WeakRef).get_ref()
	if o == null:
		return
	var names: PackedStringArray = tr
	var last: Array = _res_last[rid]
	var ch: Array = []
	for i in range(names.size()):
		var v = (o as Object).get(names[i])
		var old = last[i]
		if typeof(v) == typeof(old) and v == old:
			continue
		last[i] = v
		_push_val(ch, names[i], v)
	if ch.is_empty():
		return
	enc.u8(F.OP_RES_SET)
	enc.vu(rid)
	enc.vu(ch.size())
	for e in ch:
		enc.s(str(e[0]))
		if int(e[2]) >= 0:
			enc.res(int(e[2]))
		elif typeof(e[1]) == TYPE_COLOR:
			enc.col(e[1])
		else:
			enc.val(e[1])


## 报警: 白名单外属性和基线不同 ⇒ 计数 + 记哪一类的哪个属性(基线跟着更新, 同一次变化只报一次)。
## 原值比(不量化): 没人碰的属性不会自己漂, 碰过的就该报。
func _alarm_node(t: TN) -> void:
	_alarm_checked += 1
	var spec: Array = _specs[t.cls]
	var b: Array = t.base
	for i in range(mini(spec.size(), b.size())):
		var p: Array = spec[i]
		if bool(p[2]):
			continue
		var v = t.n.get(p[0])
		var o = b[i]
		if typeof(v) != typeof(o) or v != o:
			b[i] = v
			_alarm_hit("%s.%s" % [t.cls, str(p[0])])
	for nm in t.base_x:
		var v2 = t.n.get(nm)
		var o2 = t.base_x[nm]
		if typeof(v2) != typeof(o2) or v2 != o2:
			t.base_x[nm] = v2
			_alarm_hit("%s.%s" % [t.cls, str(nm)])
	for rid in t.mats:
		_alarm_res(rid)


func _alarm_res(rid: int) -> void:
	if _res_ak[rid] == _step_n:
		return
	_res_ak[rid] = _step_n
	var base = _res_base.get(rid)
	if base == null:
		return
	var o = (_res_ref[rid] as WeakRef).get_ref()
	if o == null:
		return
	var cls: String = (base as Array)[0]
	var b: Array = (base as Array)[1]
	var bx: Dictionary = (base as Array)[2]
	if not b.is_empty():
		var spec: Array = _specs[cls]
		for i in range(mini(spec.size(), b.size())):
			var p: Array = spec[i]
			if bool(p[2]):
				continue
			var v = (o as Object).get(p[0])
			var ov = b[i]
			if typeof(v) != typeof(ov) or v != ov:
				b[i] = v
				_alarm_hit("%s.%s" % [cls, str(p[0])])
	for nm in bx:
		var v2 = (o as Object).get(nm)
		var o2 = bx[nm]
		if typeof(v2) != typeof(o2) or v2 != o2:
			bx[nm] = v2
			_alarm_hit("%s.%s" % [cls, str(nm)])


func _alarm_hit(key: String) -> void:
	_alarm += 1
	var ap: Dictionary = meta["alarm_props"]
	ap[key] = int(ap.get(key, 0)) + 1
	var af: Dictionary = meta["alarm_first"]
	if not af.has(key):
		af[key] = int(battle._sim_step_n)


## keyframe 时丢掉已被引擎释放的资源的缓存(特效节点各带一份材质, 不清会一直涨)。
func _prune_res() -> void:
	for d in [_res_base, _res_track, _res_last]:
		var dead: Array = []
		for rid in (d as Dictionary):
			if (_res_ref[int(rid)] as WeakRef).get_ref() == null:
				dead.append(rid)
		for rid in dead:
			(d as Dictionary).erase(rid)


## 类的属性规格(ClassDB 存盘属性, 到 Node3D / Resource 为止) + 默认值。Node3D 的变换 / 显隐手工补在最前面。
func _spec(cls: String, is3d: bool) -> Array:
	if _specs.has(cls):
		return _specs[cls]
	var out: Array = []
	var defs: Array = []
	if is3d:
		out.append([&"position", TYPE_VECTOR3, true])
		out.append([&"rotation", TYPE_VECTOR3, true])
		out.append([&"scale", TYPE_VECTOR3, true])
		out.append([&"visible", TYPE_BOOL, true])
		defs.append_array([Vector3.ZERO, Vector3.ZERO, Vector3.ONE, true])
	var tracked: Array = TRACKED.get(cls, [])
	var stop := ["Node3D", "Node", "Resource", "RefCounted", "Object", ""]
	var c := cls
	while not (c in stop):
		for p in ClassDB.class_get_property_list(c, true):
			var d: Dictionary = p
			if (int(d["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var nm := str(d["name"])
			if nm in SKIP_PROPS or int(d["type"]) == TYPE_NIL:
				continue
			out.append([StringName(nm), int(d["type"]), nm in tracked])
			defs.append(ClassDB.class_get_property_default_value(cls, nm))   # ★按具体类问: 抽象父类(GeometryInstance3D / BaseMaterial3D …)问出来全是 null
		c = str(ClassDB.get_parent_class(c))
	_specs[cls] = out
	_defs[cls] = defs
	return out


# ── 事件 ──
func _events() -> void:
	if _evs.is_empty():
		return
	var ec: Dictionary = meta["events"]
	for e in _evs:
		var kind: String = e[0]
		var args: Array = e[1]
		ec[kind] = int(ec.get(kind, 0)) + 1
		enc.u8(F.OP_EVENT)
		enc.s(kind)
		enc.vu(args.size())
		for a in args:
			enc.val(a)
	_evs.clear()
