class_name TrainerChainVfx
extends RefCounted
## 训龟大师钩锁的锁链 —— 新画法(用户 2026-11-20「锁链特效主要现在这个锁链完全不行，你需要新设计一种方法」)。
##
## ★旧画法为什么不行(`trainer_system._hook_chain` → `battle._beam_vfx`): 每个 sim 步在地上**平铺**一条拉长的铁链贴图
##   (线性过滤、每条活 0.13 秒淡出)⇒ 几条叠着闪、贴图被拉糊、从 40° 镜头看就是两条深色虚线横穿场地; 没有甩出去的过程, 也没有拽的手感。
## ★新画法(参考锤石 Q / 诺提勒斯 Q 逐帧: docs/studies/20261120d-训龟大师锁链参考-锤石诺提勒斯逐帧.md):
##   一根锁链 = **一张常驻的四边形**(长边顺着链子、正面朝镜头), 每个 sim 步改位置和着色器参数(`trainer_chain.gdshader`):
##     飞行 = 拖影带(靠钩头粗浓、靠手淡) + 若隐若现的链节;
##     钩中 = 同一步收成细直的链子(链节从目标那头平铺, 拽短了也不滑) + 一道亮光从目标跑回大师;
##     每拽一下再跑一道亮光; 拽完 / 空放 ⇒ 0.18 秒收回到手里再删。
## ★全在 sim 步里建 / 改 / 删(同钩头节点) ⇒ 直播录流照样镜像(节点变换 + ShaderMaterial 参数都在跟踪表里), 时停也跟着停。
## ★单位字典不当键(CLAUDE.md §4.2): 每根链记着「它挂在哪个飞行记录 / 哪个被钩单位上」, 找的时候用 is_same。

const SHADER := preload("res://assets/shaders/trainer_chain.gdshader")
const LINK_TEX := "res://assets/sprites/vfx/trainer-chain-link.png"
const TEXEL_M := 0.05               # 链节贴图一格 = 5 厘米 ⇒ 链子 9 格高 ≈ 0.45 米(第一版 3.5 厘米实录只有三四个像素粗, 远看是一条虚线)
const HAND_H := 1.35                # 大师手的高度
const HEAD_H := 1.0                 # 钩头飞行高度(同 trainer_system._hook_head_node)
const BODY_H := 0.7                 # 钩住目标时挂在身上的高度
const RIBBON_W := 0.8               # 飞行拖影带最宽处(米)
const GLINT_T := 0.25               # 一道亮光跑完一根链子的时间(秒)
const RETRACT_T := 0.18             # 收回到手里的时间(秒)

var battle = null
var _chains: Array = []             # {ref, node, mat, a, b, mode, touched, glint, retract, tug}
var _link_tex: Texture2D = null


func _init(b) -> void:
	battle = b


func _find(ref) -> Dictionary:
	for c in _chains:
		if is_same(c["ref"], ref):
			return c
	return {}


## 每个 sim 步开头: 先把所有链标成「这一步还没人画」。
func begin_step() -> void:
	for c in _chains:
		c["touched"] = false


## 飞行中: 大师手 → 钩头。ref = 飞行记录(trainer_system._flights 的那一条)。
func fly(ref, from2d: Vector2, head2d: Vector2) -> void:
	var c: Dictionary = _find(ref)
	if c.is_empty():
		c = _new_chain(ref)
		if c.is_empty():
			return
	c["mode"] = "fly"
	c["touched"] = true
	c["a"] = battle._world_pos(from2d, HAND_H)
	c["b"] = battle._world_pos(head2d, HEAD_H)
	_place(c)


## 钩中: 这根链从「挂在飞行记录上」改成「挂在被钩的单位上」, 同一步收成直链 + 跑一道亮光。
func latch(ref, target: Dictionary) -> void:
	var c: Dictionary = _find(ref)
	if c.is_empty():
		return
	c["ref"] = target
	c["mode"] = "hold"
	c["touched"] = true
	c["glint"] = 0.0
	c["b"] = battle._world_pos(target["pos"], BODY_H)
	_place(c)


