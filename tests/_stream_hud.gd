extends RefCounted
## 逐帧直播 · HUD 快照(下划线开头: 不是门禁; 被 verify_stream_hud_parity / _shot_stream_hud preload)。
## 「本机跑」与「播放」两边用同一个函数拍, 只是「单位 idx → 单位字典」的来源不同。
##
## 快照形状:
##   texts:  {"锚|文本": 个数}  —— `_ui_layer` 下所有**在树上可见**的 Label / RichTextLabel / Button 文本
##           (锚 = 最近一个不是自动名(@…)的祖先名: Frame_basic / TeamPanel_left / LanePlate …)。
##           飘字(UI_TRANSIENT_GROUP 及其子孙)不算: 那是 verify_stream_parity 的飘字段管的。
##   texs:   {"锚|贴图键": 个数} —— 同一范围里可见的 TextureRect 贴图(头像 / 装备格图标 / 顶栏头像 / 路点 …)
##   units:  idx → [头顶血条 hp%, 盾, 龟能条宽, 血条可见]
##   frames: side → [[框名, 血条比例, 变暗?, [装备格图标], {装备 id: 充能条宽}], …](头像框栏, 按列里的顺序)
##   disc:   [有没有, 可见, 图标路径, 冷却比例, 层数](法术圆盘)
##   pk:     [左目标, 右目标, 左蛋, 右蛋, 左围栏, 右围栏](顶部 PK 条的采样值)
##   names:  [顶栏左名, 右名] —— 单独拿出来: 服务器本机跑时那里写的是**服务器自己的账号名**(没意义), 播放端按入口给的名字(见门禁)
##   plate:  [路名计时牌文本, 本战场已打秒数, 破蛋剩余秒数] —— 单独比: 秒数恰好压在整秒边界上的那一步允许差一秒(见 diff)

const DIG := 1000.0
const CHG_TOL := 0.03


static func _tex_key(t) -> String:
	if t == null or not is_instance_valid(t):
		return ""
	if t is AtlasTexture and (t as AtlasTexture).atlas != null:
		return "atlas:" + _tex_key((t as AtlasTexture).atlas) + str((t as AtlasTexture).region)
	var p := str((t as Resource).resource_path)
	if p != "" and p.find("::") < 0:
		return p
	return "<gen:%s>" % (t as Object).get_class()


static func _anchor(n: Node, top: Node) -> String:
	var p := n.get_parent()
	while p != null and p != top:
		var nm := str(p.name)
		if not nm.begins_with("@"):
			return nm
		p = p.get_parent()
	return "UI"


static func _r(v: float) -> float:
	return roundf(v * DIG) / DIG


