extends Node
## verify_theme_decor_census.gd — 四版主题的装饰普查: ① 不建默认画面的珊瑚/海草 ② 物件与接地影 1:1
##
## ══════════════════════════════════════════════════════════════════════
##  由来(2026-10-04 欠账盘点)
## ══════════════════════════════════════════════════════════════════════
## ① 方案书 `docs/plans/20261003-岛与海作为边界.md` C1「全场零珊瑚/海草」——用户 2026-10-02 原话
##    「**这些珊瑚海草不适合**你听明白了吗」。产品侧早就靠 `no_base_midground` 把 base 的珊瑚/海草
##    一处处关掉了(`battle_world_builder.gd` 至少五处 `if no_base_midground`), 但**没有一条判据**
##    数过"主题里到底还剩几株" —— 只要哪条建场路径(调试场 / 真对局 `_build_map_props`)漏判一次,
##    珊瑚就回来了, 门禁全绿(D2 水面光柱就是这样在真对局那条路上漏了 4 道)。
## ② 四版主题都配了 `prop_shadow`(物件接地影, 参考「每件物件脚下都有一块深色影, 没有就像贴上去的」),
##    `verify_arena_themes` 只验**键在不在**, 没有任何断言数过**影子真的建了几块、跟物件对不对得上**。
##    建影的有五处(布局物件 / 场内草丛 / 场内骨堆 / 中景灌木 / 主题障碍), 漏掉任何一处都只是"那几件
##    像贴上去的", 截图里很难一眼看出来。
##
## ★命名: 方案书 C1 的锚点写的是 `gate:verify_island_decor`, 但同一个锚点还挂着 C2(障碍不再是礁石)、
##   C3(成组度往参考靠)、「C 刀反向验证」——它们**没做**。审计器的判法是「文件存在 ⇒ 做完」,
##   建了那个名字 = 把没做的三条一起判成做完(方案书自己在 §4.2 末尾写过这个坑)。⇒ 本文件另起名。
## ⚠ 本条**只量「默认画面那套」珊瑚/海草**(用户 2026-10-02 指的那批)。主题**自己新画的**珊瑚/海草
##   仍在场(深礁 `reef2_kelp_*` 场内海草丛、`reef3_coral_a` 珊瑚塔、紫墟 `shoal3_coral_altar`)——
##   那是 2026-10-04 照 Anchordeep 参考有意加的。C1 原文是「**全场**零珊瑚/海草」, 两者对不上,
##   所以 C1 **不因本条判成做完**, 锚点不动, 留给用户拍板(原文要不要收窄成"默认画面那套")。
##
## ★判据量产品真的建出来的节点(调试场建场 + 再跑一遍真对局用的 `_build_map_props`, 同 verify_arena_layers_drawn)。
## ★"珊瑚/海草"按**贴图文件名**认(coral / kelp / seagrass / anem), 只认默认画面的素材(不在 map/themes/ 下的);
##   base 那一遍必须数得出 > 0 株, 否则"主题 0 株"是空检查。
## ★"影子"按**形状**认, 不按节点名(同名兄弟会被引擎改成 @Name@N): PlaneMesh + 径向渐变贴图 = `_contact_shadow` 的产物。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const CORAL_RX := "coral|kelp|seagrass|anem"
## 建接地影的四类容器(`_build_layout_props` / `_build_field_tufts` ×2 / `_build_theme_midground`)
## ⚠ 2026-10-04 实测: 四版都开了 `use_layout` ⇒ `FieldTufts`/`FieldPiles` 两个容器**根本不建**
##   (反向验证时把草丛的影删掉, 本条不红 —— 查下去是那段对四版是死路径)。留在清单里是为了
##   哪版关掉 use_layout 时自动纳入; 现在真正被量的是 布局物件 / 中景灌木 / 主题障碍 三类。
const SHADOW_HOSTS := ["LayoutProps", "FieldTufts", "FieldPiles", "ThemeMid"]