## 拽的期间: 大师 ↔ 被钩目标。in_tug = 此刻正处在「拽的那一下」里(上升沿跑一道亮光)。
func hold(target: Dictionary, from2d: Vector2, in_tug: bool) -> void:
	var c: Dictionary = _find(target)
	if c.is_empty():
		return
	c["touched"] = true
	## 拽的上升沿跑一道亮光; ★正在跑的那道不打断 —— 钩中后 0.1 秒就是第一下拽, 打断会让亮光刚起跑就跳回目标那头(门禁 ③ 抓到的顿一下)
	if in_tug and not bool(c.get("tug", false)) and float(c.get("glint", -1.0)) < 0.0:
		c["glint"] = 0.0
	c["tug"] = in_tug
	c["a"] = battle._world_pos(from2d, HAND_H)
	c["b"] = battle._world_pos(target["pos"], BODY_H)
	_place(c)


## 每个 sim 步末尾: 这一步没人画的链 ⇒ 开始收回; 推亮光 / 收回; 收完的删掉。
func end_step(dt: float) -> void:
	var keep: Array = []
	for c in _chains:
		var nd = c["node"]
		if not is_instance_valid(nd):
			continue
		if not bool(c["touched"]) and c["mode"] != "retract":
			c["mode"] = "retract"
			c["retract"] = 0.0
		if c["mode"] == "retract":
			c["retract"] = float(c["retract"]) + dt
			if float(c["retract"]) >= RETRACT_T:
				(nd as Node).queue_free()
				continue
		if float(c.get("glint", -1.0)) >= 0.0:
			c["glint"] = float(c["glint"]) + dt
			if float(c["glint"]) > GLINT_T:
				c["glint"] = -1.0
		_place(c)
		keep.append(c)
	_chains = keep


## 换路清场: 在途 / 挂着的链连节点一起删。
func clear() -> void:
	for c in _chains:
		if is_instance_valid(c["node"]):
			(c["node"] as Node).queue_free()
	_chains = []


func _new_chain(ref) -> Dictionary:
	if battle._world == null:
		return {}
	if _link_tex == null:
		if not ResourceLoader.exists(LINK_TEX):
			push_warning("[钩锁] 链节素材缺失: %s" % LINK_TEX)
			return {}
		_link_tex = load(LINK_TEX)
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mi.mesh = qm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("link_tex", _link_tex)
	m.set_shader_parameter("link_px", Vector2(_link_tex.get_width(), _link_tex.get_height()))
	m.set_shader_parameter("link_m", float(_link_tex.get_width()) * TEXEL_M)
	mi.material_override = m
	battle._world.add_child(mi)
	var c := {"ref": ref, "node": mi, "mat": m, "a": Vector3.ZERO, "b": Vector3.ZERO, "mode": "fly", "touched": true, "glint": -1.0, "retract": 0.0, "tug": false}
	_chains.append(c)
	return c


## 摆四边形 + 喂参数。长边 = 手 → 钩头 / 目标; 宽边 = 同时垂直于链子和视线(正面朝镜头), 并且朝屏幕上方。
func _place(c: Dictionary) -> void:
	var mi: MeshInstance3D = c["node"]
	var m: ShaderMaterial = c["mat"]
	var a: Vector3 = c["a"]
	var b: Vector3 = c["b"]
	if c["mode"] == "retract":
		b = a + (b - a) * maxf(0.0, 1.0 - float(c["retract"]) / RETRACT_T)
	var seg: Vector3 = b - a
	var L: float = seg.length()
	if L < 0.02:
		mi.visible = false
		return
	mi.visible = true
	var dir: Vector3 = seg / L
	var side: Vector3 = dir.cross(BattleCam.FORWARD).normalized()
	var cam_up := Vector3(0.0, BattleCam.COS_P, -BattleCam.SIN_P)
	if side.dot(cam_up) < 0.0:
		side = -side
	var chain_h: float = float(_link_tex.get_height()) * TEXEL_M
	var flying: bool = c["mode"] == "fly"
	var w: float = RIBBON_W if flying else chain_h
	var n: Vector3 = dir.cross(side).normalized()
	mi.global_transform = Transform3D(Basis(dir * L, side * w, n), a + seg * 0.5)
	m.set_shader_parameter("len_m", L)
	m.set_shader_parameter("ribbon", 1.0 if flying else 0.0)
	m.set_shader_parameter("chain_frac", chain_h / w)
	var g: float = float(c.get("glint", -1.0))
	m.set_shader_parameter("glint", (1.0 - g / GLINT_T) if g >= 0.0 else -1.0)   # 从目标那头(1)跑回大师(0)
