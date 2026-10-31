extends Node
## _shot_bracket_b.gd —— 周日对阵图 / 8 强图整页重做实拍(给人看的, 不是门禁 · 方案书 20261031c §4 B 行)
## 跑法(不能 --headless; 窗口放右屏; 必须静音):
##   WINDOW=1 bash godot-quiet.sh --resolution 1560x720 --position 2000,80 res://tests/_shot_bracket_b.tscn
## 产物: C:/tmp/sunday_redo/B/<状态>-<宽>x<高>.png。SHOT_ONLY=<序号前缀> 只拍那一张。
## ★数据全是造的(六组 × 4 人 + 冠军杯 6 人 8 签), 时刻全钉死(`set_data(..., now)`), 开播档期照 20261101 迁移的 seq 形状。

const SCENE := preload("res://scripts/scenes/BracketMapScene.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const OUT := "C:/tmp/sunday_redo/B"
## 2026-11-01 周日的锚点(周一 2026-10-26 00:00 UTC = 1792972800)。时刻都按 UTC 小时算。
const WEEK := 1792972800
const SUN := WEEK + 6 * 86400
const AV := ["candy", "pirate", "bubble", "ninja", "stone", "angel", "bamboo", "basic"]
const GN := [["吃货一枚", "小辉同学", "afei23", "huihui"], ["jyz11", "阿丽呀", "max5452", "阿芳"],
	["头发多多", "ykx1314", "kris520", "海盗龟王"], ["石头统领", "彩虹大师", "fish31", "haohao"],
	["龟龟冲鸭", "Leo_88", "南风", "糖豆"], ["竹子先生", "lily99", "夜猫子", "不吃香菜"]]


func _grp(g: int, round_: int, done: Dictionary, scores: Dictionary, closed: bool, me: int, extra: Dictionary = {}) -> Dictionary:
	var accs: Array = []
	var tags: Array = []
	var avs: Array = []
	for i in range(4):
		accs.append("acc-%d-%d" % [g, i])
		tags.append(P2C.player_tag("acc-%d-%d" % [g, i]))
		avs.append(AV[(g * 3 + i) % AV.size()] if (g + i) % 4 != 3 else "")
	var d := {"bucket": g, "size": 4, "round": round_, "me": me, "names": GN[g], "tags": tags, "accs": accs, "avatars": avs,
		"done": done, "scores": scores, "closed": closed, "revealed_at": 0, "round_at": 0}
	d.merge(extra, true)
	return d


func _week(buckets: Array, cup: Dictionary = {}) -> Dictionary:
	var w := {"buckets": buckets}
	if not cup.is_empty():
		w["cup"] = cup
	return w


## 冠军杯 6 人 8 签: 种子 0..5 = 第 1..6 组冠军(第 1 组冠军 = 吃货一枚 = 我)
func _cup(round_: int, done: Dictionary, scores: Dictionary, closed: bool, me: int, extra: Dictionary = {}) -> Dictionary:
	var names: Array = []
	var accs: Array = []
	var tags: Array = []
	var avs: Array = []
	for g in range(6):
		names.append(GN[g][0])
		accs.append("acc-%d-0" % g)
		tags.append(P2C.player_tag("acc-%d-0" % g))
		avs.append(AV[(g * 3) % AV.size()] if g % 4 != 3 else "")
	var d := {"bucket": P2C.FINALS_CUP_BUCKET, "size": 6, "round": round_, "me": me, "names": names, "tags": tags, "accs": accs,
		"avatars": avs, "done": done, "scores": scores, "closed": closed, "revealed_at": 0, "round_at": 0}
	d.merge(extra, true)
	return d


## 六个组: 组冠军都是 0 号(冠军杯的种子来源)
func _closed_groups() -> Array:
	var out: Array = []
	for g in range(6):
		out.append(_grp(g, 2, {"1-0": 0, "1-1": 1, "2-0": 0}, {"1-0": 1, "1-1": 0, "2-0": 0}, true, 0 if g == 0 else -1))
	return out


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	var only := OS.get_environment("SHOT_ONLY")
	var F := SUN + 18 * 3600 + 8 * 60          # 第 1 轮翻面时刻(18:08)
	## ① 18:00 前: 大倒计时 + 已报名人数
	if only == "" or only == "1":
		await _shot("1_18点前", {"reason": "not_seated", "entered": 24}, {}, {}, SUN + 17 * 3600 + 41 * 60, false, 60)
	## ② 小组备战中(18:01, 第 1 轮 3 分钟备战)
	if only == "" or only == "2":
		var b2 := _grp(0, 1, {}, {}, false, 0, {"round_at": SUN + 18 * 3600, "srv_now": SUN + 18 * 3600 + 61, "recv_at": 0})
		var wk2: Array = [b2]
		for g in range(1, 6):
			wk2.append(_grp(g, 1, {}, {}, false, -1, {"round_at": SUN + 18 * 3600}))
		await _shot("2_小组备战中", b2, {}, _week(wk2), SUN + 18 * 3600 + 61, false, 110)
	## ③ 小组开播中: 第 1 场开播、第 2 场即将开播(一场接一场)
	var seq := {"v": 1, "until": F + 175, "p": {"1-0": [F, F + 130], "1-1": [F, F + 150]}}   # 小组赛同一轮同时开播(S 10-31)
	var b3 := _grp(0, 2, {"1-0": 0, "1-1": 1}, {"1-0": 1, "1-1": 0}, false, 0,
		{"revealed_at": F, "round_at": F + 175, "seq": seq})
	var wk3: Array = [b3]
	for g in range(1, 6):
		wk3.append(_grp(g, 2, {"1-0": 1, "1-1": 0}, {"1-0": 0, "1-1": 1}, false, -1,
			{"revealed_at": F, "round_at": F + 175, "seq": seq}))
	if only == "" or only == "3":
		await _shot("3_小组开播中", b3, {}, _week(wk3), F + 40, false, 110)
	## ④ 本轮名牌墙(第 2 场揭晓后、下一轮备战前): 拍墙放到一半(打叉之后、揭晓下一轮时)
	if only == "" or only == "4":
		await _shot("4_本轮名牌墙", b3, {}, _week(wk3), F + 156, false, 200)
		await _shot("4b_名牌墙之后备战屏", b3, {}, _week(wk3), F + 200, false, 140)
	## ⑤ 组决赛后组冠军(我那组, 我夺冠)
	if only == "" or only == "5":
		var b5 := _grp(0, 2, {"1-0": 0, "1-1": 1, "2-0": 0}, {"1-0": 1, "1-1": 0, "2-0": 1}, true, 0)
		await _shot("5_组冠军", b5, {}, _week([b5] + _closed_groups().slice(1)), SUN + 18 * 3600 + 40 * 60, false, 110)
	## ⑥ 全部组宫格(各组状态不一)
	if only == "" or only == "6":
		var wk6: Array = [b3]
		wk6.append(_grp(1, 2, {"1-0": 1, "1-1": 0}, {"1-0": 0, "1-1": 1}, false, -1, {"revealed_at": F, "round_at": F + 175, "seq": seq}))
		wk6.append(_grp(2, 2, {"1-0": 0, "1-1": 0, "2-0": 1}, {"1-0": 1, "1-1": 0, "2-0": 1}, true, -1))
		wk6.append(_grp(3, 2, {"1-0": 0, "1-1": 1}, {}, false, -1, {"round_at": F + 20}))
		wk6.append(_grp(4, 2, {"1-0": 1, "1-1": 1}, {"1-0": 1, "1-1": 1}, false, -1, {"revealed_at": F, "round_at": F + 175, "seq": seq}))
		wk6.append(_grp(5, 1, {}, {}, false, -1, {"round_at": F - 400}))
		await _shot("6_全部组宫格", b3, {}, _week(wk6), F + 40, false, 110, "all")
	## ⑦ 冠军杯 8 强(含轮空)开播中: 6 人 8 签, 1/4 决赛第 1 场开播、第 2 场即将开播
	var C := SUN + 20 * 3600 + 2 * 60
	var cseq := {"v": 1, "until": C + 320, "p": {"1-1": [C, C + 135], "1-3": [C + 160, C + 295]}}
	var cup7 := _cup(2, {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0}, {"1-1": 1, "1-3": 0}, false, 0,
		{"revealed_at": C, "round_at": C + 320, "seq": cseq})
	if only == "" or only == "7":
		await _shot("7_冠军杯8强开播中", _closed_groups()[0], cup7, _week(_closed_groups(), cup7), C + 50, true, 110)
	## ⑧ 冠军杯收盘: 领奖台 + 滚动全部参赛者(收盘只讲结果, 不预告下一场比赛)
	if only == "" or only == "8":
		var cup8 := _cup(3, {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0, "2-0": 0, "2-1": 1, "3-0": 0},
			{"1-1": 1, "1-3": 0, "2-0": 1, "2-1": 0, "3-0": 1}, true, 0)
		await _shot("8_冠军杯收盘", _closed_groups()[0], cup8, _week(_closed_groups(), cup8), SUN + 21 * 3600, true, 150)
	## ⑨ 冠军杯备战(半决赛 3 分钟备战屏)
	if only == "" or only == "9":
		var cup9 := _cup(2, {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0}, {"1-1": 1, "1-3": 0}, false, 0,
			{"revealed_at": C, "round_at": C + 320, "seq": cseq})
		await _shot("9_冠军杯备战", _closed_groups()[0], cup9, _week(_closed_groups(), cup9), C + 380, true, 140)
	## ⑩ 对局卡(组决赛, 我赢): 点开那一格
	if only == "" or only == "10":
		var b10 := _grp(0, 2, {"1-0": 0, "1-1": 1, "2-0": 0}, {"1-0": 1, "1-1": 0, "2-0": 1}, true, 0)
		await _shot("10_对局卡", b10, {}, _week([b10] + _closed_groups().slice(1)), SUN + 18 * 3600 + 40 * 60, false, 40, "", Vector2i(1, 1))
	print("SHOTS DONE")
	get_tree().quit(0)


var _last: Node = null


func _stamp(b: Dictionary, now: int) -> void:
	if not b.is_empty() and b.has("size"):
		b["srv_now"] = now
		b["recv_at"] = now


func _shot(tag: String, bucket: Dictionary, finals: Dictionary, week: Dictionary, now: int, cup: bool, frames: int,
		chip: String = "", popup: Vector2i = Vector2i(-1, -1)) -> void:
	if _last != null:
		_last.queue_free()
		await get_tree().process_frame
	var m = SCENE.new()
	get_tree().root.add_child(m)
	_last = m
	await get_tree().process_frame
	_stamp(bucket, now)
	_stamp(finals, now)
	for b in week.get("buckets", []):
		_stamp(b, now)
	if week.has("cup"):
		_stamp(week["cup"], now)
	if not week.is_empty():
		m.set_week(week)
	m.defending_acc = "acc-2-0"          # 上周冠军(⑦「卫冕」: 客户端现在拿不到, 这里喂给截图看样子)
	m.set_data(bucket, finals, now)
	m.pick_view(L.VIEW_FINALS if cup else L.VIEW_BUCKET)
	if chip != "":
		m.pick_chip(chip)
	if popup.x >= 1:
		await get_tree().create_timer(1.0).timeout
		m._open_popup(popup.x, popup.y)
	## SHOT_BAR=1: 把 M 的全局决赛日小条(FinalsDay)也叫出来, 看它停在停靠位
	var fd = get_node_or_null("/root/FinalsDay")
	if OS.get_environment("SHOT_BAR") == "1" and fd != null:
		P2C.now_override_ts = now
		fd.test_host = m
		m._rebuild()
		fd.tick()
		tag += "_小条"
	## 等动画落位按真实时间(窗口帧率不定: 150 帧在高帧率下只有半秒, 领奖台头像还没淡入)
	await get_tree().create_timer(float(frames) / 60.0).timeout
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var p := "%s/%s-%dx%d.png" % [OUT, tag, img.get_width(), img.get_height()]
	img.save_png(p)
	print("SHOT ", p)
