extends RefCounted
## finals_lineup_push.gd —— 周日决赛: 背包里的阵容怎样交给服务端 + 交没交上的回执(2026-11-15)。
##
## 用户 11-15:「这个周日这里，这明明手明明在背包里面调了阵容，为什么在比赛里面的阵容不是这个备赛的呢？
##   还说只有备赛时间段内调整阵容才算啊？这是怎么算的呀？」
## 正式服只读核对: LouisT01 决赛用的是周六 03:29 闯关第 4 胜那一份, 之后背包里的调整一次都没进 finals_entrants。
## 原来的三处毛病:
##   ① 只有停在对阵图(BracketMapScene._on_poll)才推 ⇒ 在背包里改完、3 分钟备战窗里没回对阵图 = 永远推不上;
##   ② 推了也不看回包: 服务端 20261101b 起「开不了打的阵容」静默拒收, 客户端照样当成交上了;
##   ③ 文案「未调整阵容时沿用当前阵容」让人以为用的是背包里现在那套。
## 现在:
##   · 全局层 FinalsDay(决赛日每个玩家屏都在, 背包也在)每秒调 `tick()`: 入座了、这一组没收盘、备战窗开着 ⇒ 推;
##     阵容一变(指纹不同)隔 ≥ CHANGED_MIN_SEC 就推, 没变照旧 15 秒补推一次(节流与对阵图那条路共用 backend._finals_snap_at)。
##   · 回执: supabase.finals_update_snapshot 的回包交给 `note_result` —— true / false / 网络失败各记一份,
##     `tick()` 据此返回一句提示, 全局层在当前屏弹出来。
##   · 备战窗外改了阵容 ⇒ 提示「下一轮备战开始时按这套阵容提交」(真话: 窗一开全局层就推)。
##   ★服务端规则一个字没动(仍是每轮开打后 180 秒内才收); 「入座后随时收」要改正式服函数, 等用户点头。

const _SB := preload("res://scripts/net/supabase.gd")
const _BE := preload("res://scripts/net/backend.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

const TXT_OK := "阵容已提交，本轮按这套阵容出战"
const TXT_REJECTED := "这套阵容没有生效，本轮沿用上一次提交的阵容"
const TXT_NET := "阵容提交失败，正在重试"
const TXT_LATER := "下一轮备战开始时，会按这套阵容提交"

## 服务端回包(note_result 写, tick 读)。n 每来一个回包 +1。
static var receipt: Dictionary = {}
static var _receipt_n := 0
static var _shown_n := 0
## 服务端确认收下的那一份的指纹(收下后再推同一份不再提示)
static var _ok_sig := ""
## 上一拍看到的阵容指纹(窗外改阵容的提示用)
static var _seen_sig := ""
static var _later_sig := ""
## 不收 / 网络失败已经说过的那一份(15 秒补推一次, 同一份不反复弹)
static var _bad_sig := ""


## 我此刻在打的那一张: 冠军杯赛里有我且没收盘 ⇒ 杯; 否则我那一组(与 BracketMapScene._live_dict 同一条规则)。
static func live_of(group: Dictionary, cup: Dictionary) -> Dictionary:
	if int(cup.get("me", -1)) >= 0 and int(cup.get("size", 0)) > 1 and not bool(cup.get("closed", false)):
		return cup
	return group


## 我在这一张里, 而且还有下一场可备战(组里不止一人、没收盘)。纯函数。
static func seated(lv: Dictionary) -> bool:
	return int(lv.get("me", -1)) >= 0 and int(lv.get("size", 0)) > 1 and not bool(lv.get("closed", false))


## 这一拍该推吗: 入座 + 备战窗开着(窗的判据只在 phase2_config.finals_shop_open 一处)。纯函数。
static func due(lv: Dictionary, now_local: int) -> bool:
	return seated(lv) and _SB.finals_shop_open_of(lv, now_local)


## 全局层每秒一拍。返回要弹的一句(空 = 不弹)。
static func tick(group: Dictionary, cup: Dictionary, now_unix: int) -> String:
	var lv := live_of(group, cup)
	if not seated(lv):
		return ""
	var now_local: int = _P2.delta_clock()
	var sig := _BE.finals_snap_sig()
	if due(lv, now_local):
		_BE.finals_push_snapshot(int(lv.get("bucket", -1)), now_unix)
	elif sig != "" and _seen_sig != "" and sig != _seen_sig and sig != _later_sig:
		## 窗外改了阵容: 现在推服务端也不收 ⇒ 说清楚什么时候算
		_later_sig = sig
		_seen_sig = sig
		return TXT_LATER
	if sig != "":
		_seen_sig = sig
	return _consume()


## 回包来了(supabase.finals_update_snapshot 的回调里调)。服务端回 JSON 布尔: true = 收下, false = 不收。
static func note_result(res: Dictionary, snapshot: Dictionary) -> void:
	var body := str(res.get("body", "")).strip_edges()
	var net_ok: bool = bool(res.get("ok", false)) and int(res.get("code", 0)) >= 200 and int(res.get("code", 0)) < 300
	_receipt_n += 1
	receipt = {"n": _receipt_n, "net": net_ok, "ok": net_ok and body == "true", "sig": _BE.snap_sig_of(snapshot),
		"blocked": bool(res.get("blocked", false))}


## 新回包 ⇒ 该不该说一句: 收下的是一份新阵容 ⇒ 说已提交; 不收 / 网络失败 ⇒ 每份阵容各说一次。
static func _consume() -> String:
	if receipt.is_empty() or int(receipt.get("n", 0)) <= _shown_n:
		return ""
	_shown_n = int(receipt["n"])
	var sig := str(receipt.get("sig", ""))
	if bool(receipt.get("blocked", false)):
		return ""                       # 版本墙 / 时间穿越挡下的写请求: 那边自己有提示
	if bool(receipt.get("ok", false)):
		if sig == _ok_sig:
			return ""                   # 同一份补推, 不重复说
		_ok_sig = sig
		return TXT_OK
	var bad_key := ("net|" if not bool(receipt.get("net", false)) else "no|") + sig
	if sig == _ok_sig or bad_key == _bad_sig:
		return ""
	_bad_sig = bad_key
	return TXT_NET if not bool(receipt.get("net", false)) else TXT_REJECTED


## 门禁用: 清回执与指纹(进程里跑多段时)。
static func reset() -> void:
	receipt = {}
	_receipt_n = 0
	_shown_n = 0
	_ok_sig = ""
	_seen_sig = ""
	_later_sig = ""
	_bad_sig = ""
