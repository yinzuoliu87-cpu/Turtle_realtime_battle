class_name RosterSlots
extends RefCounted
## 选龟页·3 个统领位(建 / 刷 / 拖放·_mark_label 和 _sync_special_slots 跨区共享留主场景)
## ★2026-10-30 选龟页重做(用户「你这还是一股浏览器的感觉啊」): 三格 = 背包同款大卡(UnitCardArt) ——
##   全身立绘 + 稀有度色名字横幅 + 下沿木托(被动 + 选中的技能两枚图标); 空位 = 背包占位统领同一个样子(「?」+「统领N」)。
##   原来先铺一块金边木托盘盖住背景烤死的 6 格 + 前/后排横幅, 再画 3 张橙边卡; 背景改成干净桌面后托盘不要了。

var host

func _init(b) -> void:
	host = b

const BANNER_EMPTY_COL := Color("#6c7a8c")    # 空位横幅(= 背包占位统领)
const BANNER_ACTIVE_COL := Color("#c8a46a")   # 待填(点了空位, 下一只点的龟进这里)


func _build_slots() -> void:
	host._slot_nodes = []
	for i in range(3):
		var panel = PanelContainer.new()
		panel.name = "LeaderSlot%d" % i
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		host.root.add_child(panel)
		host._place(panel, "slot%d" % i)
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		# 整槽点击 → tap-swap
		## ★松手且没怎么动才算点一下(2026-10-29 用户「拖不起来」): 原来【按下】就算, 而这个槽同时是拖动源 ——
		##   拖一次后选中还挂着, 再按住同一格拖 = 「二次点同格 = 移除」, 龟在按下那一刻就被拿出阵容, 拖不起来;
		##   选中别的格时按住拖 = 按下当场互换。拖动一旦开始, 松手送去落点, 这里收不到 ⇒ 拖和点不会叠。
		##   守卫: tests/verify_team_slot_drag.gd
		var idx = i
		var press := {"p": Vector2.ZERO}
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					press["p"] = ev.position
				elif ev.position.distance_to(press["p"]) < 16.0:
					_on_slot_click(idx))
		# 拖放: 满槽可拖起 + 任意槽可作落点 (1:1 PoC slot draggable + drop)
		panel.set_drag_forwarding(_slot_drag.bind(panel, idx), _slot_can_drop, _slot_drop.bind(idx))
		# 卡面容器(每次刷新整张重画)
		var card := Control.new()
		card.name = "Content"
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(card)
		host._slot_nodes.append(panel)


## 大卡的卡内几何, 按这一格的实际尺寸从背包大卡(192×252)等比换算:
##   横幅 y146 高36 两端伸出 9 / 立绘脚底 y154 / 下沿木托 (6,186,180,62) / 名字 24 号。
func _geo(sz: Vector2) -> Dictionary:
	var kx: float = sz.x / UnitCardArt.NATIVE.x
	var ky: float = sz.y / UnitCardArt.NATIVE.y
	return {
		"b": UnitCardArt.border_for(sz),
		"banner": Rect2(9.0 * kx, 146.0 * ky, sz.x - 18.0 * kx, 36.0 * ky),
		"foot": 154.0 * ky,
		"strip": Rect2(6.0 * kx, 186.0 * ky, 180.0 * kx, 62.0 * ky),
		"fs": maxi(14, int(roundf(24.0 * ky))),
		"q_fs": maxi(28, int(roundf(58.0 * ky))),
		"hint_fs": maxi(14, int(roundf(20.0 * ky))),
		"hint_h": 30.0 * ky,
	}


