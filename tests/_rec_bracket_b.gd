extends Node
## _rec_bracket_b.gd —— 周日对阵图一整晚的成品视频素材(给人看的, 不是门禁 · 方案书 20261031c 块 B)。
## 用 Movie Maker 录(1280×720, 60fps; `--resolution` 对录屏无效, iPad 比例用临时 override.cfg):
##   WINDOW=1 bash godot-quiet.sh --position 2000,80 --write-movie C:/tmp/sunday_redo/B/video/full.avi res://tests/_rec_bracket_b.tscn
##   REC_MODE=ipad … ⇒ 短版(全部组宫格 + 冠军杯开播 + 收盘)
## 时间线(每段硬切): 18:00 前倒计时 → 小组备战 → 小组开播中(+ 全局小条)→ 看完回来红叉 + 光点 → 本轮名牌墙 → 备战屏
##   → 组冠军(ChampionShow 组版)→ 全部组宫格 → 冠军杯开场亮相(ChampionIntro)→ 冠军杯开播中
##   → 冠军收盘(ChampionShow 杯版 · 冠军本人 · 领奖)→ 领奖台收盘 → 冠军墙。
## ★时刻全钉死, 每帧按录像时间推进 `_now_override`(倒计时真的在走); 数据全是造的(同 _shot_bracket_b)。

const SH := preload("res://tests/_shot_bracket_b.gd")
const SCENE := preload("res://scripts/scenes/BracketMapScene.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const HERO := preload("res://scripts/scenes/bracket/bracket_hero.gd")
const STG := preload("res://scripts/scenes/bracket/bracket_stage.gd")
const CER := preload("res://scripts/scenes/bracket/bracket_ceremony.gd")
const INFO := preload("res://scripts/scenes/bracket/bracket_info.gd")
const CD := preload("res://scripts/scenes/bracket/champion_data.gd")
const CW := preload("res://scripts/scenes/bracket/champion_wall.gd")

var H = null
var m = null
var now := 0


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.account_id = "acc-0-0"          # 我 = A 组 0 号 = 冠军杯 0 号签(冠军本人视角)
	H = SH.new()
	## 看门狗: 录像时间超过 4 分钟一定是卡住了(Movie Maker 会一直往文件里写空帧) ⇒ 退出
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("REC WATCHDOG")
		get_tree().quit(1))
	HERO._seen_reveal.clear()
	STG.wall_played.clear()
	STG.prep_dismissed.clear()
	CER.played.clear()
	CER.intro_played.clear()
	INFO.champ_waiting.clear()
	INFO.champ_fired.clear()
	await get_tree().process_frame
	var mode := OS.get_environment("REC_MODE")
	if mode == "ipad":
		await _seg_grid()
		await _seg_cup_live()
		await _seg_podium_static()
	elif mode == "group":
		## 小组赛这一段(10-31 改「桶内同一轮同时开播」之后录): 备战 → 两场同时开播(+ 全局小条)→ 看完回来红叉走线 → 名牌墙 → 备战屏 → 组冠军
		await _seg_group_prep()
		await _seg_group_live()
		await _seg_back_from_watch()
		await _seg_wall()
		await _seg_prep()
		await _seg_group_champion()
	elif mode != "full":
		## 默认 = 冠军杯这一段(10-31 小组赛开播规则在改: 小组开播 / 名牌墙 / 组冠军等改完再录 REC_MODE=full)
		await _seg_pre18()
		await _seg_grid()
		await _seg_cup_intro()
		await _seg_cup_live()
		await _seg_cup_champion()
		await _seg_champion_wall()
	else:
		await _seg_pre18()
		await _seg_group_prep()
		await _seg_group_live()
		await _seg_back_from_watch()
		await _seg_wall()
		await _seg_prep()
		await _seg_group_champion()
		await _seg_grid()
		await _seg_cup_intro()
		await _seg_cup_live()
		await _seg_cup_champion()
		await _seg_champion_wall()
	print("REC DONE")
	get_tree().quit(0)


# ── 小工具 ──
func _open(bucket: Dictionary, finals: Dictionary, week: Dictionary, t: int, cup: bool, chip: String = "") -> void:
	if m != null and is_instance_valid(m):
		m.queue_free()
		await get_tree().process_frame
	now = t
	P2C.now_override_ts = t
	H._stamp(bucket, t)
	H._stamp(finals, t)
	for b in week.get("buckets", []):
		H._stamp(b, t)
	if week.has("cup"):
		H._stamp(week["cup"], t)
	m = SCENE.new()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	m.enable_ceremony(true)
	m.defending_acc = "acc-2-0"
	if not week.is_empty():
		m.set_week(week)
	m.set_data(bucket, finals, t)
	m.pick_view(L.VIEW_FINALS if cup else L.VIEW_BUCKET)
	if chip != "":
		m.pick_chip(chip)


