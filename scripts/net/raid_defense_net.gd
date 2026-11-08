extends RefCounted
## raid_defense_net.gd —— 偷袭防守阵容上传(2026-11-08 · 方案书 docs/plans/20261107-龟战主站对接.md §4.2;
##   接口照契约 §3: `raid_defense_put(p_week, p_snapshot, p_device) → {ok, has_defense}`)。
##
## 偷袭不另设阵容: 守方用自己**最新的一份**周赛快照(`build_ghost_snapshot` 的产物, 与积分赛上传、好友切磋同一个)。
##   原来快照只在打完一局时上传 ⇒ 补三处调用, 改了阵容不用打一局也生效:
##   · 离开背包(`InventoryScene._exit_tree`) · 离开选龟页(`TeamSelectScene._exit_tree`)
##   · 每打完一局(`Backend.upload_ghost`, 积分赛 / 闯关赛结算都经过它)
## ★只在本周已开轮时传: 本周已选定 3 只统领, 且本机赛季就是这一周(`week_anchor_ts` == 当前周锚点)。
##   方案书 §4.2「双方都必须已开本大轮」: 快照不是本周的 ⇒ 没有阵容(服务器也按 `p_week` 再判一次)。
## ★阵容与上次传成功的一样 ⇒ 一个请求都不发; 失败(没网 / 没令牌 / 服务器拒)静默, 下次再传, 不打扰玩家。
## ★教程沙盒 / test_mode(门禁 / 回放 / 切磋)里不传 —— 那时内存里不是玩家自己的阵容。
## ★形状照抄 `FriendsNet.put_lineup`(同一个快照函数、同一个 RPC 出口)。
## 守卫: tests/verify_raid_defense_put.gd

const SB := preload("res://scripts/net/supabase.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const FN := preload("res://scripts/net/friends_net.gd")
const ML := preload("res://scripts/net/mainsite_link.gd")

const RPC := "raid_defense_put"

## 【门禁注入点】true ⇒ 跳过 test_mode 那一道(不跳过「没变不传」与「本周已开轮」)。默认 false = 玩家路径。
static var force_in_test := false
## 观测量(门禁分母): 真交给 RPC 出口的次数 / 各种不传的次数。
static var puts := 0
static var skipped: Dictionary = {}
static var _last_key := ""
static var _inflight_key := ""


static func _reset_for_test() -> void:
	puts = 0
	skipped = {}
	_last_key = ""
	_inflight_key = ""


## 纯判据: 这一刻算不算「本周已开轮」。`leaders` = season_leaders, `wk_local` = 本机赛季那一周, `wk_now` = 当前周锚点。
static func week_open(leaders, wk_local: int, wk_now: int) -> bool:
	if not (leaders is Array) or (leaders as Array).size() != 3:
		return false
	for pid in leaders:
		if str(pid) == "":
			return false
	return wk_now > 0 and wk_local == wk_now


static func _skip(why: String, cb: Callable) -> void:
	skipped[why] = int(skipped.get(why, 0)) + 1
	cb.call({"ok": false, "reason": why, "data": {}})


## 传当前阵容。`done(r)` 一定会被调一次(r 形状同 `FriendsNet.parse`; 没传时 reason 说为什么)。
static func put_defense(done: Callable = Callable()) -> void:
	var cb := done if done.is_valid() else func(_r: Dictionary) -> void: pass
	var gs = SB._gs()
	if gs == null or bool(gs.get("tutorial_active")) or (bool(gs.get("test_mode")) and not force_in_test):
		_skip("skip", cb)
		return
	if not SB.enabled():
		_skip("off", cb)
		return
	var wk: int = P2.week_anchor_utc(int(P2.now_utc()))
	if not week_open(gs.get("season_leaders"), int(gs.get("week_anchor_ts")), wk):
		_skip("not_open", cb)
		return
	var snap: Dictionary = FN.my_snapshot()
	if snap.is_empty():
		_skip("not_open", cb)
		return
	var key := ("%s|%d|%s" % [str(gs.account_id), wk, JSON.stringify(snap, "", true)]).sha256_text()
	if key == _last_key:
		_skip("same", cb)
		return
	if key == _inflight_key:
		_skip("inflight", cb)
		return
	_inflight_key = key
	puts += 1
	FN.call_rpc(RPC, {"p_week": wk, "p_snapshot": snap, "p_device": ML.device_id()}, func(r: Dictionary) -> void:
		if _inflight_key == key:
			_inflight_key = ""
		if bool(r["ok"]):
			_last_key = key
		cb.call(r))
