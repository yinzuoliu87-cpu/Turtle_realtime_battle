extends Node
## _probe_stream_s0 —— 方案书 docs/plans/20261019-服务器逐帧直播.md 的 S0 探针(下划线开头, 不进门禁; 只量数, 不改生产代码)。
##
## 做法: 战斗场照常实例化, 但**关掉它自己的 _process**, 由本探针逐步驱动:
##   每步 `_phase = SIM` 包住 `battle._sim_step(...)`(含 sim_stepped 上醒来的协程续段 —— 它们在 emit 里同步执行)
##   ⇒ `SceneTree.node_added` 能准确分出「sim 步里生的 / 渲染步里生的 / 两者之外(第三条钟)生的」节点。
##   录流原型(Enc)按方案 §0 三层结构真的把字节写出来(单位层 + 节点层 + 事件层), 每 60 步一块 ZSTD 压缩。
##
## 环境变量:
##   S0_SET  = det(DetScenarios 全部场景) | ref(三路打满的裁判局) | find(给 ref 挑打满三路的种子)
##   S0_MODE = size(体积 + 节点统计 + 造不出镜像清单, 带 get_stack 溯源与第三条钟检测) | perf(录流开销: 三种配置轮流跑)
##   S0_REPS = perf 每种配置重复几遍(取最快, 默认 2)
##   S0_POOL = ghost_pool.json 的绝对路径(ref 的第二局用真实快照池)
##   S0_K    = 每个引擎帧推几步 sim(默认 60, 模拟裁判机一帧推一大批)
## 输出: 以 [S0] 开头的行。

const SC := preload("res://scripts/referee/det_scenarios.gd")
const Backend := preload("res://scripts/net/backend.gd")
const SIM_DT := 1.0 / 60.0
const CHUNK_STEPS := 60
const KEY_STEPS := 600

const PH_OUT := 0
const PH_SIM := 1
const PH_REN := 2
const PH_NAMES := ["外(第三条钟)", "sim步", "渲染步"]

## 单位层字段: 静态扫 battle_render.gd + hp_bar.gd 读到的键(2026-10-19), 去掉节点引用 / 渲染自己写的中间量。
## ★方案要求最终名单由「读记录」量出来(S1 门禁 verify_stream_render_fields); 这里只为估体积。
const UKEYS := ["_active_cd", "_anemoneShield", "_appearance", "_atk_voff", "_auraEnergy", "_auraShieldVal",
	"_bear_voff", "_body_tint", "_ebb_until", "_ghostShieldVal", "_hhot_owner", "_hidingShellVal", "_hidingShieldVal",
	"_holyShieldVal", "_initDef", "_isEgg", "_lavaRage", "_lavaShieldVal", "_manaShieldVal", "_manual_anim",
	"_mark_until", "_ms_stacks", "_ninja_dash_until", "_ninja_mark_pulse", "_phase_ai_t", "_slam_voff", "_starEnergy",
	"_stoneDefGained", "_tr_active", "_tr_face", "_tr_passive", "_tr_speed", "_tr_throw_t0", "_tr_throw_until",
	"_tr_throw_vec", "_ultShieldVal", "alive", "anim_action", "anim_t", "anim_t0", "baseDef", "base_def",
	"baton_zap_until", "bubbleShieldVal", "bubbleStore", "bubble_store", "def", "energy", "energyMaxStorePct",
	"face_right", "flash_col", "flash_t", "height", "hp", "id", "is_big_bear", "is_summon", "is_trainer",
	"magic_shield", "maxChargePct", "maxEnergy", "maxHp", "phase_until", "pos", "rage", "rageMax", "rum_glow_until",
	"shield", "side", "size_mult", "skill_cd", "spd_dbf_until", "star_energy", "stone_init_def", "store_energy",
	"true_fire_until", "type", "urchin_sh_left", "stacks", "_eff_side", "level"]

var _phase := PH_OUT
var _tr: Tracker = null
var _audio: Node = null


func _on_added(n: Node) -> void:
	if _tr != null:
		_tr.on_added(n, _phase)