func _refresh_slots() -> void:
	for i in range(3):
		var panel: PanelContainer = host._slot_nodes[i]
		var card: Control = panel.get_node("Content")
		## 先摘下再删: 只 queue_free 的话旧节点要到帧末才走, 同名新节点(CardFrame / NameBanner…)被引擎改成 @…@ 名, 按名字找不到
		for c in card.get_children():
			card.remove_child(c)
			c.queue_free()
		var sz: Vector2 = panel.size
		var g := _geo(sz)
		var id = host.team[i]
		var act: bool = id == null and i == host._active_slot_idx
		var sel: bool = id != null and i == host._selected_slot_idx
		var pet: Dictionary = {}
		if id != null and not host._is_special_mark(id):
			pet = DataRegistry.pet_by_id.get(str(id), {})
		var b: float = g["b"]
		var bn: Rect2 = g["banner"]
		var strip: Rect2 = g["strip"]
		## 叠放顺序与背包大卡相同: 窗口底 → 立绘 → 框 → 横幅 → 木托
		card.add_child(UnitCardArt.window(sz, b))
		var pw := Rect2(b, b, sz.x - 2.0 * b, strip.position.y - b)
		if id != null and host._is_special_mark(id):
			var vb := VBoxContainer.new()
			vb.alignment = BoxContainer.ALIGNMENT_CENTER
			vb.position = pw.position; vb.size = Vector2(pw.size.x, bn.position.y - pw.position.y)
			vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(vb)
			_fill_mark_slot(vb, id)
		elif not pet.is_empty():
			var body: Array = UnitCardArt.pet_body(str(id))
			if body[0] != null:
				card.add_child(UnitCardArt.portrait(body[0], body[1], pw, g["foot"]))
		else:
			## 空位: 「?」+「空位 / 放置」—— 与背包页占位统领同一个样子; 待填那格字提亮
			var q := Label.new()
			q.text = "?"
			q.add_theme_font_size_override("font_size", g["q_fs"])
			q.add_theme_color_override("font_color", Color("#ffe8a8") if act else Color("#9fb2c8"))
			q.position = pw.position
			q.size = Vector2(pw.size.x, bn.position.y - pw.position.y - float(g["hint_h"]))
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(q)
			var hint := Label.new()
			hint.text = "放置" if act else "空位"
			hint.add_theme_font_size_override("font_size", g["hint_fs"])
			hint.add_theme_color_override("font_color", Color("#ffe8a8") if act else Color("#9a8a70"))
			hint.position = Vector2(b, bn.position.y - float(g["hint_h"]) - 4.0)
			hint.size = Vector2(sz.x - 2.0 * b, float(g["hint_h"]))
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(hint)
		card.add_child(UnitCardArt.frame(sz, false, pet.is_empty() and not act))
		var bn_txt: String
		var bn_col: Color
		if not pet.is_empty():
			bn_txt = str(pet.get("name", "?"))
			bn_col = host.RARITY_COLOR.get(str(pet.get("rarity", "C")), Color.WHITE)
		elif id != null:
			bn_txt = host._mark_label(id)
			bn_col = BANNER_ACTIVE_COL
		else:
			bn_txt = "统领%d" % (i + 1)
			bn_col = BANNER_ACTIVE_COL if act else BANNER_EMPTY_COL
		card.add_child(UnitCardArt.banner(bn_txt, bn_col, bn, g["fs"]))
		card.add_child(_strip(strip, pet))
		## 选中(点了一下准备换位) / 待填 / 锁定版里正在看的那一张: 卡外一圈金边
		var focus: bool = host._roster_locked and not pet.is_empty() and str(id) == host.detail_pet_id
		if sel or act or focus:
			UnitCardArt.ring(card, sz, Color("#ffd86b") if (sel or focus) else Color("#ffe8a8"), 3.0)


## 大卡下沿木托(背包大卡装备托条同一张 shop-plank): 已上阵 = 被动 + 选中的那个技能两枚图标; 空位 = 两个空凹槽。
func _strip(r: Rect2, pet: Dictionary) -> Control:
	var np := NinePatchRect.new()
	np.name = "LoadoutStrip"
	np.texture = host.PLANK_TEX
	np.patch_margin_left = 18; np.patch_margin_right = 18; np.patch_margin_top = 18; np.patch_margin_bottom = 18
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.position = r.position; np.size = r.size
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cell: float = r.size.y - 8.0
	var gap := 8.0
	var texs: Array = [null, null]
	if not pet.is_empty():
		texs[0] = host._skill_picker.passive_tex(pet)
		var lo: Array = host._skill_picker._get_panel_loadout(str(pet.get("id", "")))
		if not lo.is_empty():
			texs[1] = host._skill_picker.skill_tex(pet, int(lo[0]))
	var x0: float = (r.size.x - (2.0 * cell + gap)) * 0.5
	for k in range(2):
		var c := Panel.new()
		c.name = "LoadoutCell%d" % k
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#0c0907")
		sb.border_color = Color("#7a5a36") if texs[k] != null else Color("#3a2c1e")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		c.add_theme_stylebox_override("panel", sb)
		c.position = Vector2(x0 + float(k) * (cell + gap), 4.0)
		c.size = Vector2(cell, cell)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if texs[k] != null:
			var ic := TextureRect.new()
			ic.texture = texs[k]
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.position = Vector2(4, 4); ic.size = Vector2(cell - 8.0, cell - 8.0)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.add_child(ic)
		np.add_child(c)
	return np