## 停 sec 秒(录像时间), 每过一秒把钟往前拨一秒 —— 倒计时真的在走。
func _hold(sec: float) -> void:
	var t0 := now
	var el := 0.0
	while el < sec:
		await get_tree().process_frame
		el += get_process_delta_time()
		var nt := t0 + int(el)
		if nt != now and m != null and is_instance_valid(m):
			now = nt
			m._now_override = nt
			P2C.now_override_ts = nt


## 把钟拨到 t 并重画(状态变了: 揭晓 / 开播)。
func _jump(t: int) -> void:
	now = t
	P2C.now_override_ts = t
	m._now_override = t
	m._rebuild()


func _week6(F: int) -> Array:
	var seq := {"v": 1, "until": F + 175, "p": {"1-0": [F, F + 130], "1-1": [F, F + 150]}}   # 小组赛同一轮同时开播(S 10-31)
	var wk: Array = [H._grp(0, 2, {"1-0": 0, "1-1": 1}, {"1-0": 1, "1-1": 0}, false, 0, {"revealed_at": F, "round_at": F + 175, "seq": seq})]
	for g in range(1, 6):
		wk.append(H._grp(g, 2, {"1-0": 1, "1-1": 0}, {"1-0": 0, "1-1": 1}, false, -1, {"revealed_at": F, "round_at": F + 175, "seq": seq}))
	return wk


# ── 段 ──
func _seg_pre18() -> void:
	await _open({"reason": "not_seated", "entered": 24}, {}, {}, SH.SUN + 17 * 3600 + 41 * 60, false)
	await _hold(4.5)


func _seg_group_prep() -> void:
	var t := SH.SUN + 18 * 3600 + 61
	var b: Dictionary = H._grp(0, 1, {}, {}, false, 0, {"round_at": SH.SUN + 18 * 3600})
	var wk: Array = [b]
	for g in range(1, 6):
		wk.append(H._grp(g, 1, {}, {}, false, -1, {"round_at": SH.SUN + 18 * 3600}))
	await _open(b, {}, {"buckets": wk}, t, false)
	await _hold(4.5)


func _seg_group_live() -> void:
	var F := SH.SUN + 18 * 3600 + 8 * 60
	var wk := _week6(F)
	await _open(wk[0], {}, {"buckets": wk}, F + 40, false)
	var fd = get_node_or_null("/root/FinalsDay")
	if fd != null:
		fd.test_host = m                    # 全局决赛日小条在场(停在对阵图留的停靠位)
		m._rebuild()
		fd.tick()
	await _hold(5.5)
	if fd != null:
		fd.test_host = null
		fd.tick()


func _seg_back_from_watch() -> void:
	## 看完第 1 场回来: 输家盖红叉 + 光点沿连线走到决赛格
	var F := SH.SUN + 18 * 3600 + 8 * 60
	var wk := _week6(F)
	HERO._seen_reveal.clear()
	await _open(wk[0], {}, {"buckets": wk}, F + 135, false)
	await _hold(3.8)


func _seg_wall() -> void:
	var F := SH.SUN + 18 * 3600 + 8 * 60
	var wk := _week6(F)
	await _open(wk[0], {}, {"buckets": wk}, F + 156, false)
	await _hold(6.4)


func _seg_prep() -> void:
	var F := SH.SUN + 18 * 3600 + 8 * 60
	var wk := _week6(F)
	await _open(wk[0], {}, {"buckets": wk}, F + 200, false)
	await _hold(4.5)


func _seg_group_champion() -> void:
	## 组决赛开播中 → 揭晓那一刻 ⇒ ChampionShow 组冠军版(我夺冠)
	var G := SH.SUN + 18 * 3600 + 20 * 60
	var seq := {"v": 1, "until": G + 155, "p": {"1-0": [G - 700, G - 570], "1-1": [G - 545, G - 410], "2-0": [G, G + 130]}}
	var b: Dictionary = H._grp(0, 2, {"1-0": 0, "1-1": 1, "2-0": 0}, {"1-0": 1, "1-1": 0, "2-0": 1}, true, 0, {"revealed_at": G, "seq": seq})
	var wk: Array = [b] + H._closed_groups().slice(1)
	await _open(b, {}, {"buckets": wk}, G + 100, false)
	await _hold(2.5)
	_jump(G + 140)
	await get_tree().process_frame
	var show = m._ceremony.last_show
	var dur := 10.0
	if show != null and is_instance_valid(show) and show.has_method("total_length"):
		dur = float(show.total_length())
	await _hold(dur + 2.0)
	if show != null and is_instance_valid(show):
		show.close()
	await _hold(1.5)