static func snap(b, units_by_idx: Dictionary, skip: Array = []) -> Dictionary:
	var out := {"texts": {}, "texs": {}, "units": {}, "frames": {}, "disc": [], "pk": [], "names": [], "plate": []}
	var ui: Node = b._ui_layer
	if ui == null:
		return out
	var tr_set := {}
	for n in b.get_tree().get_nodes_in_group(BattleHud.UI_TRANSIENT_GROUP):
		tr_set[(n as Object).get_instance_id()] = true
	var skip_set := {}
	for n in skip:
		if n != null and is_instance_valid(n):
			skip_set[(n as Object).get_instance_id()] = true
	## 正在淡出的幕布(已摘掉引用、等 0.22 秒真实时间的 tween 释放): 淡出走 SceneTree tween(真实时间, 不跟步号), 两边按步号比不了 ⇒ 不算
	if b._dl_sys != null and b._dl_sys.present_fading != null and is_instance_valid(b._dl_sys.present_fading):
		skip_set[(b._dl_sys.present_fading as Object).get_instance_id()] = true
	var tb = b._hud._topbar if b._hud != null else null
	if tb != null:
		for nl in [tb.name_l, tb.name_r]:
			if nl != null and is_instance_valid(nl):
				skip_set[(nl as Object).get_instance_id()] = true
				out["names"].append((nl as Label).text if (nl as Label).visible else "")
	if b._dl_hud != null and is_instance_valid(b._dl_hud):
		skip_set[(b._dl_hud as Object).get_instance_id()] = true
		var pv: bool = (b._dl_hud as Label).is_visible_in_tree()
		out["plate"] = [(b._dl_hud as Label).text if pv else "", float(b._t) - float(b._sd_t0), float(b._dl_window_until) - float(b._t)]
	## 头顶血条(bar_root)按单位单独比 ⇒ 普查里跳过它们(否则文本 / 贴图混在 UI 根下, 顺序无关但数量多)
	for idx in units_by_idx:
		var u: Dictionary = units_by_idx[idx]
		var root = u.get("bar_root")
		if root != null and is_instance_valid(root):
			skip_set[(root as Object).get_instance_id()] = true
	var stack: Array = [ui]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c.is_queued_for_deletion():
				continue
			var iid: int = c.get_instance_id()
			if tr_set.has(iid) or skip_set.has(iid):
				continue
			if c is CanvasItem and not (c as CanvasItem).visible:
				continue
			## 已被换下、正在淡出的旧幕布(SceneTree tween 走真实时间, 不跟步号; 两边按步号比不了)
			if n == ui and c != b._dl_present_root and c.find_child("PresentPanel", true, false) != null:
				continue
			stack.append(c)
			var txt := ""
			if c is Label:
				txt = (c as Label).text
			elif c is RichTextLabel:
				txt = (c as RichTextLabel).text
			elif c is Button:
				txt = (c as Button).text
			if txt.strip_edges() != "":
				var k := "%s|%s" % [_anchor(c, ui), txt]
				out["texts"][k] = int(out["texts"].get(k, 0)) + 1
			if c is TextureRect and (c as TextureRect).texture != null:
				var k2 := "%s|%s" % [_anchor(c, ui), _tex_key((c as TextureRect).texture)]
				out["texs"][k2] = int(out["texs"].get(k2, 0)) + 1
	## 头顶血条
	for idx in units_by_idx:
		var u: Dictionary = units_by_idx[idx]
		var hb = u.get("hp_bar")
		var root = u.get("bar_root")
		if hb == null or not is_instance_valid(hb):
			continue
		var en = u.get("en_fill")
		var enw := -1.0
		if en != null and is_instance_valid(en) and (en as CanvasItem).visible:
			enw = _r((en as Control).size.x)
		var vis: bool = root != null and is_instance_valid(root) and (root as CanvasItem).visible
		out["units"][int(idx)] = [_r(float(hb._hp) / maxf(1.0, float(hb._max_hp))), _r(float(hb._shield)), enw, vis]
	## 头像框栏
	for side in ["left", "right"]:
		var col = b._team_panel_left if side == "left" else b._team_panel_right
		var rows: Array = []
		if col != null and is_instance_valid(col) and not (col as Node).is_queued_for_deletion():
			for fr in (col as Node).get_children():
				if not str(fr.name).begins_with("Frame_"):
					continue
				var fill := -1.0
				var icons: Array = []
				var chg := {}
				for u in units_by_idx.values():
					if is_same(u.get("panel_frame"), fr):
						var f = u.get("panel_hp_fill")
						if f != null and is_instance_valid(f):
							var slot = (f as Node).get_parent()
							var sw: float = (slot as Control).size.x if slot is Control and (slot as Control).size.x > 1.0 else float(b._PANEL_HP_W)
							fill = _r((f as Control).size.x / sw)
						var row = u.get("panel_eq_row")
						if row != null and is_instance_valid(row):
							var st2: Array = [row]
							while not st2.is_empty():
								var q: Node = st2.pop_back()
								for cc in q.get_children():
									st2.append(cc)
									if cc is TextureRect:
										icons.append(_tex_key((cc as TextureRect).texture))
						for cb in u.get("panel_charge_bars", []):
							var cf = (cb as Dictionary).get("fill")
							if cf != null and is_instance_valid(cf):
								chg[str(cb["iid"])] = (cf as Control).size.x
						break
				icons.sort()
				rows.append([str(fr.name), fill, (fr as Control).modulate.r < 0.9, icons, chg])
		out["frames"][side] = rows
	## 法术圆盘
	var d = b._spell_disc
	if d != null and is_instance_valid(d) and not (d as Node).is_queued_for_deletion():
		out["disc"] = [true, (d as CanvasItem).visible, _tex_key(d._icon), _r(float(d._cd_frac)), int(d._stacks)]
	else:
		out["disc"] = [false]
	var h = b._hud
	if h != null:
		out["pk"] = [_r(float(h._pk_target_l)), _r(float(h._pk_target_r)), _r(float(h._pk_egg_tl)), _r(float(h._pk_egg_tr)),
			bool(h._pk_fenced.get("left", false)), bool(h._pk_fenced.get("right", false))]
	## 路点(各路胜负 = 比分): 核心颜色
	if tb != null:
		for dc in tb.dot_cores:
			if dc != null and is_instance_valid(dc):
				out["pk"].append((dc as CanvasItem).modulate.to_html())
	return out


