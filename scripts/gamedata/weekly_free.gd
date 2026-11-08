class_name WeeklyFree
extends RefCounted
## 每号每周的限免龟（方案书 docs/plans/20261105c-主站对接偷袭.md §4.2；20261107-龟战主站对接.md §4.3 / §4.9）。
##
## 规则原文：每号每周一个固定的 28 只排序（种子 = 账号 ID + 周号，客户端与服务器同一个纯函数），跳过已拥有、取前 7 只；
##   周中新得到一只限免龟 ⇒ 只换掉那一只。换周时刻 = 周一 00:00 UTC（周锚点 = 那一刻的 unix 秒，= GameState.week_anchor_ts
##   = 服务端 season_week）。
##
## ★纯函数：不读钟、不读存档、不用引擎随机。排序键 = FNV-1a 32 位（"账号|周锚点|龟 id" 的 UTF-8 字节），
##   同键（概率约 1e-7）再按龟 id 逐码点比。同一个算法在 SQL 里有一份（迁移 20261109b `weekly_free_ids`），
##   门禁 verify_weekly_free 拿同一组输入比两边逐只相同。
## ★「周中新得到一只只换那一只」不用另写：排序每周固定，已拥有的跳过 ⇒ 新拥有的那只让位给排序里的下一只，其余 6 只不动。
## 用的人：选龟页（只显示拥有 ∪ 限免）、裁判开算前校验（`RefereeJob.validate`）、陪练号选龟（sim_driver）、
##   兜底机器人（`Backend.make_bot`）。

## 28 只龟（= data/pets.json 的顺序；门禁核对它与 DataRegistry.launch_pets 一致、与 SQL 那份一致）。
const ALL: Array[String] = ["basic", "stone", "bamboo", "angel", "ice", "ninja", "two_head", "ghost", "diamond",
	"fortune", "dice", "rainbow", "gambler", "hunter", "pirate", "candy", "bubble", "line", "lightning", "phoenix",
	"lava", "cyber", "crystal", "chest", "space", "hiding", "headless", "shell"]
## 每周限免几只
const COUNT := 7

const _FNV_OFFSET := 2166136261
const _FNV_PRIME := 16777619


## FNV-1a 32 位（UTF-8 字节）。h < 2^32、乘数 < 2^25 ⇒ 积 < 2^57，int64 不溢出。
static func fnv1a32(s: String) -> int:
	var h: int = _FNV_OFFSET
	for b in s.to_utf8_buffer():
		h = ((h ^ int(b)) * _FNV_PRIME) & 0xFFFFFFFF
	return h


## 这个号这一周的 28 只排序（不看拥有）。
static func order(account_id: String, week_anchor: int) -> Array:
	var keyed: Array = []
	for pid in ALL:
		keyed.append([fnv1a32("%s|%d|%s" % [account_id, week_anchor, pid]), pid])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and str(a[1]) < str(b[1])))
	var out: Array = []
	for k in keyed:
		out.append(str(k[1]))
	return out


## 本周限免：排序里跳过已拥有的，取前 COUNT 只（按排序先后）。
static func free_ids(account_id: String, week_anchor: int, owned: Array) -> Array:
	var own := _owned_set(owned)
	var out: Array = []
	for pid in order(account_id, week_anchor):
		if own.has(pid):
			continue
		out.append(pid)
		if out.size() >= COUNT:
			break
	return out


## 能上场的：拥有 ∪ 本周限免（按 ALL 的顺序；拥有里不在 28 只之内的不算）。
static func allowed_ids(account_id: String, week_anchor: int, owned: Array) -> Array:
	var own := _owned_set(owned)
	var fr := free_ids(account_id, week_anchor, owned)
	var out: Array = []
	for pid in ALL:
		if own.has(pid) or fr.has(pid):
			out.append(pid)
	return out


## ids 是不是全在「拥有 ∪ 限免」里（空 ids ⇒ true）。
static func all_allowed(account_id: String, week_anchor: int, owned: Array, ids: Array) -> bool:
	var ok := allowed_ids(account_id, week_anchor, owned)
	for p in ids:
		if not ok.has(str(p)):
			return false
	return true


static func _owned_set(owned: Array) -> Dictionary:
	var s := {}
	for p in owned:
		s[str(p)] = true
	return s