func _seg_grid() -> void:
	var F := SH.SUN + 18 * 3600 + 8 * 60
	var seq := {"v": 1, "until": F + 175, "p": {"1-0": [F, F + 130], "1-1": [F, F + 150]}}   # 小组赛同一轮同时开播(S 10-31)
	var b3: Dictionary = H._grp(0, 2, {"1-0": 0, "1-1": 1}, {"1-0": 1, "1-1": 0}, false, 0, {"revealed_at": F, "round_at": F + 175, "seq": seq})
	var wk: Array = [b3]
	wk.append(H._grp(1, 2, {"1-0": 1, "1-1": 0}, {"1-0": 0, "1-1": 1}, false, -1, {"revealed_at": F, "round_at": F + 175, "seq": seq}))
	wk.append(H._grp(2, 2, {"1-0": 0, "1-1": 0, "2-0": 1}, {"1-0": 1, "1-1": 0, "2-0": 1}, true, -1))
	wk.append(H._grp(3, 2, {"1-0": 0, "1-1": 1}, {}, false, -1, {"round_at": F + 20}))
	wk.append(H._grp(4, 2, {"1-0": 1, "1-1": 1}, {"1-0": 1, "1-1": 1}, false, -1, {"revealed_at": F, "round_at": F + 175, "seq": seq}))
	wk.append(H._grp(5, 1, {}, {}, false, -1, {"round_at": F - 400}))
	await _open(b3, {}, {"buckets": wk}, F + 40, false, "all")
	await _hold(4.5)


func _seg_cup_intro() -> void:
	## 冠军杯 20:00 成表、第 1 轮还在备战 ⇒ 组冠军依次亮相(上届冠军标「卫冕」)
	var C0 := SH.SUN + 20 * 3600
	var cup: Dictionary = H._cup(1, {}, {}, false, 0, {"round_at": C0})
	var grp: Array = H._closed_groups()
	await _open(grp[0], cup, H._week(grp, cup), C0 + 20, true)
	var it = m._ceremony.last_intro
	var dur := 8.0
	if it != null and is_instance_valid(it) and it.has_method("total_length"):
		dur = float(it.total_length())
	await _hold(dur + 1.0)


func _seg_cup_live() -> void:
	var C := SH.SUN + 20 * 3600 + 2 * 60
	var cseq := {"v": 1, "until": C + 320, "p": {"1-1": [C, C + 135], "1-3": [C + 160, C + 295]}}
	var cup: Dictionary = H._cup(2, {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0}, {"1-1": 1, "1-3": 0}, false, 0,
		{"revealed_at": C, "round_at": C + 320, "seq": cseq})
	var grp: Array = H._closed_groups()
	CER.intro_played[SH.WEEK] = true          # 开场亮相已在上一段演过(短版也不重演)
	await _open(grp[0], cup, H._week(grp, cup), C + 50, true)
	await _hold(5.5)


func _cup_closed(extra: Dictionary = {}) -> Dictionary:
	return H._cup(3, {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0, "2-0": 0, "2-1": 1, "3-0": 0},
		{"1-1": 1, "1-3": 0, "2-0": 1, "2-1": 0, "3-0": 1}, true, 0, extra)


func _seg_cup_champion() -> void:
	## 决赛开播中 → 揭晓那一刻 ⇒ ChampionShow 冠军杯版(冠军本人: 领奖)→ 关掉 ⇒ 领奖台收盘
	var t0 := SH.SUN + 20 * 3600 + 40 * 60
	var cup: Dictionary = _cup_closed({"revealed_at": t0 - 30})
	var grp: Array = H._closed_groups()
	await _open(grp[0], cup, H._week(grp, cup), t0, true)
	await _hold(2.5)
	_jump(t0 + 600)
	await get_tree().process_frame
	var show = m._ceremony.last_show
	if show != null and is_instance_valid(show):
		await _hold(float(show.total_length()) + 1.5)
		## 领取奖励: 一件一页, 每页演完点「下一个 / 完成」
		show._on_btn("BtnClaim")
		await get_tree().process_frame
		var rw: Node = null
		for k in m.get_children():
			if k.has_signal("coins_landed"):
				rw = k
		var guard := 0
		while rw != null and is_instance_valid(rw) and guard < 6:
			var pg := int(rw.get("page"))
			await _hold(float(rw.anim_of(pg)) + 1.2)
			if is_instance_valid(rw):
				rw._on_next()
			guard += 1
		await _hold(1.2)
		if is_instance_valid(show):
			show._on_btn("BtnClose")
	## 领奖台收盘(仪式关掉之后的对阵图)
	await _hold(4.5)


func _seg_podium_static() -> void:
	var grp: Array = H._closed_groups()
	var cup: Dictionary = _cup_closed()
	await _open(grp[0], cup, H._week(grp, cup), SH.SUN + 21 * 3600, true)
	await _hold(5.0)


func _seg_champion_wall() -> void:
	## 冠军墙(往届): 本届 + 造两届往届(换冠军名)
	var grp: Array = H._closed_groups()
	var cup: Dictionary = _cup_closed()
	var es: Array = [CD.wall_entry(SH.WEEK, H._week(grp, cup))]
	for k in [1, 2]:
		var c2: Dictionary = cup.duplicate(true)
		var nm: Array = c2["names"]
		var rot: Array = nm.slice(k) + nm.slice(0, k)
		c2["names"] = rot
		es.append(CD.wall_entry(SH.WEEK - k * 7 * 86400, H._week(grp, c2)))
	CW.open(m, {"entries": es})
	await _hold(5.0)