# ═══════════════════════════════════════════════════════════════════════
#  Tracker: 节点分类 / 计数 / 资源表 / 造不出镜像的标记
# ═══════════════════════════════════════════════════════════════════════
class Tracker extends RefCounted:
	var bt: Node
	var audio: Node
	var audit := false
	var step := 0
	var encs: Array = []
	## 计数
	var adds := {}                 # "相位|根|类" → 次数
	var tracked: Array = []        # [Node, iid, site]  (sim 步里生在 _world 下、不属单位外观)
	var tracked_ids := {}          # iid → true
	var pending: Array = []        # 本步新生(sim·world)待分类
	var ui_pending: Array = []     # 本步新生(sim·ui)
	var sfx_pending: Array = []    # 本步新生(sim·Audio 播放器)
	var add_step := {}             # iid → 生出那一步
	var unit_owned := 0
	var site_of := {}              # iid → "file:line <- file:line"
	var out_world_sites := {}      # 第三条钟在 world 下生节点: site → 次数
	var ren_world := {}            # 渲染步在 world 下生节点: 类 → 次数
	## 并发
	var conc_sum := 0.0
	var conc_n := 0
	var conc_peak := 0
	var conc_peak_cls := {}
	var conc_cls_sum := {}
	var census_peak := 0
	var census_sum := 0.0
	var census_n := 0
	var census_peak_detail := {}
	var origin := {}               # iid → 相位(world 下所有新生节点)
	## 资源表
	var res_ids := {}              # 资源 iid → rid
	var res_objs: Array = [null]   # rid → Resource(rid 0 = null)
	var res_kind: Array = [""]     # rid → path | param | gen_tex | proc_mesh | inline_shader | other
	var res_spec: Array = [[]]     # rid → 属性表
	var res_site: Array = [""]
	var spec_cache := {}
	var gen_px := 0
	## 造不出镜像
	var flags := {}                # "标记|site" → 节点数
	var flag_nodes := {}           # 标记 → 节点数
	var ext_changes := {}          # "site|属性" → 次数(第三条钟改属性)
	var ext_removed := {}          # site → 次数(第三条钟删节点)
	var dyn_mesh := {}             # site → 程序网格变化次数
	var unsup := {}                # "类.属性" → 变化次数(编码器不认识的类型)
	var pchg := {}                 # "类.属性" → 变化次数(30Hz 编码器)
	var wl := {}                   # 白名单(perf 的 lean 配置): "类.属性" → true; 空 = 不过滤
	## 事件
	var ev := {"float": 0, "ui_other": 0, "sfx": 0, "shake": 0, "hitstop": 0}
	var ui_other_cls := {}
	var last_shake_t := -1.0
	var last_shake_amp := 0.0
	var last_hitstop := 0.0
	## 单位
	var uattach := {}
	var uattach_n := -1

	func _init(b: Node, au: Node, aud: bool) -> void:
		bt = b
		audio = au
		audit = aud

	func _site() -> String:
		var st: Array = get_stack()
		var picked: Array = []
		for f in st:
			var src: String = str((f as Dictionary).get("source", ""))
			if src.find("_probe_stream") >= 0:
				continue
			picked.append("%s:%d" % [src.replace("res://", ""), int((f as Dictionary).get("line", 0))])
			if picked.size() >= 2:
				break
		return " <- ".join(picked)

	func _root(n: Node) -> String:
		var w = bt.get("_world")
		if w != null and is_instance_valid(w) and (w as Node).is_ancestor_of(n):
			return "world"
		var ui = bt.get("_ui_layer")
		if ui != null and is_instance_valid(ui) and (ui as Node).is_ancestor_of(n):
			return "ui"
		if audio != null and audio.is_ancestor_of(n):
			return "audio"
		if bt.is_ancestor_of(n):
			return "battle"
		return "out"

	func on_added(n: Node, ph: int) -> void:
		var r := _root(n)
		if r == "out":
			return
		var k := "%d|%s|%s" % [ph, r, n.get_class()]
		adds[k] = int(adds.get(k, 0)) + 1
		var iid := n.get_instance_id()
		if r == "world":
			origin[iid] = ph
			if ph == PH_SIM:
				pending.append(n)
				add_step[iid] = step
				if audit:
					site_of[iid] = _site()
			elif ph == PH_OUT and audit:
				var s := _site()
				out_world_sites[s] = int(out_world_sites.get(s, 0)) + 1
			elif ph == PH_REN:
				ren_world[n.get_class()] = int(ren_world.get(n.get_class(), 0)) + 1
		elif r == "ui" and ph == PH_SIM:
			ui_pending.append(n)
		elif r == "audio" and ph == PH_SIM and n is AudioStreamPlayer:
			sfx_pending.append(n)

	## 属性表(按类缓存): [名, 类型, 连续?, 量化]
	func spec_for_class(cls: String, is3d: bool) -> Array:
		if spec_cache.has(cls):
			return spec_cache[cls]
		var out: Array = []
		if is3d:
			out.append(["position", TYPE_VECTOR3, true, 128.0, true])
			out.append(["rotation", TYPE_VECTOR3, true, 1024.0, true])
			out.append(["scale", TYPE_VECTOR3, true, 256.0, true])
			out.append(["visible", TYPE_BOOL, false, 0.0, true])
		var stop := ["Node3D", "Node", "Resource", "RefCounted", "Object", ""]
		var skip := ["frame_coords", "resource_local_to_scene", "resource_path", "resource_name",
			"resource_scene_unique_id", "script", "draw_pass_2", "draw_pass_3", "draw_pass_4"]
		var c := cls
		while not (c in stop):
			for p in ClassDB.class_get_property_list(c, true):
				var d: Dictionary = p
				if (int(d["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
					continue
				if str(d["name"]) in skip:
					continue
				var t := int(d["type"])
				if t == TYPE_NIL:
					continue
				out.append([str(d["name"]), t, t == TYPE_FLOAT or t == TYPE_VECTOR2 or t == TYPE_VECTOR3, 256.0,
					wl.is_empty() or wl.has("%s.%s" % [cls, str(d["name"])])])
			c = str(ClassDB.get_parent_class(c))
		spec_cache[cls] = out
		return out

	func rid_of(o) -> int:
		if o == null or not (o is Object) or not is_instance_valid(o):
			return 0
		if not (o is Resource):
			return 0
		var iid: int = (o as Object).get_instance_id()
		if res_ids.has(iid):
			return int(res_ids[iid])
		var r: Resource = o
		var rid := res_objs.size()
		res_ids[iid] = rid
		res_objs.append(r)
		var kind := "other"
		var spec: Array = []
		if r.resource_path != "" and r.resource_path.find("::") < 0:
			kind = "path"
		elif r is Texture2D:
			if r is AtlasTexture and (r as AtlasTexture).atlas != null and (r as AtlasTexture).atlas.resource_path != "":
				kind = "param"
				spec = spec_for_class(r.get_class(), false)
			elif r is CompressedTexture2D:
				kind = "path"
			else:
				kind = "gen_tex"
				gen_px += (r as Texture2D).get_width() * (r as Texture2D).get_height()
		elif r is PrimitiveMesh:
			kind = "param"
			spec = spec_for_class(r.get_class(), false)
		elif r is ArrayMesh or r is ImmediateMesh:
			kind = "proc_mesh"
		elif r is ShaderMaterial:
			kind = "param"
			spec = [["shader", TYPE_OBJECT, false, 0.0, wl.is_empty() or wl.has("ShaderMaterial.shader")], ["render_priority", TYPE_INT, false, 0.0, wl.is_empty()], ["next_pass", TYPE_OBJECT, false, 0.0, wl.is_empty()]]
			for p in r.get_property_list():
				var nm: String = str((p as Dictionary)["name"])
				if nm.begins_with("shader_parameter/"):
					var t := int((p as Dictionary)["type"])
					spec.append([nm, t, t == TYPE_FLOAT or t == TYPE_VECTOR2 or t == TYPE_VECTOR3, 256.0,
						wl.is_empty() or wl.has("ShaderMaterial." + nm)])
		elif r is Shader:
			kind = "inline_shader"
		elif r is Material or r is Gradient or r is Curve or r is SpriteFrames or r is Font or r is LabelSettings:
			kind = "param"
			spec = spec_for_class(r.get_class(), false)
		res_kind.append(kind)
		res_spec.append(spec)
		res_site.append("")
		return rid

	## 节点首次被采样时: 走一遍它挂的资源图, 收集「造不出镜像」的标记。
	func classify(n: Node, site: String) -> void:
		var fl := {}
		if n.get_script() != null:
			fl["自带脚本节点"] = true
		var known := ["Node3D", "Sprite3D", "AnimatedSprite3D", "MeshInstance3D", "GPUParticles3D", "CPUParticles3D",
			"Label3D", "OmniLight3D", "SpotLight3D", "DirectionalLight3D"]
		if not (n.get_class() in known):
			fl["非常见节点类:" + n.get_class()] = true
		var seen := {}
		var stack: Array = []
		for p in spec_for_class(n.get_class(), n is Node3D):
			if int(p[1]) == TYPE_OBJECT:
				stack.append(n.get(str(p[0])))
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			for si in range((n as MeshInstance3D).get_surface_override_material_count()):
				stack.append((n as MeshInstance3D).get_surface_override_material(si))
		while not stack.is_empty():
			var o = stack.pop_back()
			var rid := rid_of(o)
			if rid == 0 or seen.has(rid):
				continue
			seen[rid] = true
			if res_site[rid] == "":
				res_site[rid] = site
			match str(res_kind[rid]):
				"gen_tex": fl["程序生成贴图(" + (o as Object).get_class() + ")"] = true
				"proc_mesh": fl["程序生成网格(" + (o as Object).get_class() + ")"] = true
				"inline_shader": fl["内联 shader(无路径·要传源码)"] = true
				"other": fl["其他无路径资源(" + (o as Object).get_class() + ")"] = true
			for p in (res_spec[rid] as Array):
				if int(p[1]) == TYPE_OBJECT:
					stack.append((o as Object).get(str(p[0])))
			if o is PrimitiveMesh or o is ArrayMesh:
				var m: Mesh = o
				for si in range(m.get_surface_count()):
					stack.append(m.surface_get_material(si))
		for f in fl:
			var k := "%s|%s" % [f, site]
			flags[k] = int(flags.get(k, 0)) + 1
			flag_nodes[f] = int(flag_nodes.get(f, 0)) + 1

	func _refresh_uattach() -> void:
		var units: Array = bt.get("_units")
		uattach.clear()
		for u in units:
			for kk in (u as Dictionary):
				var v = (u as Dictionary)[kk]
				if typeof(v) == TYPE_OBJECT and is_instance_valid(v) and v is Node:
					uattach[(v as Node).get_instance_id()] = true
		uattach_n = units.size()

	func _is_unit_owned(n: Node) -> bool:
		var st := int(add_step.get(n.get_instance_id(), -1))
		var w: Node = bt.get("_world")
		var a: Node = n
		while a != null and a != w:
			var ai := a.get_instance_id()
			if uattach.has(ai) and int(add_step.get(ai, -2)) == st:
				return true
			a = a.get_parent()
		return false

	## 每步一次(sim 步 + 可能的渲染步之后)。cont = 这一步是否 30Hz 连续量采样点(由各编码器自己判)。
	func sample() -> void:
		step += 1
		## 新节点分类
		if not pending.is_empty():
			if (bt.get("_units") as Array).size() != uattach_n or step % 60 == 0:
				_refresh_uattach()
			for n in pending:
				if not is_instance_valid(n) or not (n as Node).is_inside_tree():
					continue
				if _is_unit_owned(n):
					unit_owned += 1
					continue
				var iid: int = (n as Node).get_instance_id()
				if tracked_ids.has(iid):
					continue
				var site := str(site_of.get(iid, ""))
				tracked.append([n, iid, site])
				tracked_ids[iid] = true
				if audit:
					classify(n, site)
			pending.clear()
		## 事件(一次性)
		var evs: Array = []
		for n in ui_pending:
			if not is_instance_valid(n):
				continue
			var nd: Node = n
			if nd.get_parent() != bt.get("_ui_layer"):
				continue
			if nd.is_in_group("battle_ui_transient") and (nd is Label or nd is HBoxContainer):
				ev["float"] += 1
				var txt := ""
				var col := Color.WHITE
				if nd is Label:
					txt = (nd as Label).text
					col = (nd as Label).modulate
				else:
					for ch in nd.get_children():
						if ch is Label:
							txt = (ch as Label).text
				evs.append(["float", txt, col, (nd as Control).position])
			else:
				ev["ui_other"] += 1
				ui_other_cls[nd.get_class()] = int(ui_other_cls.get(nd.get_class(), 0)) + 1
				evs.append(["ui", nd.get_class()])
		ui_pending.clear()
		for p in sfx_pending:
			if is_instance_valid(p):
				ev["sfx"] += 1
				var sp: AudioStreamPlayer = p
				evs.append(["sfx", sp.stream.resource_path if sp.stream != null else ""])
		sfx_pending.clear()
		var sh_t: float = float(bt.get("_shake_t"))
		var sh_a: float = float(bt.get("_shake_amp"))
		if sh_t == 0.0 and (last_shake_t != 0.0 or sh_a > last_shake_amp + 1.0e-6):
			ev["shake"] += 1
			evs.append(["shake", sh_a])
		last_shake_t = sh_t
		last_shake_amp = sh_a
		var hs: float = float(bt.get("_hitstop"))
		if hs > last_hitstop + 1.0e-9:
			ev["hitstop"] += 1
			evs.append(["hitstop", hs])
		last_hitstop = hs
		## 编码
		var alive_list: Array = []
		var keep: Array = []
		for t in tracked:
			var n = t[0]
			if not is_instance_valid(n) or (n as Node).is_queued_for_deletion() or not (n as Node).is_inside_tree() 					or (audit and _ancestor_queued(n)):
				for e in encs:
					(e as Enc).node_del(int(t[1]))
				tracked_ids.erase(int(t[1]))
				continue
			keep.append(t)
			alive_list.append(t)
		tracked = keep
		for e in encs:
			(e as Enc).frame(step, alive_list, evs)
		## 并发统计(每 2 步一次)
		if step % 2 == 0:
			var c := alive_list.size()
			conc_sum += c
			conc_n += 1
			var bycls := {}
			for t in alive_list:
				var cl: String = (t[0] as Node).get_class()
				bycls[cl] = int(bycls.get(cl, 0)) + 1
				conc_cls_sum[cl] = float(conc_cls_sum.get(cl, 0.0)) + 1.0
			if c > conc_peak:
				conc_peak = c
				conc_peak_cls = bycls
		if audit and step % 60 == 0:
			census()

	func _ancestor_queued(n: Node) -> bool:
		var w: Node = bt.get("_world")
		var a: Node = n.get_parent()
		while a != null and a != w:
			if a.is_queued_for_deletion():
				return true
			a = a.get_parent()
		return false

	## world 子树全量普查(含开局就有的地图、渲染步生的、单位外观)
	func census() -> void:
		var w: Node = bt.get("_world")
		if w == null:
			return
		var by := {}
		var cnt := 0
		var st: Array = [w]
		while not st.is_empty():
			var n: Node = st.pop_back()
			for ch in n.get_children():
				st.append(ch)
				cnt += 1
				var o := int(origin.get(ch.get_instance_id(), -1))
				var on := "开局前已在" if o < 0 else str(PH_NAMES[o])
				var k := "%s|%s" % [on, ch.get_class()]
				by[k] = int(by.get(k, 0)) + 1
		census_sum += cnt
		census_n += 1
		if cnt > census_peak:
			census_peak = cnt
			census_peak_detail = by

	## 引擎帧开头(本探针推 sim 之前)调: 上一帧末尾采样之后, 只有「第三条钟」(SceneTree tween / 计时器 / 节点自己的 _process / AnimationPlayer)
	## 会动这些节点。拿 30Hz 编码器的缓存比一遍。
	func check_external() -> void:
		if encs.is_empty():
			return
		var e: Enc = encs[0]
		for t in tracked:
			var n = t[0]
			var site := str(t[2])
			if not is_instance_valid(n) or (n as Node).is_queued_for_deletion() or not (n as Node).is_inside_tree():
				ext_removed[site] = int(ext_removed.get(site, 0)) + 1
				continue
			for pn in e.diff_names(n, int(t[1])):
				var k := "%s|%s" % [site, pn]
				ext_changes[k] = int(ext_changes.get(k, 0)) + 1


# ═══════════════════════════════════════════════════════════════════════
#  Enc: 录流原型编码器(方案 §1 / §2 的三层; 连续量每 cont_every 步, 离散量逐步)
# ═══════════════════════════════════════════════════════════════════════
class Enc extends RefCounted:
	var tr: Tracker
	var cont_every := 2
	var name := ""
	var buf := StreamPeerBuffer.new()
	var whole := PackedByteArray()
	var raw_total := 0
	var z_total := 0
	var z_chunks := 0
	var cat := {"header": 0, "unit": 0, "unit_spawn": 0, "node_create": 0, "node_update": 0, "node_del": 0,
		"res_def": 0, "res_update": 0, "event": 0, "global": 0, "keyframe": 0}
	var ncache := {}        # 节点 iid → Array(量化后的上次发送值)
	var rcache := {}        # rid → Array
	var rsent := {}         # rid → true
	var r_this := {}        # 本步已比过的 rid
	var strs := {}
	var units: Array = []   # 已知单位字典(is_same 匹配)
	var ucache: Array = []  # 并行: Dictionary 键 → 量化值
	var gcache := {}
	var steps_in_chunk := 0
	var per_sec_peak := 0
	var sec_bytes := 0
	var write_us := 0

	func _init(t: Tracker, ce: int, nm: String) -> void:
		tr = t
		cont_every = ce
		name = nm
		buf.big_endian = false

	func _var(v: int) -> void:
		var z: int = (v << 1) ^ (v >> 63)
		while true:
			var b: int = z & 0x7f
			z = (z >> 7) & 0x01ffffffffffffff
			if z == 0:
				buf.put_u8(b)
				return
			buf.put_u8(b | 0x80)

	func _str(s: String) -> void:
		if strs.has(s):
			_var(int(strs[s]))
			return
		strs[s] = strs.size() + 1
		_var(0)
		var b := s.to_utf8_buffer()
		_var(b.size())
		buf.put_data(b)

	static func qv(v, t: int, q: float):
		if v == null:
			return null
		match t:
			TYPE_FLOAT:
				var f: float = v
				if is_nan(f) or is_inf(f): return 1 << 40
				return roundi(clampf(f, -1.0e12, 1.0e12) * q)
			TYPE_VECTOR2:
				var a: Vector2 = v
				return Vector2i(roundi(clampf(a.x, -1e8, 1e8) * q), roundi(clampf(a.y, -1e8, 1e8) * q))
			TYPE_VECTOR3:
				var b: Vector3 = v
				return Vector3i(roundi(clampf(b.x, -1e8, 1e8) * q), roundi(clampf(b.y, -1e8, 1e8) * q), roundi(clampf(b.z, -1e8, 1e8) * q))
			TYPE_COLOR:
				var c: Color = v
				return Vector4i(roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0), roundi(c.a * 255.0))
			TYPE_RECT2:
				var r: Rect2 = v
				return Vector4i(roundi(r.position.x * 4.0), roundi(r.position.y * 4.0), roundi(r.size.x * 4.0), roundi(r.size.y * 4.0))
		return v

	func _wv(x) -> void:
		match typeof(x):
			TYPE_INT: _var(x)
			TYPE_BOOL: buf.put_u8(1 if x else 0)
			TYPE_VECTOR2I:
				_var(x.x)
				_var(x.y)
			TYPE_VECTOR3I:
				_var(x.x)
				_var(x.y)
				_var(x.z)
			TYPE_VECTOR4I:
				_var(x.x)
				_var(x.y)
				_var(x.z)
				_var(x.w)
			TYPE_STRING, TYPE_STRING_NAME: _str(str(x))
			TYPE_NIL: buf.put_u8(0)
			_:
				var b := var_to_bytes(x)
				_var(b.size())
				buf.put_data(b)

	## 取一个属性的量化值; 资源 → rid(第一次见就先发定义)
	func _get_q(o: Object, p: Array):
		var t := int(p[1])
		var v = o.get(str(p[0]))
		if t == TYPE_OBJECT:
			var rid := tr.rid_of(v)
			if rid != 0:
				_ensure_res(rid)
			return rid
		return qv(v, t, float(p[3]))

	func _ensure_res(rid: int) -> void:
		if rsent.has(rid):
			return
		rsent[rid] = true
		var p0 := buf.get_position()
		buf.put_u8(4)
		_var(rid)
		var kind: String = tr.res_kind[rid]
		var o: Resource = tr.res_objs[rid]
		_str(kind)
		match kind:
			"path":
				_str(o.resource_path)
			"param":
				_str(o.get_class())
				var vals: Array = []
				var spec: Array = tr.res_spec[rid]
				for p in spec:
					vals.append(_get_q(o, p))
				_var(vals.size())
				for x in vals:
					_wv(x)
				rcache[rid] = vals
			"inline_shader":
				var code: String = (o as Shader).code
				_str(code)
			"proc_mesh":
				_str(o.get_class())
				buf.put_data(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))   # 出处键占位(函数 id + 参数) 12 B
				rcache[rid] = _mesh_sig(o)
			_:
				_str(o.get_class())
				buf.put_data(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))   # 出处键占位 8 B
		cat["res_def"] += buf.get_position() - p0

	func _mesh_sig(o) -> Array:
		var m: Mesh = o
		var a := m.get_aabb()
		var sig: Array = [m.get_surface_count(), qv(a.position, TYPE_VECTOR3, 64.0), qv(a.size, TYPE_VECTOR3, 64.0)]
		if m is ArrayMesh and m.get_surface_count() > 0:
			sig.append((m as ArrayMesh).surface_get_array_len(0))
		return sig

	## 参数型资源逐步比(每步每个 rid 最多一次)
	func _diff_res(rid: int, cont: bool) -> void:
		if rid == 0 or r_this.has(rid):
			return
		r_this[rid] = true
		var kind: String = tr.res_kind[rid]
		var o: Resource = tr.res_objs[rid]
		if kind == "proc_mesh":
			var sig := _mesh_sig(o)
			if sig != (rcache.get(rid, []) as Array):
				rcache[rid] = sig
				var site: String = tr.res_site[rid]
				tr.dyn_mesh[site] = int(tr.dyn_mesh.get(site, 0)) + 1
				var p0 := buf.get_position()
				buf.put_u8(9)
				_var(rid)
				buf.put_data(PackedByteArray([0, 0, 0, 0, 0, 0]))   # 驱动标量占位(方案: 传驱动它的几个标量) 6 B
				cat["res_update"] += buf.get_position() - p0
			return
		if kind != "param":
			return
		var spec: Array = tr.res_spec[rid]
		var old: Array = rcache.get(rid, [])
		var ch: Array = []
		var subs: Array = []
		for i in range(spec.size()):
			var p: Array = spec[i]
			var t := int(p[1])
			if (bool(p[2]) and not cont) or (not bool(p[4]) and t != TYPE_OBJECT):
				continue
			var x = _get_q(o, p)
			if t == TYPE_OBJECT:
				subs.append(x)
			if i >= old.size() or typeof(old[i]) != typeof(x) or old[i] != x:
				ch.append([i, x])
				if name == "30Hz":
					var pk := "%s.%s" % [o.get_class(), str(p[0])]
					tr.pchg[pk] = int(tr.pchg.get(pk, 0)) + 1
				if i < old.size():
					old[i] = x
				if not (t in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, TYPE_RECT2, TYPE_OBJECT, TYPE_STRING, TYPE_STRING_NAME]):
					var uk := "%s.%s" % [o.get_class(), str(p[0])]
					tr.unsup[uk] = int(tr.unsup.get(uk, 0)) + 1
		rcache[rid] = old
		if not ch.is_empty():
			var p0 := buf.get_position()
			buf.put_u8(8)
			_var(rid)
			_var(ch.size())
			for c in ch:
				_var(int(c[0]))
				_wv(c[1])
			cat["res_update"] += buf.get_position() - p0
		for s in subs:
			_diff_res(int(s), cont)

	## 节点在某一刻和缓存不同的属性名(第三条钟检测用; 不写字节、不改缓存)
	func diff_names(n: Node, iid: int) -> Array:
		var out: Array = []
		var old: Array = ncache.get(iid, [])
		if old.is_empty():
			return out
		var spec := tr.spec_for_class(n.get_class(), n is Node3D)
		for i in range(mini(spec.size(), old.size())):
			var p: Array = spec[i]
			var x
			if int(p[1]) == TYPE_OBJECT:
				x = tr.rid_of(n.get(str(p[0])))
			else:
				x = qv(n.get(str(p[0])), int(p[1]), float(p[3]))
			if typeof(old[i]) != typeof(x) or old[i] != x:
				out.append(str(p[0]))
		return out

	func node_del(iid: int) -> void:
		if not ncache.has(iid):
			return
		ncache.erase(iid)
		var p0 := buf.get_position()
		buf.put_u8(3)
		_var(iid & 0xffffff)
		cat["node_del"] += buf.get_position() - p0

	func _node(n: Node, iid: int, cont: bool, full: bool) -> void:
		var spec := tr.spec_for_class(n.get_class(), n is Node3D)
		var p0 := buf.get_position()
		var objs: Array = []
		if full or not ncache.has(iid):
			var vals: Array = []
			for p in spec:
				var x = _get_q(n, p)
				vals.append(x)
				if int(p[1]) == TYPE_OBJECT:
					objs.append(x)
			buf.put_u8(1)
			_var(iid & 0xffffff)
			var par: Node = n.get_parent()
			_var((par.get_instance_id() & 0xffffff) if par != null else 0)
			_str(n.get_class())
			for x in vals:
				_wv(x)
			ncache[iid] = vals
			cat["keyframe" if full else "node_create"] += buf.get_position() - p0
		else:
			var old: Array = ncache[iid]
			var ch: Array = []
			for i in range(spec.size()):
				var p: Array = spec[i]
				if (bool(p[2]) and not cont) or (not bool(p[4]) and int(p[1]) != TYPE_OBJECT):
					continue
				var x = _get_q(n, p)
				if int(p[1]) == TYPE_OBJECT:
					objs.append(x)
				if typeof(old[i]) != typeof(x) or old[i] != x:
					ch.append([i, x])
					old[i] = x
					if name == "30Hz":
						var pk := "%s.%s" % [n.get_class(), str(p[0])]
						tr.pchg[pk] = int(tr.pchg.get(pk, 0)) + 1
					var t := int(p[1])
					if not (t in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, TYPE_RECT2, TYPE_OBJECT, TYPE_STRING, TYPE_STRING_NAME]):
						var uk := "%s.%s" % [n.get_class(), str(p[0])]
						tr.unsup[uk] = int(tr.unsup.get(uk, 0)) + 1
			if not ch.is_empty():
				buf.put_u8(2)
				_var(iid & 0xffffff)
				_var(ch.size())
				for c in ch:
					_var(int(c[0]))
					_wv(c[1])
				cat["node_update"] += buf.get_position() - p0
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh != null:
				for si in range(mi.get_surface_override_material_count()):
					var sm := mi.get_surface_override_material(si)
					if sm != null:
						objs.append(tr.rid_of(sm))
						_ensure_res(int(objs[-1]))
				for si in range(mi.mesh.get_surface_count()):
					var mm := mi.mesh.surface_get_material(si)
					if mm != null:
						objs.append(tr.rid_of(mm))
						_ensure_res(int(objs[-1]))
		for r in objs:
			_diff_res(int(r), cont)

	func _unit_vals(u: Dictionary, cont: bool, full: bool, old: Dictionary) -> Array:
		var ch: Array = []
		for ki in range(UKEYS.size()):
			var k: String = UKEYS[ki]
			if not u.has(k):
				continue
			var v = u[k]
			var t := typeof(v)
			if t == TYPE_DICTIONARY:
				var d: Dictionary = v
				for sk in d:
					var sv = d[sk]
					if typeof(sv) == TYPE_FLOAT or typeof(sv) == TYPE_INT:
						var key := "%s.%s" % [k, str(sk)]
						var x = qv(float(sv), TYPE_FLOAT, 16.0)
						if full or not old.has(key) or old[key] != x:
							old[key] = x
							ch.append([ki, x])
				continue
			if t == TYPE_OBJECT or t == TYPE_ARRAY or t == TYPE_CALLABLE:
				continue
			if (t == TYPE_FLOAT or t == TYPE_VECTOR2) and not cont and not full:
				continue
			var q := 16.0
			var x = qv(v, t, q)
			if full or not old.has(k) or typeof(old[k]) != typeof(x) or old[k] != x:
				old[k] = x
				ch.append([ki, x])
		return ch

	func frame(step: int, alive: Array, evs: Array) -> void:
		var t0 := Time.get_ticks_usec()
		var cont := (step % cont_every) == 0
		var key := (step % KEY_STEPS) == 1
		r_this.clear()
		var p0 := buf.get_position()
		buf.put_u8(0xFE)
		_var(step)
		cat["header"] += buf.get_position() - p0
		## 全局
		p0 = buf.get_position()
		var g := {"dl": str(tr.bt.get("_dl_state")), "over": bool(tr.bt.get("_over")),
			"ts": ((tr.bt.get("_timestop") as Object).get("_ts_active") as Array).size()}
		if cont:
			g["hs"] = qv(float(tr.bt.get("_hitstop")), TYPE_FLOAT, 60.0)
		var gch: Array = []
		for k in g:
			if key or not gcache.has(k) or gcache[k] != g[k]:
				gcache[k] = g[k]
				gch.append(g[k])
		if not gch.is_empty():
			buf.put_u8(6)
			_var(gch.size())
			for x in gch:
				_wv(x)
		cat["global"] += buf.get_position() - p0
		## 单位层
		var ul: Array = tr.bt.get("_units")
		for u in ul:
			var idx := -1
			for i in range(units.size()):
				if is_same(units[i], u):
					idx = i
					break
			var fresh := idx < 0
			if fresh:
				units.append(u)
				ucache.append({})
				idx = units.size() - 1
				p0 = buf.get_position()
				buf.put_u8(10)
				_var(idx)
				_str(str((u as Dictionary).get("id", "")))
				_str(str((u as Dictionary).get("side", "")))
				buf.put_data(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))   # 外观 spec 占位(皮肤/等级/装备图标) 16 B
				cat["unit_spawn"] += buf.get_position() - p0
			p0 = buf.get_position()
			var ch := _unit_vals(u, cont, fresh or key, ucache[idx])
			if not ch.is_empty():
				buf.put_u8(11)
				_var(idx)
				_var(ch.size())
				for c in ch:
					_var(int(c[0]))
					_wv(c[1])
			cat["keyframe" if (key and not fresh) else "unit"] += buf.get_position() - p0
		## 节点层
		for t in alive:
			_node(t[0], int(t[1]), cont, key and ncache.has(int(t[1])))
		## 事件层
		p0 = buf.get_position()
		for e in evs:
			buf.put_u8(5)
			_str(str(e[0]))
			match str(e[0]):
				"float":
					_str(str(e[1]))
					_wv(qv(e[2], TYPE_COLOR, 0.0))
					_wv(qv(e[3], TYPE_VECTOR2, 1.0))
					buf.put_u8(0)   # 类型 / 暴击
				"ui", "sfx":
					_str(str(e[1]))
					buf.put_u8(0)
					buf.put_u8(0)
				_:
					_wv(qv(float(e[1]), TYPE_FLOAT, 64.0))
		cat["event"] += buf.get_position() - p0
		steps_in_chunk += 1
		if steps_in_chunk >= CHUNK_STEPS:
			flush()
		write_us += Time.get_ticks_usec() - t0

	func flush() -> void:
		if buf.get_position() == 0:
			return
		var raw: PackedByteArray = buf.data_array.slice(0, buf.get_position())
		raw_total += raw.size()
		var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
		z_total += z.size()
		z_chunks += 1
		per_sec_peak = maxi(per_sec_peak, z.size())
		whole.append_array(raw)
		buf.clear()
		steps_in_chunk = 0


