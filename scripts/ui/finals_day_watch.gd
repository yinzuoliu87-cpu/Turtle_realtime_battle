extends RefCounted
## 从任何一屏直接进某一场的开播 / 回放(2026-10-31 方案书 20261031c 块 M ⑤⑦⑧)。
## 主菜单「观看开播」、全局「你的比赛 30 秒后开播 · 观看」、收盘补看「重看」三处共用 —— 不必先进对阵图再点一次(P19 / G17)。
## ★取录像与开播会话的做法与对阵图 `open_replay` 同一套(ReplayFetcher.open_finals + live_spectate.premiere_session),
##   开播中 ⇒ 挂开播会话(迟到的人从当前进度看); 已揭晓 ⇒ 回放。即将开播(还没轮到它)不开: 点了只能对着第 0 步干等。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _B := preload("res://scripts/gamedata/bracket.gd")
const _LS := preload("res://scripts/systems/replay/live_spectate.gd")
const _RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const _RN := preload("res://scripts/net/referee_net.gd")

const BRACKET := "res://scenes/BracketMap.tscn"

## 门禁读: 最近一次请求了哪一场 / 走的哪条路(premiere | replay | wait)。
static var last_ask: Dictionary = {}


## 这一场此刻能不能直接点开看(开播中 / 已揭晓)。即将开播 / 没翻面 ⇒ false。
static func can_open(b: Dictionary, r: int, m: int, now: int) -> bool:
	if int(b.get("bucket", -1)) < 0 or not (b.get("done", {}) as Dictionary).has("%d-%d" % [r, m]):
		return false
	return not _LS.premiere_upcoming(b, r, m, now)


## 开这一场。`week` = 那张图的周锚点; `back` = 看完回哪一屏(默认对阵图); `done(code, msg)` 取不到时回一句话。
static func open(tree: SceneTree, week: int, b: Dictionary, r: int, m: int, now: int, back: String = BRACKET,
		done: Callable = Callable()) -> bool:
	if tree == null or not can_open(b, r, m, now):
		last_ask = {"how": "wait", "r": r, "m": m}
		return false
	var bk := int(b.get("bucket", -1))
	var n := int(b.get("size", 0))
	var d: Dictionary = b.get("done", {})
	var ws := int(d.get("%d-%d" % [r, m], -1))
	var vd: Dictionary = {}
	## 两边是谁: 按「上一轮已揭晓」推(这一场自己的胜负不参与 —— 不剧透)
	for k in d:
		if int(str(k).get_slice("-", 0)) < r:
			vd[str(k)] = int(d[k])
	var a := _B.occupant_seed(r, m, 0, n, vd)
	var z := _B.occupant_seed(r, m, 1, n, vd)
	var names: Array = b.get("names", [])
	var pair := [str(names[a]) if a >= 0 and a < names.size() else "", str(names[z]) if z >= 0 and z < names.size() else ""]
	var wn := str(pair[ws]) if ws >= 0 and ws < 2 else ""
	var live := _LS.premiere_hidden(b, r, m, now)
	if live:
		_LS.pending = _LS.premiere_session(b, r, m, now)
	var me := int(b.get("me", -1))
	var own := me >= 0 and (a == me or z == me)
	last_ask = {"how": "premiere" if live else "replay", "week": week, "bucket": bk, "round": r, "match": m, "back": back}
	var cb := func(code: String, msg: String) -> void:
		if code != "":
			_LS.pending = {}
		if done.is_valid():
			done.call(code, msg)
	_RF.open_finals(tree, week, bk, r, m, cb, back, {"l": wn, "r": wn, "pair": pair}, own and _RN.finals_on())
	return true
