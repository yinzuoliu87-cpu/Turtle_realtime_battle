extends Node
## verify_tame_defection.gd — 驯服「归顺」到底换干净没有(用户 2026-07-31)
##
## 用户原话:「尤其是训龟这一个技能，目标有没有正确换血条等等」
##          「有没有正确换阵营，如果对面团灭，被驯服的龟要和友军直接打龟蛋」
##
## ★探针实测到的两个真 bug(都不是读代码看出来的):
##   ① 血条敌我色是 spawn 时 hp_bar.setup(side == "left") 定死的, 之后【没人改】——
##      被驯服的龟逻辑上已经是我方(不打我方/打原队/进我方幸存名单), 血条却一直是敌方红。
##   ② dual_lane_flow._dl_side_alive() 自己手写了一份"只认 hijacked"的阵营判断,
##      于是被驯服的龟【一直给原队顶着一个存活数】: 敌方其余人全死光, 返回值仍是 1
##      → 团灭永远不触发 → 蛋阶段开不了, 本路卡住直到那只归顺龟也死。
##      (主场景那份用的是 _eff_side, 这份没跟上 —— 同一语义在两处各写各的。)
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_tame_defection.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	gs.trainer_skill = "tame"
	gs.dual_active = true
	gs.current_lane = "top"
	print("=== 驯服·归顺是否换干净(血条/阵营/团灭计数/打蛋) ===")

	var s = RB.new()
	add_child(s)
	for _i in range(40):
		await get_tree().process_frame

	# ★走【真实换路入口】建场 —— 龟蛋只有这条路才会生成(_dl_build_lane_field)。
	#   用 _dl_start_fight 之类的近路会拿不到蛋, 后面 ⑦⑧⑨ 全成空检查。
	s._dl_sys._dl_clear_units()
	s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	# ★必须真开打 —— _dl_build_lane_field 结束时 _dl_state 是 "place"(摆放阶段),
	#   那个状态下 sim 不推进, 驯服的到达判定永远不结算, 后面 11 条会一起假红。
	s._dl_sys._dl_start_fight()
	await get_tree().process_frame

	var tr = null
	var victim = null
	var ally = null
	var foe2 = null
	var egg_r = null
	for u in s._units:
		if u.get("_isEgg", false):
			if str(u.get("egg_side_lr", "")) == "right":
				egg_r = u
			continue
		if u.get("is_trainer", false):
			if str(u.get("side", "")) == "left":
				tr = u
			continue
		if str(u.get("side", "")) == "right" and u.get("alive", false):
			if victim == null: victim = u
			elif foe2 == null: foe2 = u
		elif str(u.get("side", "")) == "left" and u.get("alive", false) and ally == null:
			ally = u
	_ok("① ★分母: 大师/受害者/我方友军/敌方第二人/敌方龟蛋 都在场",
		tr != null and victim != null and ally != null and foe2 != null and egg_r != null,
		"tr=%s victim=%s ally=%s foe2=%s egg=%s" % [tr != null, victim != null, ally != null, foe2 != null, egg_r != null])
	if tr == null or victim == null or ally == null or foe2 == null or egg_r == null:
		_done(s); return

	# ── ② 驯服【前】的基线(没有基线, 后面全是"本来就这样") ──
	var hb = victim.get("hp_bar", null)
	_ok("② 基线: 受害者是敌方(_eff_side=right / 血条敌方色 / 与我方敌对)",
		s._eff_side(victim) == "right" and hb != null and hb.is_ally == false
			and s._is_hostile(victim, ally),
		"_eff_side=%s is_ally=%s" % [s._eff_side(victim), (str(hb.is_ally) if hb != null else "无条")])
	var alive_r0: int = s._dl_sys._dl_side_alive("right")
	_ok("② ★基线: 未驯服时它【算】敌方存活(否则 ⑤ 是空检查)", alive_r0 >= 2,
		"敌方存活 %d" % alive_r0)

	# ── ③ 施放驯服(真入口), 推进到归顺生效 ──
	victim["pos"] = tr["pos"] + Vector2(200.0, 0.0)
	tr["_active_cd"] = 0.0
	var cast_ok: bool = s._trainer_sys._cast_tame(tr, Vector2(200.0, 0.0))
	_ok("③ 经真入口 _cast_tame 放得出去", cast_ok)
	# ★★驯服是【标记】, 不是当场换队 —— 归顺只在被标记者【死亡】时触发
	#   (_kill → _tame_try_revive → 30% 最大生命复活 + tamed_side=施法方)。
	#   我第一版只是干等 1200 帧, 结果 tamed_side 一直是空 —— 不是 bug, 是我没让它死。
	#   标记本身走 _pending_shots(按飞行距离定时), 所以先等标记, 再杀。
	var w := 0
	while w < 600 and not victim.get("tame_pending", false):
		s._sim_step(1.0 / 60.0, false, false)
		w += 1
	_ok("③ ★标记先落地(tame_pending·走 _pending_shots 到达才标)",
		bool(victim.get("tame_pending", false)), "推了 %d 帧" % w)
	_ok("③ ★标记记下了施法方", str(victim.get("tame_by_side", "")) == "left")
	s._kill(victim)                                        # 被标记者死亡 → 归顺
	_ok("③ ★★归顺真的落地(tamed_side=left, 且是【复活】不是真死)",
		str(victim.get("tamed_side", "")) == "left" and victim.get("alive", false),
		"tamed_side=%s alive=%s hp=%.0f/%.0f" % [str(victim.get("tamed_side", "")),
			victim.get("alive", false), float(victim.get("hp", 0)), float(victim.get("maxHp", 1))])
	_ok("③ 复活血量 = 30% 最大生命(需求字面值)",
		absf(float(victim.get("hp", 0)) / maxf(1.0, float(victim.get("maxHp", 1))) - 0.30) < 0.02,
		"%.1f%%" % (100.0 * float(victim.get("hp", 0)) / maxf(1.0, float(victim.get("maxHp", 1)))))
	for _i in range(180):                                  # 跨过 2.5s 重生演出(无敌/不可选中)
		s._sim_step(1.0 / 60.0, false, false)
		s._render._render_step(1.0 / 60.0, false, false)
		victim["hp"] = maxf(1.0, float(victim["hp"]))       # 每秒 2% 掉血 buff 会一路掉, 别让它死
		victim["alive"] = true

	# ── ④ 阵营换了 ──
	print("")
	_ok("④ ★有效阵营变我方", s._eff_side(victim) == "left")
	_ok("④ ★不再与我方友军敌对", not s._is_hostile(victim, ally))
	_ok("④ ★开始与原队友敌对", s._is_hostile(victim, foe2))
	_ok("④ ★索敌名单里是原队(_pick_enemies_of 至少含原队友)",
		_arr_has(s._targeting._pick_enemies_of(victim), foe2))

	# ── ⑤ 血条换色(走真 render 路, 不是读字段就完事) ──
	print("")
	for _k in range(4):
		s._render._render_step(1.0 / 60.0, false, false)
	_ok("⑤ ★★血条敌我色跟着换成我方(改前是 spawn 定死、永远红)",
		hb != null and hb.is_ally == true,
		"is_ally=%s" % (str(hb.is_ally) if hb != null else "无条"))
	# ★头像栏: 归顺后应当挪到【我方】那一栏(它是 spawn 时建一次的, 靠归顺时主动重建)
	var fr = victim.get("panel_frame", null)
	_ok("⑤ ★★头像框挪到我方栏(改前一直挂在敌方栏)",
		fr != null and is_instance_valid(fr) and fr.get_parent() != null
			and is_same(fr.get_parent(), s._team_panel_left),
		"父节点 = %s (我方栏=%s)" % [(str(fr.get_parent()) if fr != null and is_instance_valid(fr)
			and fr.get_parent() != null else "无"), str(s._team_panel_left)])
	var fr_ally = ally.get("panel_frame", null)
	_ok("⑤ ★分母: 我方原有单位的框还在我方栏(重建没把别人搞丢)",
		fr_ally != null and is_instance_valid(fr_ally) and fr_ally.get_parent() != null
			and is_same(fr_ally.get_parent(), s._team_panel_left))
	# ★★边框色: 必须【推进渲染若干帧之后】再量 —— _update_team_panels 每帧会重刷它,
	#   建框时设对了不算数。我第一版只改了建框那处, 实拍抓到左栏里挂着一个红框。
	for _k in range(6):
		s._render._render_step(1.0 / 60.0, false, false)
	var sb_v = victim.get("panel_stylebox", null)
	_ok("⑤ ★★头像框边框色 = 我方蓝(每帧重刷之后仍是我方色)",
		sb_v != null and sb_v is StyleBoxFlat
			and (sb_v as StyleBoxFlat).border_color.is_equal_approx(Color("#3fa9ff")),
		"边框色 = %s (我方蓝应为 %s)" % [(str((sb_v as StyleBoxFlat).border_color) if sb_v != null else "无"),
			str(Color("#3fa9ff"))])
	var sb_f = foe2.get("panel_stylebox", null)
	_ok("⑤ ★分母: 没归顺的敌人边框仍是敌方红(否则上面是'全都变蓝了')",
		sb_f != null and sb_f is StyleBoxFlat
			and (sb_f as StyleBoxFlat).border_color.is_equal_approx(Color("#ff5a5a")),
		"边框色 = %s" % (str((sb_f as StyleBoxFlat).border_color) if sb_f != null else "无"))
	var fr_foe = foe2.get("panel_frame", null)
	_ok("⑤ ★分母: 没归顺的敌人仍在敌方栏(否则上面是'全都挪过来了')",
		fr_foe != null and is_instance_valid(fr_foe) and fr_foe.get_parent() != null
			and is_same(fr_foe.get_parent(), s._team_panel_right))
	# ★名字也要对得上 —— 光验"挂在 _team_panel_left 上"守不住"栏被改名了"(实测 @VBoxContainer@566)
	_ok("⑤ ★两栏节点名没被 Godot 自动改掉(旧栏未及时移除会占名)",
		str(s._team_panel_left.name) == "TeamPanel_left"
			and str(s._team_panel_right.name) == "TeamPanel_right",
		"left=%s right=%s" % [str(s._team_panel_left.name), str(s._team_panel_right.name)])

	# ── ⑥ 团灭计数: 归顺者不再给原队顶存活数 ──
	print("")
	for u in s._units:
		if str(u.get("side", "")) == "right" and u.get("alive", false) \
			and not u.get("_isEgg", false) and not u.get("is_trainer", false) \
			and not is_same(u, victim):
			u["alive"] = false
			u["hp"] = 0.0
	var alive_r: int = s._dl_sys._dl_side_alive("right")
	_ok("⑥ ★★敌方只剩这只归顺龟时, 敌方存活数 = 0(改前是 1 → 永不团灭)",
		alive_r == 0, "_dl_side_alive(right) = %d (驯服前是 %d)" % [alive_r, alive_r0])
	_ok("⑥ ★同时它【算进】我方存活数(不是两边都不算, 那样我方会被误判团灭)",
		s._dl_sys._dl_side_alive("left") >= 2, "_dl_side_alive(left) = %d" % s._dl_sys._dl_side_alive("left"))

	# ── ⑦ 团灭真的触发 + 敌方蛋围栏掉了 ──
	print("")
	_ok("⑦ ★分母: 蛋此刻还有围栏(否则 ⑦ 白测)", bool(egg_r.get("_egg_fence", false)))
	battle_tick(s, 90)
	_ok("⑦ ★★团灭真的触发(状态进 eggwindow)", str(battle_state(s)) == "eggwindow",
		"_dl_state = %s" % str(battle_state(s)))
	_ok("⑦ ★敌方蛋围栏已掉(可被索敌)", not bool(egg_r.get("_egg_fence", false)))

	# ── ⑧⑨ 归顺龟和友军一起打敌方蛋 ──
	print("")
	victim["pos"] = egg_r["pos"] + Vector2(-60.0, 0.0)      # 贴到蛋边上
	var tgt = s._targeting._nearest_enemy(victim)
	_ok("⑧ ★★归顺龟索敌能锁到【敌方蛋】(和友军一样)",
		tgt != null and is_same(tgt, egg_r),
		"锁到 %s" % (str(tgt.get("id", tgt.get("name", "?"))) if tgt != null else "null"))
	_ok("⑧ ★它【不会】去锁我方的蛋(那是自己人的)",
		not _arr_has(s._targeting._pick_enemies_of(victim), _egg_of(s, "left")))
	var hp0: float = float(egg_r.get("hp", 0.0))
	var w2 := 0
	while w2 < 900 and float(egg_r.get("hp", 0.0)) >= hp0:
		victim["pos"] = egg_r["pos"] + Vector2(-60.0, 0.0)  # 钉住(活单位会被 sim 挪走)
		victim["alive"] = true
		s._sim_step(1.0 / 60.0, false, false)
		w2 += 1
	_ok("⑨ ★★归顺龟真的把敌方蛋打掉血了(整条链通)",
		float(egg_r.get("hp", 0.0)) < hp0,
		"蛋 %.0f → %.0f (推了 %d 帧)" % [hp0, float(egg_r.get("hp", 0.0)), w2])

	_done(s)


func battle_tick(s, n: int) -> void:
	for _i in range(n):
		s._sim_step(1.0 / 60.0, false, false)


func battle_state(s) -> String:
	return str(s._dl_state)


func _egg_of(s, lr: String):
	for u in s._units:
		if u.get("_isEgg", false) and str(u.get("egg_side_lr", "")) == lr:
			return u
	return null


## ★单位字典不能用 in / has —— Godot 会递归哈希互引成环的字典 → 卡死(项目铁律)。
func _arr_has(arr: Array, x) -> bool:
	if x == null:
		return false
	for o in arr:
		if is_same(o, x):
			return true
	return false


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条)" % _n)
	print("ALL PASS — 驯服归顺换阵营/换血条/团灭计数/打敌方蛋" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