# ═══════════════════════════════════════════════════════════════════════
#  驱动
# ═══════════════════════════════════════════════════════════════════════
## 配置: "ref" = 现在的裁判机(一帧推 K 步, 只跑一次渲染步) | "align" = 每 2 步跑一次渲染步(rd = 2·SIM_DT, 方案「渲染步对齐」)
##       | "rec" = align + 录流(30Hz; size 模式另加 20Hz 编码器与审计)
func _drive(bt, total_steps: int, cfg: String, audit: bool, is_ref: bool) -> Dictionary:
	var K: int = int(OS.get_environment("S0_K")) if OS.get_environment("S0_K") != "" else 60
	var rr = bt.get("_replay")
	if cfg == "rec" or cfg == "lean":
		_tr = Tracker.new(bt, _audio, audit)
		if cfg == "lean":
			for ln in FileAccess.get_file_as_string(OS.get_environment("S0_WL")).split("
"):
				if ln.strip_edges() != "":
					_tr.wl[ln.strip_edges()] = true
		_tr.encs.append(Enc.new(_tr, 2, "30Hz"))
		if audit:
			_tr.encs.append(Enc.new(_tr, 3, "20Hz"))
			_tr.encs.append(Enc.new(_tr, 1, "60Hz"))
	var steps := 0
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var ended := false
	while not ended:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(bt) or not bt.is_inside_tree():
			break
		if _tr != null and audit:
			_tr.check_external()
		for _i in range(K):
			if is_ref and (bool(rr.finished) or steps >= 40000):
				ended = true
				break
			if not is_ref and steps >= total_steps:
				ended = true
				break
			var frozen: bool = float(bt._hitstop) > 0.0
			var in_ts: bool = not (bt._timestop._ts_active as Array).is_empty()
			_phase = PH_SIM
			bt._sim_step(SIM_DT, frozen, in_ts)
			_phase = PH_OUT
			steps += 1
			if cfg != "ref" and steps % 2 == 0:
				_phase = PH_REN
				bt._render._render_step(2.0 * SIM_DT, float(bt._hitstop) > 0.0, not (bt._timestop._ts_active as Array).is_empty())
				_phase = PH_OUT
			if _tr != null:
				_tr.sample()
		bt._frame_sim_dt = SIM_DT if not is_ref else 0.0
		bt._render_alpha = 0.0
		if cfg == "ref":
			_phase = PH_REN
			bt._render._render_step(SIM_DT, float(bt._hitstop) > 0.0, not (bt._timestop._ts_active as Array).is_empty())
			_phase = PH_OUT
	var us := Time.get_ticks_usec() - t0
	var out := {"steps": steps, "us": us, "frames": frames}
	if _tr != null:
		for e in _tr.encs:
			(e as Enc).flush()
		out["tr"] = _tr
		_tr = null
	return out


## DetScenarios 的建场(与 det_scenarios.gd run() 同一套), 然后交给 _drive。
func _run_det(sc: Dictionary, cfg: String, audit: bool) -> Dictionary:
	OS.set_environment("TURTLE_SEED", str(sc["seed"]))
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	s._debug._edit_clear()
	var lo: Dictionary = sc.get("loadouts", {})
	if not lo.is_empty():
		var gs2 = get_node_or_null("/root/GameState")
		for k in lo:
			gs2.loadouts[str(k)] = int(lo[k])
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in (sc["pairs"] as Array):
		var pid: String = str(p[0])
		if pid.begins_with("__minion__"):
			var bits: PackedStringArray = pid.split(":")
			s._edit_minion_role = str(bits[1]) if bits.size() > 1 else "front"
			pid = "__minion__"
		var u: Dictionary = s._debug._edit_place_unit(pid, str(p[1]), Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
		if (p as Array).size() > 5 and bool(p[5]):
			u["active_skills"] = s._resolve_active_skills(pid, false)
			u["skill_idx"] = 0
	s._debug._edit_start_battle()
	s.set_process(false)
	var r: Dictionary = await _drive(s, int(sc["frames"]), cfg, audit, false)
	r["fp"] = SC.fp(s).md5_text().left(12)
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return r


# ── 裁判局(三路打满) ──
const LEVEL := 6

func _snap_mirror(gs) -> Dictionary:
	## 与 tests/verify_referee_job_roundtrip.gd `_snap_a(gs, false)` 同一份(镜像那组: 打满三路)
	gs.reset_dual_lane()
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for pid in gs.season_leaders:
		pe[pid] = [{"id": str(shop[k % shop.size()]), "star": 1}]
		k += 1
	gs.persistent_equipped = pe
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": "basic", "off": [-100, 160]},
			{"kind": "minion", "role": "front", "equips": [], "off": [150, -200]},
			{"kind": "minion", "role": "back", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": "stone", "equips": [], "off": [60, -120]},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
	}
	gs.loadouts = {"basic": 1, "stone": 2}
	gs.trainer_skill = "hook"
	gs.season_level = LEVEL
	return Backend.build_ghost_snapshot("g_s0_a", {"name": "甲方", "avatar": "basic", "id": "g_s0_a"})


func _pool_snaps() -> Array:
	var path := OS.get_environment("S0_POOL")
	if path == "" or not FileAccess.file_exists(path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return []
	var bb: Dictionary = (d as Dictionary).get("by_battles", {})
	var out: Array = []
	var ks: Array = bb.keys()
	ks.sort_custom(func(a, b): return int(float(a)) > int(float(b)))
	for k in ks:
		for g in (bb[k] as Array):
			out.append(g)
	return out


func _job(a: Dictionary, b: Dictionary, seed: int) -> Dictionary:
	var j := {"v": 1, "job_id": 1, "match_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "mode": "gauntlet",
		"key": {"week": 1, "account": "t"}, "seed": seed, "client_version": ReplayRecorder.client_version(),
		"level": LEVEL, "a": a, "b": b}
	return JSON.parse_string(JSON.stringify(j))


## 裁判局: RefereeRunner 原样跑(真入口), 但战斗场 ready 之后关掉它的 _process, 由 _drive 推。
func _run_ref(job: Dictionary, cfg: String, audit: bool) -> Dictionary:
	var holder := {}
	var res: Dictionary = await RefereeRunner.run(self, job, func(bt) -> void:
		bt.ready.connect(func() -> void:
			bt.set_process(false)
			holder["bt"] = bt
			_ref_drive_start(bt, cfg, audit, holder), CONNECT_ONE_SHOT))
	while not holder.has("drv"):
		await get_tree().process_frame
	var r: Dictionary = holder["drv"]
	r["ok"] = bool(res.get("ok", false))
	r["fights"] = int(res.get("fights", 0))
	r["fp"] = str(res.get("digest", ""))
	r["winner"] = str(res.get("winner", ""))
	r["err"] = str(res.get("error", ""))
	return r


func _ref_drive_start(bt: Node, cfg: String, audit: bool, holder: Dictionary) -> void:
	if _audio != null and _audio.get("mute_sfx") != null:
		_audio.mute_sfx = false     # 裁判机静音 ⇒ 不生播放器; 量事件层要它生
	var r: Dictionary = await _drive(bt, 0, cfg, audit, true)
	holder["drv"] = r


func _ref_jobs() -> Array:
	var gs = get_node_or_null("/root/GameState")
	var jobs: Array = []
	var a := _snap_mirror(gs)
	var b: Dictionary = a.duplicate(true)
	b["profile"] = {"name": "乙方", "avatar": "stone", "id": "g_s0_b"}
	b["ghost_id"] = "g_s0_b"
	jobs.append(["镜像快照(verify_referee_job_roundtrip 同款)", a, b, int(OS.get_environment("S0_SEED_M")) if OS.get_environment("S0_SEED_M") != "" else 2000023])
	var pool := _pool_snaps()
	if pool.size() >= 2:
		var ia := int(OS.get_environment("S0_PA")) if OS.get_environment("S0_PA") != "" else 0
		var ib := int(OS.get_environment("S0_PB")) if OS.get_environment("S0_PB") != "" else 1
		var sd := int(OS.get_environment("S0_SEED_P")) if OS.get_environment("S0_SEED_P") != "" else 2000023
		var pa: Dictionary = (pool[ia] as Dictionary).duplicate(true)
		var pb: Dictionary = (pool[ib] as Dictionary).duplicate(true)
		jobs.append(["真实快照池 #%d vs #%d(%s / %s)" % [ia, ib, str(pa.get("leaders")), str(pb.get("leaders"))], pa, pb, sd])
	return jobs


# ═══════════════════════════════════════════════════════════════════════
#  报告
# ═══════════════════════════════════════════════════════════════════════
var _agg := {}

func _acc(k: String, v: float) -> void:
	_agg[k] = float(_agg.get(k, 0.0)) + v

func _accd(k: String, d: Dictionary) -> void:
	var m: Dictionary = _agg.get(k, {})
	for kk in d:
		m[kk] = int(m.get(kk, 0)) + int(d[kk])
	_agg[k] = m

func _top(d: Dictionary, n: int) -> Array:
	var ks: Array = d.keys()
	ks.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	return ks.slice(0, n)

func _report_one(tag: String, r: Dictionary) -> void:
	var tr: Tracker = r["tr"]
	var steps := int(r["steps"])
	var secs := steps / 60.0
	print("[S0] ── %s ── 步 %d (%.1f 游戏秒) 指纹 %s" % [tag, steps, secs, str(r.get("fp", ""))])
	print("[S0]   节点层并发(sim 步生·world·不含单位外观): 峰值 %d / 平均 %.1f · 峰值时按类 %s" % [tr.conc_peak, tr.conc_sum / maxf(1.0, tr.conc_n), str(tr.conc_peak_cls)])
	print("[S0]   world 全量普查(每 60 步): 峰值 %d / 平均 %.1f · 单位外观排除 %d 个" % [tr.census_peak, tr.census_sum / maxf(1.0, tr.census_n), tr.unit_owned])
	print("[S0]   新建: %s" % str(tr.adds))
	print("[S0]   事件: %s · 其他 UI 类 %s" % [str(tr.ev), str(tr.ui_other_cls)])
	for e in tr.encs:
		var en: Enc = e
		print("[S0]   编码 %s: 原始 %d B(%.2f KB/s) · ZSTD 分块 %d B(%.2f KB/s, %d 块, 最大块 %d B) · 整段 ZSTD %d B · 分类 %s · 编码耗时 %.1f ms" % [
			en.name, en.raw_total, en.raw_total / 1024.0 / maxf(0.01, secs), en.z_total, en.z_total / 1024.0 / maxf(0.01, secs),
			en.z_chunks, en.per_sec_peak, en.whole.compress(FileAccess.COMPRESSION_ZSTD).size(), str(en.cat), en.write_us / 1000.0])
		_acc("raw_" + en.name, en.raw_total)
		_acc("z_" + en.name, en.z_total)
		_acc("zw_" + en.name, en.whole.compress(FileAccess.COMPRESSION_ZSTD).size())
		_accd("cat_" + en.name, en.cat)
	_acc("steps", steps)
	_agg["peak"] = maxi(int(_agg.get("peak", 0)), tr.conc_peak)
	_acc("conc_sum", tr.conc_sum)
	_acc("conc_n", tr.conc_n)
	_agg["census_peak"] = maxi(int(_agg.get("census_peak", 0)), tr.census_peak)
	_acc("census_sum", tr.census_sum)
	_acc("census_n", tr.census_n)
	_accd("conc_cls", tr.conc_cls_sum)
	_accd("adds", tr.adds)
	_accd("ev", tr.ev)
	_accd("flags", tr.flags)
	_accd("flag_nodes", tr.flag_nodes)
	_accd("ext_changes", tr.ext_changes)
	_accd("ext_removed", tr.ext_removed)
	_accd("out_world", tr.out_world_sites)
	_accd("dyn_mesh", tr.dyn_mesh)
	_accd("unsup", tr.unsup)
	_accd("pchg", tr.pchg)
	_accd("ren_world", tr.ren_world)
	_acc("tracked_total", float(tr.flags.size()))
	var kinds := {}
	for i in range(1, tr.res_kind.size()):
		kinds[tr.res_kind[i]] = int(kinds.get(tr.res_kind[i], 0)) + 1
	_accd("res_kinds", kinds)
	print("[S0]   资源表: %s · 程序贴图总像素 %d" % [str(kinds), tr.gen_px])
	_acc("gen_px", tr.gen_px)


func _report_total(label: String) -> void:
	var steps := float(_agg.get("steps", 0.0))
	var secs := steps / 60.0
	print("[S0] ════ 合计 %s: %d 步 = %.1f 游戏秒 ════" % [label, int(steps), secs])
	print("[S0] 节点层并发 峰值 %d / 平均 %.1f ; world 全量 峰值 %d / 平均 %.1f" % [int(_agg.get("peak", 0)),
		float(_agg.get("conc_sum", 0.0)) / maxf(1.0, float(_agg.get("conc_n", 0.0))), int(_agg.get("census_peak", 0)),
		float(_agg.get("census_sum", 0.0)) / maxf(1.0, float(_agg.get("census_n", 0.0)))])
	var cc: Dictionary = _agg.get("conc_cls", {})
	var tot := 0.0
	for k in cc:
		tot += float(cc[k])
	var parts: Array = []
	for k in _top(cc, 12):
		parts.append("%s %.1f%%" % [k, 100.0 * float(cc[k]) / maxf(1.0, tot)])
	print("[S0] 节点层并发按类占比(节点·采样): %s" % ", ".join(parts))
	var adds: Dictionary = _agg.get("adds", {})
	for k in _top(adds, 40):
		print("[S0]   新建 %s = %d" % [k, int(adds[k])])
	print("[S0] 事件: %s" % str(_agg.get("ev", {})))
	for nm in ["30Hz", "20Hz", "60Hz"]:
		if _agg.has("raw_" + nm):
			print("[S0] 编码 %s: 原始 %.0f B = %.2f KB/s · ZSTD 分块 %.0f B = %.2f KB/s(压缩比 %.1f×) · 整段 ZSTD %.0f B · 分类 %s" % [nm,
				float(_agg["raw_" + nm]), float(_agg["raw_" + nm]) / 1024.0 / secs, float(_agg["z_" + nm]), float(_agg["z_" + nm]) / 1024.0 / secs,
				float(_agg["raw_" + nm]) / maxf(1.0, float(_agg["z_" + nm])), float(_agg["zw_" + nm]), str(_agg["cat_" + nm])])
	print("[S0] 资源表(按种类): %s · 程序贴图总像素 %d" % [str(_agg.get("res_kinds", {})), int(_agg.get("gen_px", 0))])
	print("[S0] 造不出镜像 · 按标记(节点数): %s" % str(_agg.get("flag_nodes", {})))
	var fl: Dictionary = _agg.get("flags", {})
	for k in _top(fl, 80):
		print("[S0]   FLAG %s = %d" % [k, int(fl[k])])
	var dm: Dictionary = _agg.get("dyn_mesh", {})
	for k in _top(dm, 20):
		print("[S0]   程序网格逐步变化 %s = %d 次" % [k, int(dm[k])])
	var ex: Dictionary = _agg.get("ext_changes", {})
	print("[S0] 第三条钟改属性(条目 %d):" % ex.size())
	for k in _top(ex, 40):
		print("[S0]   EXT %s = %d" % [k, int(ex[k])])
	var er: Dictionary = _agg.get("ext_removed", {})
	print("[S0] 第三条钟删节点(条目 %d):" % er.size())
	for k in _top(er, 30):
		print("[S0]   EXTDEL %s = %d" % [k, int(er[k])])
	var ow: Dictionary = _agg.get("out_world", {})
	print("[S0] 第三条钟在 world 下生节点(条目 %d):" % ow.size())
	for k in _top(ow, 30):
		print("[S0]   EXTADD %s = %d" % [k, int(ow[k])])
	print("[S0] 渲染步在 world 下生节点: %s" % str(_agg.get("ren_world", {})))
	print("[S0] 编码器不认识类型的属性变化: %s" % str(_agg.get("unsup", {})))
	var pc: Dictionary = _agg.get("pchg", {})
	var pct := 0
	for k in pc:
		pct += int(pc[k])
	print("[S0] 真的变过的属性(30Hz·节点+资源·创建后): %d 种 / 共 %d 次" % [pc.size(), pct])
	for k in _top(pc, 60):
		print("[S0]   CHG %s = %d" % [k, int(pc[k])])
	var wlp := OS.get_environment("S0_WL_OUT")
	if wlp != "":
		var f := FileAccess.open(wlp, FileAccess.WRITE)
		f.store_string("
".join(PackedStringArray(pc.keys())))
		f.close()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	_audio = get_node_or_null("/root/Audio")
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)
	get_tree().node_added.connect(_on_added)
	var set_ := OS.get_environment("S0_SET")
	var mode := OS.get_environment("S0_MODE")
	var reps: int = int(OS.get_environment("S0_REPS")) if OS.get_environment("S0_REPS") != "" else 2
	if set_ == "find":
		await _find()
	elif mode == "perf":
		await _perf(set_, reps)
	else:
		if set_ == "det":
			var dn: int = int(OS.get_environment("S0_DETN")) if OS.get_environment("S0_DETN") != "" else 999
			for sc in SC.all().slice(0, dn):
				var r: Dictionary = await _run_det(sc as Dictionary, "rec", true)
				_report_one(str(sc["tag"]), r)
			_report_total("det_scenarios 全部 %d 个场景" % SC.all().size())
		else:
			var only := OS.get_environment("S0_ONLY")
			var i := 0
			for j in _ref_jobs():
				if only != "" and str(i) != only:
					i += 1
					continue
				i += 1
				var job := _job(j[1], j[2], int(j[3]))
				var r: Dictionary = await _run_ref(job, "rec", true)
				print("[S0] 裁判局 %s 种子 %d: ok=%s 开打 %d 次 胜方 %s %s" % [str(j[0]), int(j[3]), str(r["ok"]), int(r["fights"]), str(r["winner"]), str(r["err"])])
				_report_one(str(j[0]), r)
			_report_total("裁判局")
	print("[S0] DONE")
	get_tree().quit(0)


## 给 ref 挑「打满三路」的组合(RefereeRunner 原样跑, 不录流)。
func _find() -> void:
	var pool := _pool_snaps()
	print("[S0] 池子快照数 %d" % pool.size())
	var seeds := [2000023, 3000026, 4000029, 5000032]
	for pair in [[0, 1], [0, 2], [1, 2], [2, 3], [3, 4], [0, 5]]:
		if pool.size() <= int(pair[1]):
			break
		for sd in seeds:
			var job := _job((pool[int(pair[0])] as Dictionary).duplicate(true), (pool[int(pair[1])] as Dictionary).duplicate(true), int(sd))
			var res: Dictionary = await RefereeRunner.run(self, job)
			print("[S0] FIND pair=%s seed=%d ok=%s fights=%d steps=%d winner=%s err=%s" % [str(pair), int(sd), str(res.get("ok")), int(res.get("fights", 0)), int(res.get("steps", 0)), str(res.get("winner")), str(res.get("error", ""))])
			if int(res.get("fights", 0)) >= 3:
				print("[S0] FOUND pair=%s seed=%d" % [str(pair), int(sd)])
				return


## 录流开销: 三种配置轮流跑, 每种取最快一遍。比的是同一进程里的步/秒(参照 = 「ref」现状)。
func _perf(set_: String, reps: int) -> void:
	var cfgs: Array = Array(OS.get_environment("S0_CFGS").split(",")) if OS.get_environment("S0_CFGS") != "" else ["ref", "align", "rec"]
	var best := {}
	var fps := {}
	for rep in range(reps):
		for cfg in cfgs:
			var steps := 0
			var us := 0
			var fpl: Array = []
			if set_ == "det":
				for sc in SC.all():
					var r: Dictionary = await _run_det(sc as Dictionary, cfg, false)
					steps += int(r["steps"])
					us += int(r["us"])
					fpl.append(str(r["fp"]))
			else:
				var only := OS.get_environment("S0_ONLY")
				var i := 0
				for j in _ref_jobs():
					if only != "" and str(i) != only:
						i += 1
						continue
					i += 1
					var r: Dictionary = await _run_ref(_job(j[1], j[2], int(j[3])), cfg, false)
					steps += int(r["steps"])
					us += int(r["us"])
					fpl.append(str(r["fp"]) + "/" + str(r["fights"]))
			print("[S0] PERF rep %d %s: %d 步 %.2f 秒 = %.0f 步/秒 · 指纹 %s" % [rep, cfg, steps, us / 1.0e6, steps / (us / 1.0e6), str(fpl)])
			if not best.has(cfg) or us < int(best[cfg][1]):
				best[cfg] = [steps, us]
			var key := "|".join(fpl)
			fps[cfg] = key
	var base := float(best[cfgs[0]][0]) / (float(best[cfgs[0]][1]) / 1.0e6)
	for cfg in cfgs:
		var sps := float(best[cfg][0]) / (float(best[cfg][1]) / 1.0e6)
		print("[S0] PERF 最快一遍 %s: %.0f 步/秒 = 现状的 %.2f 倍 = 实时(60 步/秒)的 %.1f 倍" % [cfg, sps, sps / base, sps / 60.0])
	var same := true
	for cfg in cfgs:
		same = same and fps[cfg] == fps[cfgs[0]]
		print("[S0] PERF 指纹 %s = %s" % [cfg, str(fps[cfg]).left(120)])
	print("[S0] PERF 各配置终局指纹一致: %s" % str(same))
