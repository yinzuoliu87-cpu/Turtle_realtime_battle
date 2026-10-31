extends RefCounted
## 周日决赛日的数据(2026-10-31 方案书 20261031c 块 M): 本周各组 / 冠军杯赛 / 我那一组 + 上周冠军 + 头像。
## ★只读 supabase.gd 已有的读接口(finals_view / finals_week_view / 赛况板), 不往 supabase.gd 里加东西(它快到 3000 行)。
## ★本周那几份走全局缓存(对阵图读同一份, 不另存); 上周冠军走只回调不落缓存的 `fetch_finals_week_cb`
##   (写进全局缓存会让对阵图拿到上周的组 —— supabase.gd 那条注释写过)。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _SB := preload("res://scripts/net/supabase.gd")
const _M := preload("res://scripts/ui/finals_day_model.gd")
const _Board := preload("res://scripts/systems/replay/gauntlet_board.gd")

## 【门禁 / 实拍注入点】{"group": 我那一组, "cup": 冠军杯赛, "groups": [各组]}。空 = 读 Supabase 缓存(玩家路径)。
static var override: Dictionary = {}
## 上周冠军 {"name", "tag", "avatar", "week"}; 空 = 还没问到 / 上周没有冠军杯赛。门禁可直接写。
static var prev_champ: Dictionary = {}
## 周锚点 → {#ID: 头像 id}(赛况板那一周最新一行的头像)。
static var avatars: Dictionary = {}
static var _asked: Dictionary = {}          # 问过的(周 → true), 一个进程只问一次


static func entered() -> bool:
	return str(GameState.gauntlet_state()) == _P2.GAUNTLET_IN


## 此刻的三份: 我那一组 / 冠军杯赛 / 本周各组。
static func feeds() -> Dictionary:
	if not override.is_empty():
		return {"group": override.get("group", {}), "cup": override.get("cup", {}), "groups": override.get("groups", [])}
	var wk: Dictionary = _SB.finals_week_cached()
	var groups: Array = wk.get("buckets", []) if wk.get("buckets", null) is Array else []
	var group: Dictionary = _SB.finals_cached()
	if int(group.get("size", 0)) < 1:
		group = {}
		for g in groups:
			if g is Dictionary and int((g as Dictionary).get("me", -1)) >= 0:
				group = g
	return {"group": group, "cup": _SB.finals_cup_cached(), "groups": groups}


## 去问一次本周的(两条 RPC 自己有在途闸, 重复调不会叠请求)。
static func pull(now: int) -> void:
	if not _SB.enabled():
		return
	var wk: int = _P2.week_anchor_utc(now)
	_SB.fetch_finals_week_async(wk)
	if entered():
		_SB.fetch_finals_async(wk, -1)


## 上周冠军: 问上周的冠军杯赛 + 上周赛况板的头像(各一次)。
static func pull_prev_champ(now: int) -> void:
	var pw: int = _P2.week_anchor_utc(now) - 7 * 86400
	if _asked.has("champ:%d" % pw) or not _SB.enabled():
		return
	_asked["champ:%d" % pw] = true
	_SB.fetch_finals_week_cb(pw, func(res: Dictionary) -> void:
		var cup: Dictionary = res.get("cup", {}) if res.get("cup", null) is Dictionary else {}
		var sd: int = _M.champion_visible(cup, 2147483647)
		if sd < 0:
			return
		prev_champ = {"name": _M.name_of(cup, sd), "tag": _M.tag_of(cup, sd), "avatar": "", "week": pw}
		pull_avatars(pw))


## 某一周的头像表(#ID → 头像 id)。回来以后补到上周冠军上。
static func pull_avatars(week: int) -> void:
	if _asked.has("av:%d" % week) or not _SB.enabled():
		return
	_asked["av:%d" % week] = true
	_SB.fetch_gauntlet_board_async(week, func(res: Dictionary) -> void:
		if not res.has("rows"):
			return
		var mp := {}
		for p in (_Board.build(res["rows"], "", true).get("players", []) as Array):
			if str(p.get("tag", "")) != "" and str(p.get("avatar", "")) != "":
				mp[str(p["tag"])] = str(p["avatar"])
		avatars[week] = mp
		if int(prev_champ.get("week", -1)) == week:
			prev_champ["avatar"] = str(mp.get(str(prev_champ.get("tag", "")), "")))


static func avatar_of(week: int, tag: String) -> String:
	var mp = avatars.get(week, {})
	return str((mp as Dictionary).get(tag, "")) if mp is Dictionary else ""
