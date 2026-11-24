extends Node
## 炸弹羁绊 + 10 件炸弹 + 武士刀 实战录像台(不是门禁, 2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md)。
## 用户 11-24「你全部做完，然后给我看成果…分段给我看视频」。
## 走真流程: 双路对局(DL_AUTOFIGHT 跳开场总览), 我方三统领带满 10 件炸弹(顶档) + 武士刀, 对手 = 产品自己的机器人快照。
##   上路: 两只统领带 097~104(鞭炮/爆竹筒/手雷/烟雾弹/粘弹/地雷/炸药桶/定时炸弹)
##   下路: 一只统领带 105 炮筒 / 106 遥控炸弹 / 107 武士刀
## 跑法(右屏、静音、单独存档目录):
##   APPDATA=<目录> XDG_DATA_HOME=<目录> DUALLANE=1 DL_AUTOFIGHT=1 SHIP=1 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " WINDOW=1 \
##     bash godot-quiet.sh --path . --resolution 1280x720 --position 2000,80 --write-movie <输出>/bomb.avi --fixed-fps 30 \
##     res://tests/_rec_bomb_showcase.tscn
## 可选: REC_MAX_SEC(默认 75) 录多久就收工。
const Backend := preload("res://scripts/net/backend.gd")
const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
const LEADERS := ["two_head", "phoenix", "lightning"]

var _b = null
var _el := 0.0
var _max := 75.0
var _last := ""


func _ready() -> void:
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	if OS.has_environment("REC_MAX_SEC"):
		_max = float(OS.get_environment("REC_MAX_SEC"))
	GameState.test_mode = true
	GameState.nickname = "录像台"
	GameState.season_level = 12
	GameState.season_total_battles = 20
	GameState.season_leaders = LEADERS.duplicate()
	GameState.dual_lineup = {}
	var lineup: Dictionary = GameState.get_dual_lineup()
	var st := int(OS.get_environment("REC_STAR")) if OS.has_environment("REC_STAR") else 2
	var mk := func(ids: Array) -> Array:
		var a: Array = []
		for i in ids:
			a.append({"id": i, "star": st})
		return a
	## REC_SETS="097,098,099,100|101,102,103,104|105,106,107" = 上路两只 | 下路一只 各带哪几件(分段录: 少带几件 ⇒ 羁绊档低、打得久, 周期件看得到)
	var sets := (OS.get_environment("REC_SETS") if OS.has_environment("REC_SETS") else "097,098,099,100|101,102,103,104|105,106,107").split("|")
	var pe := {}
	for i in range(LEADERS.size()):
		var ids: Array = []
		if i < sets.size():
			for x in str(sets[i]).split(",", false):
				ids.append("p2eq_" + x.strip_edges())
		pe[LEADERS[i]] = mk.call(ids)
	GameState.persistent_equipped = pe
	GameState.dual_lineup = lineup
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261124
	var bl := int(OS.get_environment("REC_FOE_LV")) if OS.has_environment("REC_FOE_LV") else 20
	var bot: Dictionary = Backend.make_bot(bl, rng)
	bot["leaders"] = ["lava", "ninja", "crystal"]
	bot["lane_assign"] = {"top": ["lava", "ninja"], "bottom": ["crystal"]}
	## 对手装备: 机器人生成器按等级给的那几套(产品自己的), 只是换到这三只身上; 一件炸弹都不带(画面里分得清谁在炸)
	var olds: Array = (bot.get("equipped", {}) as Dictionary).values()
	var eq := {}
	var k := 0
	for pid in ["lava", "ninja", "crystal"]:
		var lst: Array = []
		if k < olds.size() and olds[k] is Array:
			for e in olds[k]:
				if e is Dictionary and int(str(e.get("id", "p2eq_000")).substr(5)) < 97:
					lst.append(e)
		eq[pid] = lst
		k += 1
	bot["equipped"] = eq
	var plv := int(OS.get_environment("REC_FOE_PET")) if OS.has_environment("REC_FOE_PET") else 4
	bot["pet_levels"] = {"lava": plv, "ninja": plv, "crystal": plv}
	bot["loadouts"] = {}
	GameState.dual_ghost = bot
	await get_tree().process_frame
	_b = load(BATTLE_SCENE).instantiate()
	add_child(_b)
	print("[REC] 进场")


func _process(d: float) -> void:
	_el += d
	if _b == null or not is_instance_valid(_b):
		return
	var s := "%s/%s" % [str(_b._dl_state), str(GameState.current_lane)]
	if s != _last:
		_last = s
		print("[REC] %.2f 状态 %s" % [_el, s])
		if s.begins_with("fight/"):
			## REC_FOE_HPX: 录像台专用 —— 对手血量 ×N(只为让周期装备有时间出手; 不是产品数值)
			var hx := float(OS.get_environment("REC_FOE_HPX")) if OS.has_environment("REC_FOE_HPX") else 1.0
			if hx != 1.0:
				for u in _b._units:
					if u is Dictionary and str(u.get("side", "")) == "right" and not bool(u.get("_isEgg", false)) and not bool(u.get("is_trainer", false)):
						u["maxHp"] = float(u["maxHp"]) * hx
						u["hp"] = float(u["maxHp"])
			for u in _b._units:
				if u is Dictionary and not bool(u.get("_isEgg", false)):
					print("[REC]    %s %s hp %.0f atk %.0f 装备 %d 炸弹档 %d" % [str(u.get("side", "")), str(u.get("id", "")), float(u.get("maxHp", 0)), float(u.get("atk", 0)), (u.get("equips", []) as Array).size(), int(_b._synergy.tier_for(u, "炸弹"))])
	var bs = _b._equip_sys._bomb_sys if _b.get("_equip_sys") != null else null
	if bs != null and int(_el * 2.0) != int((_el - d) * 2.0) and int(_el) % 5 == 0 and int(_el * 2.0) % 2 == 0:
		print("[REC] %.1f 炸弹计数 %s · 导弹 %d" % [_el, JSON.stringify(bs.stat), _b._bomb_syn.strikes])
	if _el > _max:
		print("[REC] %.2f 收工" % _el)
		get_tree().quit(0)