var _fail := 0
var _n := 0
var _rx := RegEx.new()


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 主题装饰普查(珊瑚海草 0 株 · 物件/接地影 1:1) ===")
	_rx.compile(CORAL_RX)
	var keep: String = AT.active
	RB.DEBUG_EDIT = true

	## ── base: 证明两把尺子都找得到东西 ──
	AT.active = AT.V0_BASE
	var sb = await _build()
	var bc: Array = _corals(sb)
	_ok("[base] ★分母: 默认画面数得出珊瑚/海草(%d 株) —— 数不出来, 下面「主题 0 株」就是空检查" % bc.size(),
		bc.size() >= 5, str(_hist(bc)))
	var bsh: int = _all_shadows(sb._world).size()
	_ok("[base] ★分母: base 没配 prop_shadow ⇒ 一块接地影都没有(%d 块)" % bsh,
		not AT.cfg_of(AT.V0_BASE).has("prop_shadow") and bsh == 0, "%d 块" % bsh)
	sb.queue_free()
	await get_tree().process_frame

	_ok("★分母: 主题表里四版都在 DRAWN(普查覆盖全部四版)", AT.ALL.size() == 4 and AT.DRAWN.size() == 4,
		"ALL %s / DRAWN %s" % [str(AT.ALL), str(AT.DRAWN)])
	for th in AT.ALL:
		AT.active = str(th)
		var s = await _build()
		var cs: Array = _corals(s)
		_ok("[%s] ★★C1 全场零珊瑚/海草(默认画面那套素材 0 株)" % th, cs.is_empty(), str(_hist(cs)))

		var ps: float = float(AT.cfg_of(str(th)).get("prop_shadow", 0.0))
		_ok("[%s] ★分母: 配了 prop_shadow(%.2f > 0)" % [th, ps], ps > 0.0)
		var props_n := 0
		var shad_n := 0
		var bad: Array = []
		for host in SHADOW_HOSTS:
			for box in _all_named(s._world, str(host)):
				var np: int = 0
				var nsh: int = 0
				for ch in (box as Node).get_children():
					if (ch as Node).is_queued_for_deletion():
						continue
					if ch is Sprite3D:
						np += 1
					elif _is_shadow(ch):
						nsh += 1
				props_n += np
				shad_n += nsh
				if np != nsh:
					bad.append("%s 物件 %d / 影 %d" % [str((box as Node).name), np, nsh])
		## 主题障碍: 每个 holder 一件精灵 + 一块影
		var obs: Array = _with_meta(s._world, "vis_w")
		for sp in obs:
			var holder: Node = (sp as Node).get_parent()
			var nsh2 := 0
			for ch in holder.get_children():
				if _is_shadow(ch):
					nsh2 += 1
			props_n += 1
			shad_n += nsh2
			if nsh2 != 1:
				bad.append("障碍 %s 影 %d 块" % [(sp as Sprite3D).texture.resource_path.get_file(), nsh2])
		_ok("[%s] ★分母: 建影的物件一共 %d 件(布局/中景/障碍; 障碍 %d 件)" % [th, props_n, obs.size()],
			props_n >= 20 and obs.size() > 0, "%d 件" % props_n)
		_ok("[%s] ★★物件与接地影 1:1(物件 %d / 影 %d)" % [th, props_n, shad_n],
			bad.is_empty() and props_n == shad_n, str(bad))
		s.queue_free()
		await get_tree().process_frame
	AT.active = keep
	_ok("★分母: 测试结束把主题切回原样(不留污染)", AT.active == keep, AT.active)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 主题装饰普查" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 调试场建场 + 再跑一遍真对局那条 `_build_map_props`(两条路径都要量, 见 verify_arena_layers_drawn 头注)。
func _build():
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._world_builder._build_map_props()
	await get_tree().process_frame
	return s


## 默认画面的珊瑚/海草: 贴图文件名命中 CORAL_RX、且不在 map/themes/ 下。世界 + 相机(前景带挂在相机上)都扫。
func _corals(s) -> Array:
	var out: Array = []
	for root in [s._world, s._cam]:
		for nd in _all_nodes(root):
			if (nd as Node).is_queued_for_deletion():
				continue
			var tex: Texture2D = _tex_of(nd)
			if tex == null:
				continue
			var p: String = tex.resource_path
			if p == "" or "/themes/" in p:
				continue
			if _rx.search(p.get_file().to_lower()) != null:
				out.append(p.get_file())
	return out


func _tex_of(nd) -> Texture2D:
	if nd is Sprite3D:
		return (nd as Sprite3D).texture
	if nd is GeometryInstance3D:
		var m = (nd as GeometryInstance3D).material_override
		if m is StandardMaterial3D:
			return (m as StandardMaterial3D).albedo_texture
		if m is ShaderMaterial:
			var t = (m as ShaderMaterial).get_shader_parameter("tex")
			if t is Texture2D:
				return t
	return null


func _is_shadow(nd) -> bool:
	if not (nd is MeshInstance3D):
		return false
	var mi: MeshInstance3D = nd
	var m = mi.material_override
	return mi.mesh is PlaneMesh and m is StandardMaterial3D \
		and (m as StandardMaterial3D).albedo_texture is GradientTexture2D


func _all_shadows(root: Node) -> Array:
	return _all_nodes(root).filter(func(x): return _is_shadow(x))


func _hist(a: Array) -> Dictionary:
	var h := {}
	for x in a:
		h[str(x)] = int(h.get(str(x), 0)) + 1
	return h


func _all_nodes(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		out.append(c)
		out.append_array(_all_nodes(c))
	return out


func _all_named(root: Node, prefix: String) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if prefix in str(c.name):   # ★同名兄弟会被引擎改成 @Name@N, 用「包含」不用「开头」
			out.append(c)
		out.append_array(_all_named(c, prefix))
	return out


func _with_meta(root: Node, key: String) -> Array:
	return _all_nodes(root).filter(func(x): return (x as Node).has_meta(key) and not (x as Node).is_queued_for_deletion())
