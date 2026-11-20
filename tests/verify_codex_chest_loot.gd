extends Node
## verify_codex_chest_loot.gd — 图鉴「装备」栏列出宝箱龟藏宝图能开出的全部战利品(2026-11-20)
##
## 用户 2026-11-20「宝箱龟的这好像是十八个那个被动装备吧，需要在图鉴里面去显示」→
##   「十几件装备其实可以放在装备那一栏不用塞到龟里面吧」(方案书 docs/plans/20261120-宝箱龟图鉴战利品与普攻特效.md; 件数读 ChestLoot.POOL)。
## 判据(全部量活场景里真画出来的节点, 走真入口 _switch_tab → _select):
##   ① 装备栏末尾一组「宝箱龟战利品」: 条目数 = ChestLoot.POOL 总件数, 顺序 = 基础 → 进阶 → 传说, 一件不重不漏, 排在所有装备后面
##   ② 逐件点开: 名字 = ChestLoot.NAME, 效果 = ChestLoot.desc_plain, 副标写池名 + 第几箱(与战斗开箱同一张 OPEN_ORDER), 有获得方式
##   ③ 手机 / iPad 两种比例: 详情页的字都在详情框内、屏幕内
##   ④ 龟页(含宝箱龟)不再有战利品那一节
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


func _one(nm: String) -> Node:
	for ch in _c.detail.get_children():
		if not ch.is_queued_for_deletion() and str(ch.name) == nm:
			return ch
	return null


func _loot_idx() -> Array:
	var out: Array = []
	for i in range(_c._items.size()):
		var it = _c._items[i]
		if it is Dictionary and (it as Dictionary).has("_loot"):
			out.append(i)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 图鉴装备栏: 宝箱龟藏宝图全部战利品 ===")
	_c = CODEX_SCN.instantiate()
	add_child(_c)
	await _settle(8)

	var want: Array = []
	for g in ChestLoot.POOL.keys():
		for tid in ChestLoot.POOL[g]:
			want.append(str(tid))
	_ok("★分母: ChestLoot.POOL 有 %d 件、三个池子; 开箱顺序表与阈值表一样长" % want.size(),
		want.size() >= 10 and ChestLoot.POOL.size() == 3 and ChestLoot.OPEN_ORDER.size() == ChestLoot.THRESH.size())

	# ① 列表
	_c._switch_tab("equips")
	await _settle(4)
	var li: Array = _loot_idx()
	var got: Array = []
	for i in li:
		got.append(str(_c._items[i]["_loot"]))
	_ok("★★★① 装备栏的战利品条目 = POOL 全部 %d 件、顺序基础 → 进阶 → 传说" % want.size(), got == want, "列出 %s" % str(got))
	var last_eq := -1
	for i in range(_c._items.size()):
		var it = _c._items[i]
		if it is Dictionary and not (it as Dictionary).has("_loot"):
			last_eq = i
	_ok("★① 战利品一组排在所有装备后面、连成一组", not li.is_empty() and int(li[0]) > last_eq and int(li.back()) - int(li[0]) == li.size() - 1,
		"装备末行 %d · 战利品 %s~%s" % [last_eq, str(li.front()) if not li.is_empty() else "-", str(li.back()) if not li.is_empty() else "-"])
	var head_ok := false
	for n in _c.list_vbox.get_children():
		for l in n.find_children("*", "Label", true, false):
			if (l as Label).text == "宝箱龟战利品":
				head_ok = true
	_ok("★① 列表里有这一组的标题「宝箱龟战利品」", head_ok)

	# ② 逐件点开 + ③ 两种比例
	for sz in SIZES:
		get_window().size = sz[1]
		await _settle(6)
		var n := 0
		var bad: Array = []
		var out: Array = []
		for k in range(li.size()):
			var tid: String = str(want[k]) if k < want.size() else ""
			_c._select(int(li[k]))
			await _settle(2)
			n += 1
			var nm := _one("LootName") as Label
			var sub := _one("LootSub") as Label
			var ds := _one("LootDesc") as RichTextLabel
			var src := _one("LootSource") as RichTextLabel
			var g: String = ChestLoot.pool_of(tid)
			if nm == null or ds == null or sub == null or src == null:
				bad.append("%s:没画全" % tid)
				continue
			if nm.text != str(ChestLoot.NAME.get(tid, "")):
				bad.append("%s:名字「%s」" % [tid, nm.text])
			if _plain(ds.text).strip_edges() != ChestLoot.desc_plain(tid).strip_edges() or ChestLoot.desc_plain(tid).strip_edges() == "":
				bad.append("%s:效果「%s」" % [tid, _plain(ds.text).left(16)])
			if sub.text.find(str(ChestLoot.POOL_NAME.get(g, "?"))) < 0 or sub.text.find(ChestLoot.box_text(g)) < 0 or ChestLoot.box_text(g) == "":
				bad.append("%s:副标「%s」" % [tid, sub.text])
			if _plain(src.text).find(ChestLoot.box_text(g)) < 0 or _plain(src.text).find("藏宝图") < 0:
				bad.append("%s:获得方式「%s」" % [tid, _plain(src.text).left(16)])
			# ③ 详情框内 / 屏幕内(横向; 竖向超出由详情框自己滚)
			var clip: Rect2 = (_c.detail.get_parent() as Control).get_global_rect()
			var vr: Rect2 = get_viewport().get_visible_rect()
			for c in [nm, sub, ds, src]:
				var r: Rect2 = (c as Control).get_global_rect()
				var w: float = (c as Control).get_combined_minimum_size().x if c is Label else r.size.x
				var right: float = r.position.x + w
				if r.position.x < clip.position.x - 0.5 or right > clip.end.x + 0.5 or r.position.x < vr.position.x or right > vr.end.x + 0.5:
					out.append("%s:%s" % [tid, (c as Node).name])
		_ok("★分母[%s]: 逐件点了 %d 件" % [sz[0], n], n == want.size())
		_ok("★★★②[%s] 名字 / 效果 / 池名 · 第几箱 / 获得方式都对得上 ChestLoot" % sz[0], bad.is_empty(), str(bad.slice(0, 4)))
		_ok("★★③[%s] 详情页的字都在详情框内、屏幕内" % sz[0], out.is_empty(), str(out.slice(0, 4)))
	_ok("★② 第几箱与战斗开箱顺序一致(基础 1-2 / 进阶 3-4 / 传说 5)",
		ChestLoot.box_text("basic") == "第 1-2 箱" and ChestLoot.box_text("adv") == "第 3-4 箱"
		and ChestLoot.box_text("legend") == "第 %d 箱" % ChestLoot.OPEN_ORDER.size())

	# ④ 龟页不再有战利品那一节
	_c._switch_tab("pets")
	await _settle(4)
	var n_pet := 0
	var chest_seen := false
	var leaked: Array = []
	for i in range(_c._items.size()):
		var it = _c._items[i]
		if not (it is Dictionary) or (it as Dictionary).has("_minion"):
			continue
		_c._select(i)
		await _settle(2)
		n_pet += 1
		if str(it.get("id", "")) == "chest":
			chest_seen = true
		for ch in _c.detail.get_children():
			if not ch.is_queued_for_deletion() and str(ch.name).begins_with("Loot"):
				leaked.append(str(it.get("id", "")))
				break
	_ok("★分母: 量了 %d 只龟(含宝箱龟)" % n_pet, n_pet >= 20 and chest_seen)
	_ok("★★④ 龟页不再有战利品那一节", leaked.is_empty(), str(leaked))
	_finish()


func _finish() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 图鉴装备栏宝箱龟战利品")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