## 两张快照逐项比; 返回 {n: 比过的元素数, bad: [差异描述]}。
## `fresh_panels`: 播放端这一步刚重建了头像框栏 —— 新框还没排版(槽宽 0), 这一帧的血条按兜底宽 80 算、下一帧才按真宽 90 算
##   (本机每一局建栏那一帧也是这样; 只是本机建栏与采样之间隔了一帧)。这一步只不比头像框血条比例, 其余照比。
static func diff(a: Dictionary, b: Dictionary, tag: String, fresh_panels: bool = false) -> Dictionary:
	var n := 0
	var bad: Array = []
	for key in ["texts", "texs"]:
		var x: Dictionary = a[key]
		var y: Dictionary = b[key]
		for k in x:
			n += 1
			if int(x[k]) != int(y.get(k, 0)):
				bad.append("%s %s「%s」本机 %d / 播放 %d" % [tag, key, k, int(x[k]), int(y.get(k, 0))])
		for k in y:
			if not x.has(k):
				bad.append("%s %s「%s」本机 0 / 播放 %d" % [tag, key, k, int(y[k])])
	var ua: Dictionary = a["units"]
	var ub: Dictionary = b["units"]
	for idx in ua:
		n += 1
		if not ub.has(idx) or str(ua[idx]) != str(ub[idx]):
			bad.append("%s 头顶血条 单位%d 本机 %s / 播放 %s" % [tag, int(idx), str(ua[idx]), str(ub.get(idx, "-"))])
	for idx in ub:
		if not ua.has(idx):
			bad.append("%s 头顶血条 单位%d 本机没有 / 播放 %s" % [tag, int(idx), str(ub[idx])])
	for side in ["left", "right"]:
		var fa: Array = a["frames"].get(side, [])
		var fb: Array = b["frames"].get(side, [])
		n += fa.size()
		var same := fa.size() == fb.size()
		for i in range(fa.size()):
			if not same:
				break
			var ra: Array = (fa[i] as Array).slice(0, 4)
			var rb: Array = (fb[i] as Array).slice(0, 4)
			if fresh_panels:
				ra[1] = 0
				rb[1] = 0
			if str(ra) != str(rb):
				same = false
				break
			## 充能条: 流里按 1/1024 量化 ⇒ 44 像素宽的条差 ≤ 0.022 像素(看不出); 判 ≤ CHG_TOL
			var ca: Dictionary = fa[i][4]
			var cb2: Dictionary = fb[i][4]
			if ca.size() != cb2.size():
				same = false
				break
			for k in ca:
				n += 1
				if not cb2.has(k) or absf(float(ca[k]) - float(cb2[k])) > CHG_TOL:
					same = false
		if not same:
			bad.append("%s 头像框栏 %s 本机 %s / 播放 %s" % [tag, side, str(fa), str(fb)])
	n += 1
	if str(a["disc"]) != str(b["disc"]):
		bad.append("%s 法术圆盘 本机 %s / 播放 %s" % [tag, str(a["disc"]), str(b["disc"])])
	n += 1
	if str(a["pk"]) != str(b["pk"]):
		bad.append("%s PK 条 本机 %s / 播放 %s" % [tag, str(a["pk"]), str(b["pk"])])
	## 路名计时牌: 文本相同; 不同时只放过「本机的秒数恰好压在整秒边界上」那一步
	##   (本机 `_t` 是 double 累加、恰好 x.000000 时 ceil / floor 落哪边看浮点末位; 流里 `t` 是 float32 ⇒ 那一步可能早 / 晚一步翻秒)
	var boundary := 0
	var pa: Array = a["plate"]
	var pb: Array = b["plate"]
	if not pa.is_empty():
		n += 1
		if pb.is_empty() or str(pa[0]) != str(pb[0]):
			if not pb.is_empty() and _on_second_edge(pa) and _same_head(str(pa[0]), str(pb[0])):
				boundary += 1
			else:
				bad.append("%s 路名计时牌 本机 %s / 播放 %s" % [tag, str(pa), str(pb)])
	return {"n": n, "bad": bad, "boundary": boundary}


static func _on_second_edge(pa: Array) -> bool:
	for i in [1, 2]:
		var v: float = float(pa[i])
		if absf(v - roundf(v)) < 1.0e-3:
			return true
	return false


## 「破蛋 0:10」与「破蛋 0:11」: 去掉数字后相同, 且秒数只差 1
static func _same_head(x: String, y: String) -> bool:
	var re := RegEx.new()
	re.compile("([0-9]+):([0-9]+)")
	var mx := re.search(x)
	var my := re.search(y)
	if mx == null or my == null:
		return false
	if re.sub(x, "#") != re.sub(y, "#"):
		return false
	var sx := int(mx.get_string(1)) * 60 + int(mx.get_string(2))
	var sy := int(my.get_string(1)) * 60 + int(my.get_string(2))
	return absi(sx - sy) == 1


## 这张快照里各类元素各有几个(分母)
static func count(a: Dictionary) -> Dictionary:
	var fr := 0
	var icons := 0
	var chg := 0
	for side in a["frames"]:
		for r in (a["frames"][side] as Array):
			fr += 1
			icons += (r[3] as Array).size()
			chg += (r[4] as Dictionary).size()
	var tx := 0
	for k in a["texts"]:
		tx += int(a["texts"][k])
	return {"texts": tx, "texs": (a["texs"] as Dictionary).size(), "units": (a["units"] as Dictionary).size(),
		"frames": fr, "icons": icons, "charge": chg, "disc": 1 if bool(a["disc"][0]) else 0}
