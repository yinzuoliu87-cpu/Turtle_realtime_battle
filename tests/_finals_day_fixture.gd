extends RefCounted
## 周日决赛日的「服务端此刻会回什么」(门禁 + 实拍共用; 不是测试本身)。
## 照服务端 20261101 的开播排法造数据(finals_advance + finals_premiere_plan):
##   第 r 轮 round_at → 3 分钟备战 → round_at + 480 翻面 → 小组赛: 本轮所有场同时开播(用户 10-31 纠正); 冠军杯赛: 一场接一场
##   (每场 = 210 秒 + 场间 25 秒)→ 本轮全部播完 + 25 秒 = 下一轮 round_at。冠军杯赛 FINALS_START_HOUR_UTC 开赛(10-31 起 19:00), 6 位组冠军进 8 签(2 个轮空)。
## 形状 = SupabaseNet._bucket_from 的产物(size / round / done / names / tags / accs / me / closed / left / recv_at / bucket /
##   round_at / srv_now / revealed_at / seq)。`now` = 服务端此刻; 收包时刻 = now(时间差为 0)。

const _B := preload("res://scripts/gamedata/bracket.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

const ROUND_SEC := 480
const SHOP_SEC := 180
const PLAY := 210            # 一场 = ceil(步数/60) + 开场 30 秒
const GAP := 25
## ★「吃货一枚」坐第 3 组 2 号种子: 4 人表座次 [0,3,1,2] ⇒ 2 号种子在半决赛第 2 场(1-1)下半区, 开播排在第 1 场之后 ⇒
##   有「30 秒后开播」那一段可拍(第 1 场 = 翻面那一刻开播, 没有提前量)。默认我拿下小组(1-1 / 2-0 都是下半区赢);
##   冠军杯赛 8 签座次 [0,7,3,4,1,6,2,5] ⇒ 我(2 号签)第 1 轮第 4 场、半决赛输给 1 号签(第 2 组冠军), 冠军 = 0 号签(第 1 组冠军)。
const NAMES := [
	["小辉同学", "afei23", "huihui", "阿笨"],
	["头发多多", "ykx1314", "momo酱", "风起"],
	["老王不在", "Kiki", "吃货一枚", "大眼龟"],
	["nana", "一只鹅", "Leo", "八宝粥"],
	["阿土", "Mint", "龟仙人", "七七"],
	["Rex", "小鱼干", "米粒", "Coco"],
]
const MY_GROUP := 2
const MY_SEED := 2

var mon := 0
## 谁赢(组号 → {"r-m": side}); 没写的一律上半区(0)赢。
var group_wins: Dictionary = {}
var cup_wins: Dictionary = {}
var me_in := true            # 我是不是参赛者(false = 观众: 所有 me = -1)


func _init(week_anchor: int) -> void:
	mon = week_anchor
	group_wins[MY_GROUP] = {"1-1": 1, "2-0": 1}


func sun() -> int:
	return mon + 6 * 86400


func seat() -> int:
	return sun() + 18 * 3600


func cup_start() -> int:
	return sun() + int(_P2.FINALS_START_HOUR_UTC) * 3600


## 一张图在 start 开赛时的整条时间线: [{"round_at", "flip", "slots": {"r-m": [开播, 揭晓]}, "until"}, ...](每轮一项)。
## `parallel` = 小组赛(用户 10-31 纠正: 各组并行、组内同一轮所有场同时开播, 一轮播完才开下一轮备战);
##   冠军杯赛 = false(全服一路, 一场接一场)。
func timeline(n: int, start: int, wins: Dictionary, parallel: bool = false) -> Array:
	var out: Array = []
	var ra := start
	var done := {}
	for r in range(1, _B.rounds_for(n) + 1):
		var flip := ra + ROUND_SEC
		var slots := {}
		var t := flip
		for m in range(_B.matches_in_round(n, r)):
			var a := _B.occupant_seed(r, m, 0, n, done)
			var z := _B.occupant_seed(r, m, 1, n, done)
			var k := "%d-%d" % [r, m]
			if a == _B.OCC_BYE or z == _B.OCC_BYE:
				continue
			if parallel:
				slots[k] = [flip, flip + PLAY]
				t = flip + PLAY + GAP
			else:
				slots[k] = [t, t + PLAY]
				t += PLAY + GAP
			done[k] = int(wins.get(k, 0))
		## 轮空那几场不在档期、但 done 里也不记(occupant_seed 自己推)
		out.append({"round_at": ra, "flip": flip, "slots": slots, "until": t})
		ra = t
	return out


## 服务端此刻会给的那一张(还没开赛 ⇒ {})。
func bucket(n: int, bk: int, names: Array, me: int, start: int, wins: Dictionary, now: int, ids: Array = []) -> Dictionary:
	if now < start:
		return {}
	var tl := timeline(n, start, wins, bk != int(_P2.FINALS_CUP_BUCKET))
	var rnd := 1
	var closed := false
	var done := {}
	var scores := {}
	var p := {}
	var until := 0
	var revealed := 0
	for i in range(tl.size()):
		var it: Dictionary = tl[i]
		if now >= int(it["flip"]):
			for k in (it["slots"] as Dictionary):
				done[k] = int(wins.get(k, 0))
				p[k] = it["slots"][k]
				## 比分代码(败方赢了几路: 0 = 2:0 / 1 = 2:1), 与 done 同一道锁; 轮 + 场为偶数的打满三路
				scores[k] = 1 if (int(str(k).get_slice("-", 0)) + int(str(k).get_slice("-", 1))) % 2 == 0 else 0
			until = int(it["until"])
			revealed = int(it["flip"])
			if i + 1 < tl.size():
				rnd = i + 2
			else:
				closed = true
	var cur: Dictionary = tl[mini(rnd, tl.size()) - 1]
	var ra := int(cur["round_at"])
	var accs: Array = []
	var tags: Array = []
	for i in range(n):
		## 冠军杯赛的人就是各组冠军: 账号 / #ID 与他在组里那一份相同(服务端同一个 account_id)
		var gi: Array = ids[i] if i < ids.size() else [bk, i]
		accs.append("acc-%d-%d" % [int(gi[0]), int(gi[1])])
		tags.append("#T%d%02d" % [int(gi[0]), int(gi[1])])
	var left := (ra + ROUND_SEC - now) if not closed else -1
	var b := {"size": n, "round": rnd, "done": done, "scores": scores, "names": names.duplicate(), "tags": tags, "accs": accs,
		"me": me, "closed": closed, "left": maxi(0, left) if left >= 0 else -1, "recv_at": now, "bucket": bk,
		"round_at": ra, "srv_now": now, "revealed_at": revealed, "seq": null}
	if not p.is_empty():
		b["seq"] = {"v": 1, "until": until, "p": p}
	return b


## 各组(6 组 × 4 人)。
func groups(now: int) -> Array:
	var out: Array = []
	for g in range(NAMES.size()):
		var me := MY_SEED if (me_in and g == MY_GROUP) else -1
		var b := bucket(4, g, NAMES[g], me, seat(), group_wins.get(g, {}), now)
		if not b.is_empty():
			out.append(b)
	return out


## 某组的冠军名字(按全部打完算)。
func group_champ(g: int) -> String:
	return str(NAMES[g][group_champ_seed(g)])


func group_champ_seed(g: int) -> int:
	var b := bucket(4, g, NAMES[g], -1, seat(), group_wins.get(g, {}), seat() + 86400)
	return _B.champion_seed(4, b["done"])


## 冠军杯赛(6 位组冠军进 8 签); 开赛之前 ⇒ {}。
func cup(now: int) -> Dictionary:
	var names: Array = []
	var ids: Array = []
	var me := -1
	for g in range(NAMES.size()):
		var nm := group_champ(g)
		names.append(nm)
		ids.append([g, group_champ_seed(g)])
		if me_in and g == MY_GROUP and nm == str(NAMES[MY_GROUP][MY_SEED]):
			me = g
	return bucket(6, int(_P2.FINALS_CUP_BUCKET), names, me, cup_start(), cup_wins, now, ids)


func my_group(now: int) -> Dictionary:
	for b in groups(now):
		if int(b.get("bucket", -1)) == MY_GROUP:
			return b if me_in else {}
	return {}


## {"group", "cup", "groups"}(finals_day_feed.override / MenuFinalsDay.feed_override 的形状)。
func feeds(now: int) -> Dictionary:
	return {"group": my_group(now), "cup": cup(now), "groups": groups(now)}


## 本周晋级名单(服务端 finals_qualified_list 回包解析后的形状): 6 组 × 4 人, 按闯关战绩排(4 胜 0~2 负)。
func qualified() -> Dictionary:
	var out: Array = []
	for g in range(NAMES.size()):
		for i in range(4):
			out.append({"name": str(NAMES[g][i]), "tag": "#T%d%02d" % [g, i], "avatar": "", "gw": 4,
				"gl": (g + i) % 3, "me": me_in and g == MY_GROUP and i == MY_SEED})
	out.sort_custom(func(a, b): return int(a["gl"]) < int(b["gl"]))
	return {"n": out.size(), "list": out, "seated": false}
