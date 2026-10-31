class_name ChampionHook
extends Node
## champion_hook.gd —— 冠军杯决赛播完 → 冠军收盘总流程 的接手点(块 C ↔ 块 D 的交接)。
## 观战收尾(scripts/scenes/battle/finals_end_beats.gd)在冠军杯决赛第二拍落定那一刻对组 `finals_champion` 调
##   `on_cup_final_end(info, host)`; 组里有节点 ⇒ 它停在第二拍、收起自己的卡, 由这里接手演冠军收盘。
## ★这个节点常驻在根下(跨场景活着): 由 `ChampionHook.install(get_tree())` 装一次(重复装只留一个)。
## 收盘的定格卡点「关闭」⇒ 回对阵图(与观战收尾「返回对阵图」同一个出口: 战斗场 HUD 的 `_replay_exit`)。

const GROUP := "finals_champion"
const SHOW := preload("res://scripts/scenes/bracket/champion_show.gd")
const DATA := preload("res://scripts/scenes/bracket/champion_data.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var last_data: Dictionary = {}     # 最近一次演的数据(门禁读)
var last_show: CanvasLayer = null


func _init() -> void:
	name = "ChampionHook"
	add_to_group(GROUP)


## 装到根下(延后一帧加, 避开「根节点正忙」); 已经有了就返回现成的那个。
static func install(tree: SceneTree) -> ChampionHook:
	for n in tree.get_nodes_in_group(GROUP):
		if n is ChampionHook:
			return n
	var h := ChampionHook.new()
	tree.root.add_child.call_deferred(h)
	return h


## 本周的周锚点: 优先用服务端的钟(缓存里带着), 没有就用本机钟。
static func week_of(view: Dictionary) -> int:
	var now := int(view.get("srv_now", 0))
	if now <= 0:
		now = int(Time.get_unix_time_from_system())
	return P2C.week_anchor_utc(now)


## 冠军本人这一周打了几轮(轮空不算; 每轮那 8 深海币当场已入账, 奖励链只是演出来)。
static func rounds_played(view: Dictionary, cup_path: Array) -> int:
	var n := 0
	for row in cup_path:
		if not bool((row as Dictionary).get("bye", false)):
			n += 1
	for b in (view.get("buckets", []) as Array):
		if b is Dictionary and int((b as Dictionary).get("me", -1)) >= 0:
			for row in DATA.path_of(b, int(b["me"]), {}, true):
				if not bool(row.get("bye", false)):
					n += 1
	return n


func on_cup_final_end(info: Dictionary, host: Control) -> void:
	var view: Dictionary = SB.finals_week_cached()
	var d: Dictionary = DATA.cup_show_from_end(info, view, week_of(view))
	if d.is_empty():
		return
	if bool(d.get("viewer_is_champion", false)):
		var titles: Array = [P2C.TITLE_CHAMPION]
		var rounds := rounds_played(view, d.get("path", []))
		d["rewards"] = DATA.reward_pages(titles, rounds)
		var gs = get_node_or_null("/root/GameState")
		if gs != null:
			var amount := rounds * int(P2C.FINALS_COINS_PER_ROUND)
			d["coin_from"] = maxi(0, int(gs.get("meta_deepsea_coins")) - amount)
	last_data = d
	var parent: Node = host if host != null and is_instance_valid(host) else get_tree().root
	last_show = SHOW.open(parent, d)
	load("res://scripts/ui/finals_day_recap.gd").mark_seen(int(d.get("week", 0)))   # 演过 ⇒ 下次开机不再补演(块 M G21)
	last_show.finished.connect(_on_closed.bind(host))


## 定格卡关掉 ⇒ 回对阵图(不在战斗场里, 比如门禁直接调, 就什么都不做)。
func _on_closed(host: Control) -> void:
	if host == null or not is_instance_valid(host):
		return
	var sc := host.get_tree().current_scene
	var hud = sc.get("_hud") if sc != null else null
	if hud != null and hud.has_method("_replay_exit"):
		hud._replay_exit()
