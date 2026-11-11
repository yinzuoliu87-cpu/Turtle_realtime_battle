extends Node
## verify_spirit_dmg_row.gd —— 灵物触手伤害在战报 / 结算表单列一行(2026-11-11)。
## 用户 11-11:「关于这个羁绊领悟，整个伤害面板都没有统计这个出手的伤害，反而是把这个伤害归类为了这个龟的伤害。
##   为什么不单独做一个就是羁绊，就是触手，触手造成的伤害呢？或者说你写这个灵物，然后伤害值也可以」。
## 口径(方案书 docs/plans/20261111-忍者普攻与小将铁链与灵物统计.md §4 D): 拍击伤害仍记在来源龟的 _st_dealt(sim 账: 钩爆 /
##   香炉石 / 猎龟令都读它, 改账会改对局结果), 另记 _st_spirit_dealt; 显示时龟那一行扣掉、本方多一行「灵物触手」、不评 MVP。
## 判据: 走真拍击入口 spirit_synergy_system._slap_resolve 打一下(不是手写 _st_* 键)。
##   ① sim 账: 来源龟 _st_dealt 涨了这一下全额(与改前同口径)
##   ② 灵物份额 = 这一下; 龟显示值 = _st_dealt - 灵物份额(战报 val / 结算行 _st_row)
##   ③ 每路快照多一行「灵物触手」= 份额; 合计页(_st_merge_all 再过一遍 _st_row)后标记与头像还在
##   ④ MVP 不评灵物行; 战报 render 也列出这一行
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 灵物触手伤害单列 ===")
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(4):
		await get_tree().process_frame
	for u0 in s._units.duplicate():
		var sp0 = u0.get("sprite", null)
		if sp0 != null and is_instance_valid(sp0):
			sp0.queue_free()
	s._units.clear()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var me: Dictionary = s._spawn._make_unit("stone", "left", c + Vector2(-200, 0))
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(100, 0))
	foe["maxHp"] = 90000.0
	foe["hp"] = 90000.0
	me["no_move"] = true; me["no_basic"] = true
	foe["no_move"] = true; foe["no_basic"] = true
	s._units.append(me)
	s._units.append(foe)
	## 先让龟自己打一下(非灵物), 再走真拍击入口拍一下
	s._damage._apply_damage_from(me, foe, 100, Color.RED)
	var d0: int = int(me.get("_st_dealt", 0))
	var hp0: float = float(foe["hp"])
	var hits: int = s._spirit_syn._slap_resolve("left", c + Vector2(-100, 0), Vector2.RIGHT, 600.0, 1.0)
	var slap: int = int(round(hp0 - float(foe["hp"])))
	_ok("分母: 真拍击入口打中 %d 个、掉血 %d" % [hits, slap], hits == 1 and slap > 0)
	_ok("① sim 账: 来源龟 _st_dealt 涨了拍击全额(%d → %d)" % [d0, int(me.get("_st_dealt", 0))], int(me.get("_st_dealt", 0)) == d0 + slap)
	_ok("② 灵物份额 = 拍击这一下", int(me.get("_st_spirit_dealt", 0)) == slap, "%d vs %d" % [int(me.get("_st_spirit_dealt", 0)), slap])
	_ok("② 龟自己的 100 不算进灵物份额", int(me.get("_st_spirit_dealt", 0)) != d0 + slap)
	_ok("② 战报龟那一行 = 扣掉灵物份额", DmgStatsPanel.val(me, "dealt") == d0, "%d" % DmgStatsPanel.val(me, "dealt"))
	var pt: int = 0
	for p in DmgStatsPanel.parts(me, "dealt"):
		pt += int(p[0])
	_ok("② 战报龟那一行分段条合计 = 显示值", pt == d0, "%d" % pt)
	var row: Dictionary = s._st_row(me)
	_ok("② 结算行龟 = 扣掉灵物份额", int(row["_st_dealt"]) == d0 and int(row["_st_phy"]) + int(row["_st_mag"]) + int(row["_st_tru"]) == d0, str([row["_st_dealt"], row["_st_phy"], row["_st_mag"], row["_st_tru"]]))
	## ③ 每路快照
	s._st_lane_hist.clear()
	s._st_snapshot_lane("top")
	var snap: Dictionary = s._st_lane_hist[0]
	var srow: Dictionary = {}
	for r in snap["left"]:
		if bool(r.get("_st_spirit", false)):
			srow = r
	_ok("③ 快照我方多一行「灵物触手」", not srow.is_empty() and str(srow.get("name", "")) == "灵物触手", str(srow.get("name", "")))
	_ok("③ 灵物行伤害 = 份额、分类型合计对得上", int(srow.get("_st_dealt", -1)) == slap and int(srow.get("_st_phy", 0)) + int(srow.get("_st_mag", 0)) + int(srow.get("_st_tru", 0)) == slap)
	var enemy_spirit := false
	for r in snap["right"]:
		if bool(r.get("_st_spirit", false)):
			enemy_spirit = true
	_ok("③ 敌方没有拍击 ⇒ 没有灵物行", not enemy_spirit)
	## 合计页: 两路快照 → _st_merge_all(内部再过一遍 _st_row)
	s._st_snapshot_lane("bot")
	var pages: Array = [{"lane": "top", "left": s._st_lane_hist[0]["left"], "right": s._st_lane_hist[0]["right"]},
		{"lane": "bot", "left": s._st_lane_hist[1]["left"], "right": s._st_lane_hist[1]["right"]}]
	var merged: Array = s._hud._st_merge_all(pages, "left")
	var mrow: Dictionary = {}
	for r in merged:
		if bool(r.get("_st_spirit", false)):
			mrow = r
	_ok("③ 合计页灵物行还在(标记没被 _st_row 丢掉)、两路相加", not mrow.is_empty() and int(mrow.get("_st_dealt", 0)) == slap * 2, str(mrow.get("_st_dealt", -1)))
	_ok("③ 合计页灵物行头像 = 灵物羁绊图标", str(mrow.get("_st_portrait", "")) == "res://assets/sprites/tags/tag-spirit.png", str(mrow.get("_st_portrait", "")))
	## ④ MVP: 灵物行比龟打得多也不评
	var fake: Dictionary = srow.duplicate()
	fake["_st_dealt"] = 999999
	var mvp: int = s._hud._st_mvp_index([row, fake])
	_ok("④ MVP 不评灵物行(灵物行伤害更高仍选龟)", mvp == 0, "下标 %d" % mvp)
	## ④ 战报 render: 我方那一列列出灵物行
	var panel := DmgStatsPanel.new()
	var lay := CanvasLayer.new()
	add_child(lay)
	panel.setup(lay, func(sd: String) -> Array:
		var out: Array = []
		for u in s._units:
			if str(u.get("side", "")) == sd:
				out.append(u)
		return out)
	panel.toggle()
	panel.render()
	var names: Array = []
	for col in panel._cols:
		for rw in (col as Node).get_children():
			for lb in rw.find_children("*", "Label", true, false):
				names.append((lb as Label).text)
	_ok("④ 战报列出「灵物触手」一行", names.has("灵物触手"), str(names.slice(0, 12)))
	s.queue_free()
	await get_tree().process_frame
	if _fail == 0:
		print("ALL PASS (%d 项)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