## 渲染特殊占位槽内容 (1:1 PoC .fg-summon TeamSelectScene.ts:591-598): 随从?/水晶球img/糖果炸弹img + 彩色名
func _fill_mark_slot(vb: VBoxContainer, mark: String) -> void:
	var nm_text = ""
	var nm_color = Color.WHITE
	if mark == host.SUMMON_MARK:
		nm_text = "随从"; nm_color = Color("#ffc850")
		var q = Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", host._sf(28))
		q.add_theme_color_override("font_color", Color("#ffc850"))
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(q)
	elif mark == host.CRYSTAL_BALL_MARK:
		nm_text = "水晶球"; nm_color = Color("#9b6bff")
		var img = TextureRect.new()
		img.custom_minimum_size = Vector2(host._sp(32), host._sp(32))
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cb = "res://assets/sprites/pets/crystal-ball.png"
		if ResourceLoader.exists(cb):
			img.texture = load(cb)
		vb.add_child(img)
	else:   # CANDY_BOMB_MARK
		## ★★2026-09-28「🍬💣」→ 糖果炸弹**自己的立绘**。
		##   上面水晶球那一支早就是这么画的(`pets/crystal-ball.png`),
		##   只有糖果炸弹这一支拿两个 emoji 凑 —— **同一个函数里两种画法**。
		##   用的是它本人的图(`pets/candy-bomb.png`), 不是拿别件素材顶替。
		##   摆法/尺寸/过滤逐项拄水晶球那支, 不另写一份。
		nm_text = "糖果炸弹"; nm_color = Color("#ff6bd8")
		var cimg = TextureRect.new()
		cimg.custom_minimum_size = Vector2(host._sp(32), host._sp(32))
		cimg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cimg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cimg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cimg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cbomb = "res://assets/sprites/pets/candy-bomb.png"
		if ResourceLoader.exists(cbomb):
			cimg.texture = load(cbomb)
		vb.add_child(cimg)
	var nm = Label.new()
	nm.text = nm_text
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", host._sf(10))
	nm.add_theme_color_override("font_color", nm_color)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)


func _on_slot_click(idx: int) -> void:
	if host._roster_locked:
		if host.team[idx] != null and not host._is_special_mark(host.team[idx]):
			host._set_detail_pet(str(host.team[idx]))   # 锁定态: 点槽=查看该龟(调技能), 不换位/不移除
		return
	var id = host.team[idx]
	var is_mark: bool = id != null and host._is_special_mark(id)
	# === 满槽路径 ===
	if id != null:
		if host._selected_slot_idx == -1:
			host._selected_slot_idx = idx           # 首次 tap: 选中
			host._active_slot_idx = -1
			_refresh_slots()
			return
		if host._selected_slot_idx == idx:
			host._selected_slot_idx = -1            # 二次 tap 同槽: 取消选中 + 移除 (mark 不移)
			if not is_mark:
				host.team[idx] = null
				host._sync_special_slots()
				host._save_team()
			host._refresh_after_team()
			return
		# 二次 tap 不同满槽: SWAP
		var other = host._selected_slot_idx
		var other_is_mark: bool = host._is_special_mark(host.team[other])
		if is_mark or other_is_mark:
			# mark 只能移到空格, 不能与满槽互换 (PoC:1609)
			var mark_from = other if other_is_mark else idx
			var target = idx if other_is_mark else other
			var mark_value = host.team[mark_from]
			if host.team[target] != null:
				host._flash_status("%s 不能被替换" % host._mark_label(mark_value))
				host._selected_slot_idx = -1
				_refresh_slots()
				return
			host.team[target] = mark_value
			host.team[mark_from] = null
		else:
			# 普通 swap
			var tmp = host.team[other]
			host.team[other] = host.team[idx]
			host.team[idx] = tmp
		host._selected_slot_idx = -1
		host._save_team()
		host._refresh_after_team()
		return
	# === 空槽路径 ===
	# (a) 有选中满槽 → 把已选龟移到这 (PoC:1640)
	if host._selected_slot_idx >= 0 and host.team[host._selected_slot_idx] != null:
		host.team[idx] = host.team[host._selected_slot_idx]
		host.team[host._selected_slot_idx] = null
		host._selected_slot_idx = -1
		host._sync_special_slots()
		host._save_team()
		host._refresh_after_team()
		return
	# (b) 空槽 toggle active — 下次点卡片入此槽 (PoC:1651)
	host._selected_slot_idx = -1
	host._active_slot_idx = -1 if host._active_slot_idx == idx else idx
	_refresh_slots()


func _slot_drag(_at_pos: Vector2, panel: Control, idx: int) -> Variant:
	if host._roster_locked:
		return null   # 大轮锁定: 禁槽间换位
	var id = host.team[idx]
	if id == null:
		return null
	## 跟手的是整个槽(DragLift: 拿起不跳 → 中心滑到鼠标下, 原位虚影), 不再是挂在鼠标右下的小头像
	panel.set_drag_preview(DragLift.make(panel, null, _at_pos / panel.size, true))
	return {"pet_id": str(id)}


func _slot_can_drop(_at_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("pet_id")


## drop 到槽 (drop_func; bind → (at_pos, data, idx))
func _slot_drop(_at_pos: Vector2, data: Variant, idx: int) -> void:
	if data is Dictionary and (data as Dictionary).has("pet_id"):
		## 拖放是一次完整的换位, 之前点选留下的「选中」作废(否则高亮按下标挂到换过来的龟上, 下次点击误换 / 误删)。
		##   放在这里而不是 host._on_drop_pet: 那个函数在积分赛逐字节守卫里(verify_gauntlet_online_queue R 段), 而选中本来就是槽位这边的状态。
		if host._selected_slot_idx != -1:
			host._selected_slot_idx = -1
			_refresh_slots()
		host._on_drop_pet(str((data as Dictionary)["pet_id"]), idx)


## 拖放落点处理 (1:1 PoC onDropPet TeamSelectScene.ts:1160)
