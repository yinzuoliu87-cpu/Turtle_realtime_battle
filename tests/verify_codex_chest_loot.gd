extends Node
## verify_codex_chest_loot.gd — 图鉴宝箱龟页列出藏宝图能开出的全部战利品(2026-11-20)
##
## 用户 2026-11-20「宝箱龟的这好像是十八个那个被动装备吧，需要在图鉴里面去显示」
##   (方案书 docs/plans/20261120-宝箱龟图鉴战利品与普攻特效.md; 实际件数读 ChestLoot.POOL)。
## 判据(全部量活场景里真画出来的节点, 走真入口 _switch_tab → _select → 点图标):
##   ① 宝箱龟页图标数 = ChestLoot.POOL 总件数, 每个池子的件数对得上, 一件不重不漏
##   ② 每个池子的抬头写池名 + 第几箱(第几箱从 ChestLoot.OPEN_ORDER 推, 与战斗开箱同一张表)
##   ③ 手机 / iPad 两种比例: 图标全在右栏内、在屏幕内, 互不重叠, 普攻条 / 技能在它下面
##   ④ 逐件点开: 名字 = ChestLoot.NAME, 说明 = ChestLoot.desc_plain; 再点同一件收起
##   ⑤ 别的龟页没有这一节
## ★每条配分母; 反向验证见方案书第 6 节。

const CODEX_SCN := preload("res://scenes/Codex.tscn")
const SIZES := [["phone", Vector2i(1560, 720)], ["ipad", Vector2i(960, 720)]]

var _n := 0
var _fail := 0
var _c = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _settle(n: int = 4) -> void:
	for _i in range(n):
		await get_tree().process_frame


## BBCode 去掉只留玩家读到的字; 内联属性图标([img]路径[/img])整段去掉。
func _plain(t: String) -> String:
	t = RegEx.create_from_string("[\\[]img[^\\]]*[\\]][^\\[]*[\\[]/img[\\]]").sub(t, "", true)
	return RegEx.create_from_string("[\\[][^\\]]*[\\]]").sub(t, "", true).replace("  ", " ")


func _open_pet(pid: String) -> bool:
	for i in range(_c._items.size()):
		var it = _c._items[i]
		if it is Dictionary and str(it.get("id", "")) == pid and not it.has("_minion"):
			_c._select(i)
			await _settle(3)
			return true
	return false


func _live(prefix: String) -> Array:
	var out: Array = []
	for ch in _c.detail.get_children():
		if not ch.is_queued_for_deletion() and str(ch.name).begins_with(prefix):
			out.append(ch)
	return out


func _one(nm: String) -> Node:
	var a := _live(nm)
	for ch in a:
		if str(ch.name) == nm:
			return ch
	return null


func _tap(hit: Control) -> void:
	for down in [true, false]:   # 一次点按 = 按下 + 松开(CodexDetail._tap_hit 松手才算点)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = hit.size * 0.5
		ev.global_position = hit.get_global_rect().get_center()
		hit.gui_input.emit(ev)
	await _settle(3)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 图鉴宝箱龟页: 藏宝图全部战利品 ===")
	_c = CODEX_SCN.instantiate()
	add_child(_c)
	await _settle(8)
	_c._switch_tab("pets")
	await _settle(4)

	var total := 0
	for g in ChestLoot.POOL.keys():
		total += (ChestLoot.POOL[g] as Array).size()
	_ok("★分母: ChestLoot.POOL 有 %d 件、三个池子; 开箱顺序表与阈值表一样长" % total,
		total >= 10 and ChestLoot.POOL.size() == 3 and ChestLoot.OPEN_ORDER.size() == ChestLoot.THRESH.size())

	for sz in SIZES:
		get_window().size = sz[1]
		await _settle(6)
		print("── %s %s ──" % [sz[0], str(sz[1])])
		var found: bool = await _open_pet("chest")
		_ok("★分母[%s]: 图鉴里找得到宝箱龟(走真 _select)" % sz[0], found)
		if not found:
			continue
		_check_strip(str(sz[0]), total)
		if sz[0] == "phone":
			await _check_taps()

	# ⑤ 别的龟页没有这一节
	var n_other := 0
	var leaked: Array = []
	for it in _c._items:
		if not (it is Dictionary) or it.has("_minion") or str(it.get("id", "")) == "chest":
			continue
		if not await _open_pet(str(it.get("id", ""))):
			continue
		n_other += 1
		if not _live("LootHit_").is_empty() or not _live("LootGroup_").is_empty():
			leaked.append(str(it.get("id", "")))
	_ok("★分母: 量了 %d 只别的龟" % n_other, n_other >= 20)
	_ok("★★⑤ 别的龟页没有战利品这一节", leaked.is_empty(), str(leaked))
	_finish()


