class_name FinalsConfirm
extends RefCounted
## finals_confirm.gd —— 周末决赛「确定阵容」(2026-11-16 · 方案书 docs/plans/20261116b-周末确定阵容按钮.md)。
##
## 用户 11-16:「加个按钮，就加在背包里面…加个确定阵容，然后在点确定阵容的时候，就顺便把那个选择技能，
##   就是能够跳出来让玩家选择」。周六每局开打前本来就经过选龟页(本大轮统领, 能换技能); 缺口在周日 ——
##   决赛不经过选龟页, 技能换不了, 阵容也是 0.23.4 起背包一改就自动推、玩家不知道哪一刻算数。
## 现在:
##   · 背包顶栏「确定阵容」(finals_confirm_btn.gd): 本周已晋级、决赛还没打完才有; 背包与上次提交的一样 ⇒「阵容已确定」
##   · 点了 ⇒ 打开「本大轮统领」页的决赛模式(TeamSelectScene: pick_mode)⇒ 换技能 ⇒「提交阵容」⇒ submit()
##   · 服务端 finals_confirm_snapshot(迁移 20261116): 什么时候交都算 —— 入座前写晋级那一行、备战窗内本轮生效、
##     窗外下一轮生效、小组打完等冠军杯时进杯生效; 回 applies / reason, 这里翻成一句话
##   · 只认点过「提交阵容」的那一份(finals_lineup_push 不再自动推); 每轮备战时背包有没提交的改动 ⇒ 提醒一次(remind)

const _FN := preload("res://scripts/net/friends_net.gd")
const _BE := preload("res://scripts/net/backend.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _FLP := preload("res://scripts/net/finals_lineup_push.gd")
const _FDF := preload("res://scripts/ui/finals_day_feed.gd")

const RPC := "finals_confirm_snapshot"
const SAVE_PATH := "user://finals_confirm.json"

## 按钮 / 页面文案
const BTN_CONFIRM := "确定阵容"
const BTN_DONE := "阵容已确定"
const PAGE_TITLE := "决赛阵容"
const PAGE_HINT := "提交后按这套阵容出战\n点击统领卡可更换技能"
const PAGE_SUBMIT := "提交阵容"
const PAGE_SENDING := "提交中"
## 回执
const R_SEAT := "已提交：决赛按这套阵容出战"
const R_NOW := "已提交：本轮按这套阵容出战"
const R_NEXT := "已提交：下一轮起按这套阵容出战"
const R_CUP := "已提交：冠军杯赛按这套阵容出战"
const E_BAD := "没有提交：三只统领要各不相同，并且都要排进上路或下路"
const E_CLOSED := "没有提交：你的决赛已经结束"
const E_NOT_ENTERED := "没有提交：本周没有晋级决赛"
const E_NET := "没有提交：网络不通，请稍后重试"
const REMIND := "阵容有改动还没提交，点背包里的「确定阵容」提交"

## 阶段: "" = 不显示按钮 / pre = 已晋级、还没分组 / live = 已分组、还有比赛
const STAGE_PRE := "pre"
const STAGE_LIVE := "live"

## 选龟页决赛模式: 背包按钮置 true 再进选龟页, 选龟页 _ready 取走(取一次就清)
static var pick_mode := false
## 回执: 提交后回到背包时弹一次(take_receipt 取走)
static var _receipt := ""
## 每轮只提醒一次(键 = 表号:轮次)
static var _reminded_key := ""
## 门禁 / 实拍注入: 非空 ⇒ stage() 一律回它
static var override_stage := ""
## 观测量(门禁分母)
static var submits := 0


## 此刻按钮该不该出现、处在哪一段。纯读状态, 不联网。
static func stage(now: int) -> String:
	if override_stage != "":
		return "" if override_stage == "none" else override_stage
	if GameState == null or GameState.gauntlet_state() != _P2.GAUNTLET_IN:
		return ""
	if not _P2.phase_mode_live(_P2.PHASE_FINALS):
		return ""
	var ph: String = _P2.phase_at_utc(now)
	if ph != _P2.PHASE_GAUNTLET and ph != _P2.PHASE_FINALS:
		return ""
	if now < _P2.finals_seat_ts(int(GameState.week_anchor_ts)):
		return STAGE_PRE
	var f: Dictionary = _FDF.feeds()
	var lv: Dictionary = _FLP.live_of(f.get("group", {}) as Dictionary, f.get("cup", {}) as Dictionary)
	return STAGE_LIVE if _FLP.seated(lv) else ""


## 背包里此刻那一套的指纹(含技能)。
static func current_sig() -> String:
	return _BE.finals_snap_sig()


## 本周上一次提交成功的那一套的指纹(没交过 ⇒ "")。
static func confirmed_sig() -> String:
	if GameState == null:
		return ""
	var d := _load()
	if int(d.get("week", 0)) != int(GameState.week_anchor_ts):
		return ""
	return str(d.get("sig", ""))


## 背包与上次提交的一样吗(按钮显示「阵容已确定」)。
static func is_confirmed() -> bool:
	var s := current_sig()
	return s != "" and s == confirmed_sig()


## 服务端回包 → 一句话。纯函数(门禁直接喂)。
static func receipt_of(res: Dictionary) -> String:
	if bool(res.get("ok", false)):
		var d: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
		match str(d.get("applies", "")):
			"seat":
				return R_SEAT
			"now":
				return R_NOW
			"next":
				return R_NEXT
			"cup":
				return R_CUP
		return R_NOW
	match str(res.get("reason", "")):
		"bad_lineup", "too_big":
			return E_BAD
		"closed":
			return E_CLOSED
		"not_entered":
			return E_NOT_ENTERED
	return E_NET


## 提交背包里此刻那一套。`done(msg: String, ok: bool)` 一定会被调一次。
static func submit(done: Callable) -> void:
	var snap: Dictionary = _BE._finals_snap()
	if snap.is_empty():
		done.call(E_BAD, false)
		return
	var wk := int(GameState.week_anchor_ts)
	var sig := _BE.snap_sig_of(snap)
	submits += 1
	_FN.call_rpc(RPC, {"p_week": wk, "p_snapshot": snap}, func(res: Dictionary) -> void:
		var ok := bool(res.get("ok", false))
		if ok:
			_save({"week": wk, "sig": sig})
		var msg := receipt_of(res)
		_receipt = msg
		done.call(msg, ok))


## 回到背包时弹的那一句(取一次就清)。
static func take_receipt() -> String:
	var m := _receipt
	_receipt = ""
	return m


## 决赛日全局层每拍调: 这一轮备战开着、背包有没提交的改动 ⇒ 提醒一次(每轮一次)。返回要弹的一句。
static func remind(group: Dictionary, cup: Dictionary) -> String:
	var lv := _FLP.live_of(group, cup)
	if not _FLP.due(lv, _P2.delta_clock()):
		return ""
	if is_confirmed() or current_sig() == "":
		return ""
	var key := "%d:%d" % [int(lv.get("bucket", -1)), int(lv.get("round_at", 0))]   # 每一轮的开打时刻不同 ⇒ 一轮一个键
	if key == _reminded_key:
		return ""
	_reminded_key = key
	return REMIND


static func _load() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return j if j is Dictionary else {}


static func _save(d: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()


## 门禁用: 清掉本机记录与静态状态
static func reset_for_test() -> void:
	pick_mode = false
	_receipt = ""
	_reminded_key = ""
	override_stage = ""
	submits = 0
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
