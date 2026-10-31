class_name BracketCeremony
extends RefCounted
## bracket_ceremony.gd —— 对阵图上接 D 的三样仪式(2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md 块 D / G7 G10 G12)
##
##   · 冠军决出那一刻 ⇒ `ChampionShow`(冠军杯: 收盘总流程; 组: 缩短版「晋级冠军杯赛 · 20:00 开赛」); 冠军本人看 ⇒ 带奖励链
##   · 冠军杯第 1 场开播前 / 第一次进冠军杯页时第 1 场还没开播 ⇒ `ChampionIntro`(组冠军依次亮相, 上届冠军标「卫冕」)
##   · 「冠军墙」入口 ⇒ `ChampionWall`(往届, 最近 8 届)
## ★同一周同一张图只演一次 —— 看直播看到决赛结束的人, 冠军杯收盘已经由 `ChampionHook.on_cup_final_end`(观战那一侧)演过了,
##   回到对阵图不再演第二遍(读 ChampionHook 的 `last_data`, 那边没留标记就用这里自己的静态标记)。
## ★画面全在 D 的 champion_*.gd 里, 这里只挑时机 + 拼参数, 一个字都不改它们。

const _CD := preload("res://scripts/scenes/bracket/champion_data.gd")
const _CS := preload("res://scripts/scenes/bracket/champion_show.gd")
const _CI := preload("res://scripts/scenes/bracket/champion_intro.gd")
const _CW := preload("res://scripts/scenes/bracket/champion_wall.gd")
const _CH := preload("res://scripts/scenes/bracket/champion_hook.gd")
const _B := preload("res://scripts/gamedata/bracket.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
## M 的「没守到最后的人下次开机补看」(G21): 冠军杯收盘这里演过了 ⇒ 记成看过, 下次开机不再补演。
##   ★用到时才 load(不 preload): 那是 M 的文件, 它改到一半编译不过时不连带对阵图整屏编译失败。
const RECAP_PATH := "res://scripts/ui/finals_day_recap.gd"

## 演过的(「cup|周」/「group|组号|周」)与开场亮相演过的周。★静态: 看完回放回来(新场景实例)不重演。
static var played: Dictionary = {}
static var intro_played: Dictionary = {}

var s
var last_show = null          # 最近一次打开的 ChampionShow(门禁读)
var last_intro = null
var last_wall = null


func _init(scene) -> void:
	s = scene


## 这一张图这一周演过了吗(含观战那一侧 ChampionHook 演的冠军杯收盘)。
func already_played(cup: bool, bucket: int, week: int) -> bool:
	if played.has(_key(cup, bucket, week)):
		return true
	if cup and s.is_inside_tree():
		for h in s.get_tree().get_nodes_in_group(_CH.GROUP):
			var ld = h.get("last_data")
			if ld is Dictionary and str((ld as Dictionary).get("mode", "")) == "cup" and int((ld as Dictionary).get("week", -1)) == week:
				return true
	return false


static func _key(cup: bool, bucket: int, week: int) -> String:
	return "cup|%d" % week if cup else "group|%d|%d" % [bucket, week]


## 冠军决出那一刻(场景的挂点 `_on_champion_decided` 调)。返回打开的 ChampionShow; 不演 = null。
func play_champion(data: Dictionary):
	var view: Dictionary = data.get("view", {}) if data.get("view", {}) is Dictionary else {}
	var wk := int(data.get("week", 0))
	var cup := str(data.get("stage", "")) == "cup"
	var bk := int(data.get("bucket", -1))
	if already_played(cup, bk, wk):
		played[_key(cup, bk, wk)] = true
		return null
	var gs = s.get_node_or_null("/root/GameState")
	var my_acc := str(gs.get("account_id")) if gs != null else ""
	var d: Dictionary = {}
	_CD.portraits = s._portraits       # 头像: 对阵图从同周赛况板拿到的那份(仪式自己手里没有比赛记录)
	if cup:
		d = _CD.cup_show(view, wk, [], my_acc)
	else:
		d = _CD.group_show(view, bk, wk, [], my_acc, "晋级%s · %s 开赛" % [_P2C.STAGE_CUP, _P2C.local_hhmm(int(s._cup_start_ts()))])
	if d.is_empty():
		return null
	played[_key(cup, bk, wk)] = true
	if bool(d.get("viewer_is_champion", false)):
		## 冠军本人: 定格卡上出「领取奖励」(头衔 + 这一周打的那几轮深海币; 币当场已入账, 奖励链只是演出来)
		var rounds := 0
		if cup:
			rounds = _CH.rounds_played(view, d.get("path", []))
		else:
			for row in (d.get("path", []) as Array):
				if not bool((row as Dictionary).get("bye", false)):
					rounds += 1
		d["rewards"] = _CD.reward_pages([_P2C.TITLE_CHAMPION if cup else _P2C.TITLE_GROUP_CHAMPION], rounds)
		if gs != null:
			d["coin_from"] = maxi(0, int(gs.get("meta_deepsea_coins")) - rounds * int(_P2C.FINALS_COINS_PER_ROUND))
		## coin_target: 对阵图顶栏没有深海币图标 ⇒ 不给, 奖励链飞到它自己画的右上角小条
	last_show = _CS.open(s, d)               # 定格卡上的「冠军墙」由 ChampionShow 自己开(没人接 wall_requested 时它自己开)
	if cup and ResourceLoader.exists(RECAP_PATH):
		var rc = load(RECAP_PATH)
		if rc != null and rc.has_method("mark_seen"):
			rc.mark_seen(wk)
	return last_show


## 冠军杯开场亮相(G7): 冠军杯页、成表、第 1 轮还没有一场开播 ⇒ 每周演一次。
func maybe_intro() -> void:
	if str(s._view) != "finals" or not bool(s.ceremony_on):
		return
	var c: Dictionary = s._finals
	var n := int(c.get("size", 0))
	if n < 2:
		return
	var wk := int(s.feed_week())
	if intro_played.has(wk):
		return
	for m in range(_B.matches_in_round(n, 1)):
		var st := str(s.match_state(1, m))
		if st == str(s.ST_PREMIERE) or (st == str(s.ST_DONE) and not bool(s.competitor(1, m, 0).get("bye", false))
				and not bool(s.competitor(1, m, 1).get("bye", false))):
			return                          # 第 1 轮已经有场开播 / 播完了: 开场那一拍已经过去
	_CD.portraits = s._portraits
	var d: Dictionary = _CD.cup_intro(s._week_view(), wk, [], str(s.defending_acc))
	if (d.get("entrants", []) as Array).is_empty():
		return
	intro_played[wk] = true
	last_intro = _CI.open(s, d)


## 冠军墙(G12): 往届最近 8 届。
func open_wall() -> void:
	last_wall = _CW.open(s, {"loading": true})
	last_wall.load_weeks(int(s.feed_week()), 8)
