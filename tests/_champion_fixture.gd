extends RefCounted
## _champion_fixture.gd —— 冠军收盘门禁 / 截图台共用的假数据(不进产品)。
## 形状 = `SupabaseNet.parse_finals_week()` 的回包(组 + 杯, 每张 = `_bucket_from` 那一份)+ `matches` 行。
## 6 组 × 4 人 = 24 人; 每组 0 号种子夺冠(先胜 3 号、再胜 1 号);
## 冠军杯 6 签(8 坑): 0 号、1 号轮空; 4 号(E 组冠军)先胜 3 号 → 再胜 0 号 → 决赛胜 2 号(C 组冠军)夺冠。

const P2C := preload("res://scripts/gamedata/phase2_config.gd")

const WEEK := 1792972800        # 2026-10-26 周一 ⇒ 周日 11 月 1 日, 第 4 届
const LETTERS := "ABCDEF"
const NAMES := [["深海小龟王", "珊瑚", "潮汐", "海草"], ["浪花", "蓝鲸", "灯笼鱼", "沙丁"],
	["火山岩", "暗流", "贝壳", "海星"], ["北极光", "冰川", "小企鹅", "雪球"],
	["凤凰之羽", "海风", "礁石", "海葵"], ["夜行者", "旋涡", "珍珠", "银鱼"]]
const LEADERS := [["phoenix", "lava", "shell"], ["ice", "ninja", "ghost"], ["crystal", "space", "cyber"],
	["angel", "diamond", "fortune"], ["hiding", "headless", "rainbow"], ["pirate", "candy", "bubble"]]


static func acc(g: int, s: int) -> String:
	return "acc-%s%d" % [LETTERS[g], s]


static func group(g: int) -> Dictionary:
	var names: Array = []
	var tags: Array = []
	var accs: Array = []
	for s in range(4):
		names.append(NAMES[g][s])
		accs.append(acc(g, s))
		tags.append(P2C.player_tag(acc(g, s)))
	## 4 坑座次 [0,3,1,2]: 1-0 = 0 对 3, 1-1 = 1 对 2; 组决赛 0 对 1
	return {"bucket": g, "size": 4, "round": 3, "closed": true, "names": names, "tags": tags, "accs": accs, "me": -1,
		"done": {"1-0": 0, "1-1": 0, "2-0": 0}, "scores": {"1-0": 0, "1-1": 1, "2-0": 1}}


static func cup() -> Dictionary:
	var names: Array = []
	var tags: Array = []
	var accs: Array = []
	for g in range(6):
		names.append(NAMES[g][0])
		accs.append(acc(g, 0))
		tags.append(P2C.player_tag(acc(g, 0)))
	## 8 坑座次 [0,7,3,4,1,6,2,5]: 1-0 = 0 对 空, 1-1 = 3 对 4, 1-2 = 1 对 空, 1-3 = 2 对 5
	return {"bucket": 99, "size": 6, "round": 4, "closed": true, "names": names, "tags": tags, "accs": accs, "me": -1,
		"done": {"1-1": 1, "1-3": 0, "2-0": 1, "2-1": 1, "3-0": 0}, "scores": {"1-1": 0, "1-3": 1, "2-0": 1, "2-1": 0, "3-0": 1}}


static func view(with_cup: bool = true) -> Dictionary:
	var bs: Array = []
	for g in range(6):
		bs.append(group(g))
	var v := {"buckets": bs, "srv_now": WEEK + 6 * 86400 + 20 * 3600}
	if with_cup:
		v["cup"] = cup()
	return v


## 每一场一行 matches(左 = 座次靠前那一侧)。steps 各不相同: 最快那一场 = C 组半决赛第 2 场(1:12)。
static func rows() -> Array:
	var out: Array = []
	for g in range(6):
		for m in [[1, 0, 0, 3], [1, 1, 1, 2], [2, 0, 0, 1]]:
			out.append(_row(g, int(m[0]), int(m[1]), acc(g, int(m[2])), acc(g, int(m[3])), NAMES[g][int(m[2])], NAMES[g][int(m[3])],
				LEADERS[g] if int(m[2]) == 0 else ["basic", "stone", "bamboo"], ["basic", "stone", "bamboo"],
				(90 + g * 7 + int(m[1]) * 11) * 60 if not (g == 2 and int(m[1]) == 1 and int(m[0]) == 1) else 72 * 60))
	## 杯: (r, m, 左组, 右组, 左赢?)
	for x in [[1, 1, 3, 4, false], [1, 3, 2, 5, true], [2, 0, 0, 4, false], [2, 1, 1, 2, false], [3, 0, 4, 2, true]]:
		var lg := int(x[2])
		var rg := int(x[3])
		out.append(_row(99, int(x[0]), int(x[1]), acc(lg, 0), acc(rg, 0), NAMES[lg][0], NAMES[rg][0], LEADERS[lg], LEADERS[rg],
			150 * 60 + int(x[1]) * 600, bool(x[4])))
	return out


static func _row(b: int, r: int, m: int, la: String, ra: String, ln: String, rn: String, lu: Array, ru: Array,
		steps: int, won: bool = true) -> Dictionary:
	return {"match_id": "00000000-0000-4000-8000-%012d" % (b * 100 + r * 10 + m),
		"result": {"won": won, "steps": steps, "fb": b, "fr": r, "fm": m},
		"lp": {"name": ln, "tag": P2C.player_tag(la), "avatar": str(lu[0])},
		"rp": {"name": rn, "tag": P2C.player_tag(ra), "avatar": str(ru[0])},
		"la": lu, "ra": ru}