func _check_strip(tag: String, total: int) -> void:
	var hits := _live("LootHit_")
	var ids: Dictionary = {}
	for h in hits:
		ids[str((h as Node).get_meta("loot_id", ""))] = true
	_ok("★★★①[%s] 图标数 = %d(POOL 全部件数), 一件不重" % [tag, total], hits.size() == total and ids.size() == total,
		"图标 %d · 不同 id %d" % [hits.size(), ids.size()])
	var miss: Array = []
	for g in ChestLoot.POOL.keys():
		for tid in ChestLoot.POOL[g]:
			if not ids.has(str(tid)) or _one("LootSlot_%s" % tid) == null:
				miss.append(str(tid))
	_ok("★★①[%s] POOL 每一件都有图标槽" % tag, miss.is_empty(), "缺 %s" % str(miss))
	# ② 池子抬头
	var bad_head: Array = []
	for g in ChestLoot.POOL.keys():
		var gl := _one("LootGroup_%s" % g) as Label
		var want := "%s · %s" % [ChestLoot.POOL_NAME.get(g, ""), ChestLoot.box_text(str(g))]
		if gl == null or gl.text != want or ChestLoot.box_text(str(g)) == "":
			bad_head.append("%s:%s" % [g, gl.text if gl != null else "<无>"])
	_ok("★★②[%s] 三个池子的抬头 = 池名 · 第几箱" % tag, bad_head.is_empty(), str(bad_head))
	_ok("★②[%s] 第几箱与战斗开箱顺序一致(基础 1-2 / 进阶 3-4 / 传说 5)" % tag,
		ChestLoot.box_text("basic") == "第 1-2 箱" and ChestLoot.box_text("adv") == "第 3-4 箱"
		and ChestLoot.box_text("legend") == "第 %d 箱" % ChestLoot.OPEN_ORDER.size())
	# ③ 不出界 / 不重叠 / 在普攻条上面
	var clip: Control = _c.detail.get_parent() as Control
	var clip_r: Rect2 = clip.get_global_rect()
	var vr: Rect2 = get_viewport().get_visible_rect()
	var right_x: float = CodexDetail.RCOL_X + _c._codex_detail._rw()
	var out: Array = []
	var rects: Array = []
	var bottom := 0.0
	for s in _live("LootSlot_"):
		var c := s as Control
		var r: Rect2 = c.get_global_rect()
		rects.append(r)
		bottom = maxf(bottom, c.position.y + c.size.y)
		if c.position.x < CodexDetail.RCOL_X - 0.5 or c.position.x + c.size.x > right_x + 0.5 \
				or r.position.x < clip_r.position.x - 0.5 or r.end.x > clip_r.end.x + 0.5 \
				or r.position.x < vr.position.x or r.end.x > vr.end.x:
			out.append(str(c.name))
	for gl in _live("LootGroup_"):
		var lc := gl as Control
		var lr := Rect2(lc.position, lc.get_combined_minimum_size())
		if lr.end.x > right_x + 0.5:
			out.append(str(lc.name))
		for s in _live("LootSlot_"):
			if lr.intersects(Rect2((s as Control).position, (s as Control).size)):
				out.append("%s×%s" % [lc.name, (s as Node).name])
	_ok("★分母[%s]: 量了 %d 个图标槽" % [tag, rects.size()], rects.size() == total)
	_ok("★★★③[%s] 图标槽 / 抬头都在右栏内、详情框内、屏幕内, 抬头不压图标" % tag, out.is_empty(), str(out.slice(0, 6)))
	var overlap := 0
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).grow(-0.5).intersects(rects[j]):
				overlap += 1
	_ok("★③[%s] 图标槽互不重叠" % tag, overlap == 0, "重叠 %d 对" % overlap)
	var bb := _one("BasicBar") as Control
	_ok("★★③[%s] 普攻条排在战利品下面(不被压)" % tag, bb != null and bb.position.y >= bottom,
		"普攻条 y=%.0f · 战利品底 %.0f" % [bb.position.y if bb != null else -1.0, bottom])


func _check_taps() -> void:
	var n := 0
	var bad: Array = []
	for g in ChestLoot.POOL.keys():
		for tid in ChestLoot.POOL[g]:
			var hit := _one("LootHit_%s" % tid) as Control
			if hit == null:
				bad.append("%s:无热区" % tid)
				continue
			await _tap(hit)
			n += 1
			var nm := _one("LootName") as Label
			var ds := _one("LootDesc") as RichTextLabel
			var want_desc: String = ChestLoot.desc_plain(str(tid)).strip_edges()
			if nm == null or ds == null:
				bad.append("%s:没展开" % tid)
			elif nm.text != str(ChestLoot.NAME.get(tid, "")) or str(ds.get_meta("loot_id", "")) != str(tid):
				bad.append("%s:名字「%s」" % [tid, nm.text])
			elif want_desc == "" or _plain(ds.text).strip_edges() != want_desc:
				bad.append("%s:说明「%s」≠「%s」" % [tid, _plain(ds.text).left(20), want_desc.left(20)])
	_ok("★分母: 逐件点了 %d 件" % n, n == ChestLoot.NAME.size())
	_ok("★★★④ 逐件点开: 名字与说明都对得上 ChestLoot", bad.is_empty(), str(bad.slice(0, 4)))
	# 展开后普攻条仍在说明下面
	var ds2 := _one("LootDesc") as RichTextLabel
	var bb := _one("BasicBar") as Control
	_ok("★④ 展开说明时普攻条让到说明下面", ds2 != null and bb != null
		and bb.position.y >= ds2.position.y + ds2.get_content_height() - 0.5)
	# 再点同一件收起
	var last_tid := str((ChestLoot.POOL["legend"] as Array).back())
	var h2 := _one("LootHit_%s" % last_tid) as Control
	var had: bool = h2 != null and _one("LootDesc") != null   # 点之前: 热区在、说明开着(重画后 h2 已释放, 先记下)
	if h2 != null:
		await _tap(h2)
	_ok("★★④ 再点同一件 ⇒ 说明收起", had and _one("LootDesc") == null and _one("LootName") == null,
		"sel=「%s」 desc=%s" % [_c._codex_loot_sel, str(_one("LootDesc"))])


func _finish() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 图鉴宝箱龟页战利品")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
