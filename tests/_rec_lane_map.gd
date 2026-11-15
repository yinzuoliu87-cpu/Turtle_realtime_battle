extends Node
## 三路战场地图开场录像台(不是门禁, 2026-11-15)。方案书 docs/plans/20261115d-三路战场地图开场.md。
## 用户 11-15「三路开战…不符合一种商业游戏啊…是否可以通过…地图一样的形式去展现出来，就是做多做点动画啥的」→ 录成片给用户看。
## 阵容: App Store 截图台那份真实玩家种子(`_setup_appstore.gd`: 三统领带装备 + 对手快照)。
##
## 时间线(游戏秒; --write-movie 下 = 视频秒):
##   0~10   开场地图(5 秒) → 上路对阵(5 秒), 真流程自己走
##   10     开战横幅
##   ~13.5  按真实规则收这一路: 输的一方全灭(battle._kill, 有死亡演出), 赢的一方也阵亡一只 —— 一路本来就要打到一方全灭才结束,
##          只有赢的一方活下来的进终极战场(用户 11-15「我们只有幸存者会进入终极战场…项目的规矩你也搞清楚」);
##          1.5 秒后进「上路战果」(左方赢)。破蛋那 10 秒省掉(录像不等)。
##   ~20    下路对阵 → 开战 → 同上收这一路(右方赢 ⇒ 1:1 ⇒ 有终极战场)
##   ~31    终极战场对阵 → 开战 → 再录 3 秒 quit
## 跑法(右屏、静音、单独存档目录):
##   APPDATA=<单独目录> XDG_DATA_HOME=<同一目录> DUALLANE=1 SHIP=1 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " WINDOW=1 \
##     bash godot-quiet.sh --path . --resolution 1560x720 --position 2000,80 --write-movie <输出>/lane_map.avi --fixed-fps 30 \
##     --quit-after 2400 res://tests/_rec_lane_map.tscn
## 可选: REC_FIGHT_SEC = 每路开打后几秒进战果(默认 3.5)
## 声音: 录制一律静音(godot-quiet.sh); 每一声的触发时刻打成 [SFX] 行(视频秒 · 音效名 · 音量 · 音高),
##   再由 tools/oneoff/mix_rec_sfx.py 按这些时刻把同一批音效文件混进成片(不在用户电脑上外放)。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"

var _b = null
var _el := 0.0
var _fight_sec := 3.5
var _fight_t0 := -1.0
var _settled := {}
var _done_t := -1.0
var _logged := {}
var _last_state := ""
var _kill_t := -1.0
var _loser := ""


func _ready() -> void:
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	if OS.has_environment("REC_FIGHT_SEC"):
		_fight_sec = float(OS.get_environment("REC_FIGHT_SEC"))
	var scr: GDScript = load("res://tests/_setup_appstore.gd")
	scr.run()
	await get_tree().process_frame
	_b = load(BATTLE_SCENE).instantiate()
	add_child(_b)
	print("[REC] 进场")


func _process(d: float) -> void:
	_el += d
	if _b == null or not is_instance_valid(_b):
		return
	var st := str(_b._dl_state)
	var ln := str(GameState.current_lane)
	_log_sfx(st)
	if st == "fight" or st == "eggwindow":
		if _fight_t0 < 0.0:
			_fight_t0 = _el
			print("[REC] %.2f 开打 %s" % [_el, ln])
			if OS.has_environment("REC_PROBE"):
				print("[PROBE] 开打时 dual_survivors = ", JSON.stringify(GameState.dual_survivors))
		if ln != "final" and not _settled.has(ln) and _kill_t < 0.0 and _el - _fight_t0 >= _fight_sec:
			_kill_t = _el
			_loser = "right" if ln == "top" else "left"
			## 赢方阵亡一只: 挑小将(带驯服标记的龟死了会以 30% 血重生、改投训龟大师那一边 —— 那是真规则, 但录像里不想人为触发)
			for u in _b._units.duplicate():
				if u.get("alive", false) and u.get("_isMinion", false) and _b._eff_side(u) != _loser and not u.get("_isEgg", false):
					_b._kill(u)
					break
			print("[REC] %.2f 收这一路 %s: 输的一方 %s 全灭, 赢的一方阵亡一只小将" % [_el, ln, _loser])
		## 输的一方: 每帧把还活着的都击杀, 直到真的一个不剩(驯服重生 / 涅槃 / 圣光之类会再站起来, 再杀)
		if _kill_t > 0.0 and _loser != "":
			for u in _b._units.duplicate():
				if u.get("alive", false) and _b._eff_side(u) == _loser and not u.get("_isEgg", false) and not u.get("is_summon", false) and not u.get("is_trainer", false):
					_b._kill(u)
			if OS.has_environment("REC_PROBE"):
				for u2 in _b._units:
					if u2.get("_isEgg", false) or u2.get("is_trainer", false):
						continue
					print("[PROBE] %s side=%s eff=%s alive=%s summon=%s tamed=%s hijacked=%s" % [str(u2.get("id", "?")), str(u2.get("side", "")), _b._eff_side(u2), str(u2.get("alive", false)), str(u2.get("is_summon", false)), str(u2.get("tamed_side", "")), str(u2.get("hijacked", ""))])
		if ln != "final" and not _settled.has(ln) and _kill_t > 0.0 and _el - _kill_t >= 1.5:
			_settled[ln] = true
			_kill_t = -1.0
			_loser = ""
			_b._dl_pending_loser = "right" if ln == "top" else "left"
			print("[REC] %.2f 进战果 %s(输的一方 %s)" % [_el, ln, _b._dl_pending_loser])
			_b._dl_sys._dl_enter_present("lane_settle")
			if OS.has_environment("REC_PROBE"):
				print("[PROBE] 进战果时 dual_survivors = ", JSON.stringify(GameState.dual_survivors))
		if ln == "final" and _done_t < 0.0 and _el - _fight_t0 >= 3.0:
			_done_t = _el
	else:
		_fight_t0 = -1.0
	if _done_t > 0.0 or _el > 70.0:
		print("[REC] %.2f 收工" % _el)
		get_tree().quit(0)


## 幕布演出轨道里到点响过的声音 + 开打那一声(fight_start, 在 dual_lane_flow._dl_fight_start_dramatize)
func _log_sfx(st: String) -> void:
	if st == "fight" and _last_state != "fight":
		print("[SFX] %.3f fight_start 1.0 1.0" % _el)
	_last_state = st
	var back = _b._dl_present_root
	if back == null or not is_instance_valid(back):
		return
	for c in back.get_children():
		var it = c.get("intro")
		if it == null:
			continue
		for i in it.tracks.size():
			var tr: Dictionary = it.tracks[i]
			if str(tr["k"]) != "sfx" or not bool(tr["fired"]):
				continue
			var key := "%d|%d" % [it.get_instance_id(), i]
			if _logged.has(key):
				continue
			_logged[key] = true
			if it.t < float(tr["t0"]) + 0.5:   # 真到点响的(摆过头直接作废的不算)
				print("[SFX] %.3f %s %s %s" % [_el - (it.t - float(tr["t0"])), str(tr["name"]), str(tr["vol"]), str(tr["pitch"])])
