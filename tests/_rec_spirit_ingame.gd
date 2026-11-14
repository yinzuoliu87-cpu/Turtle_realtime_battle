extends Node
## 灵物触手·真对局录屏台(不是门禁, 2026-11-14): 用户「那你把成品给我看看」—— 新外形(深海磷光)放进真对局是什么样。
## 真战斗场 RealtimeBattle3D.tscn、默认镜头、两队照常开打; 只在开打第 2 帧给我方(左)第一只龟塞 2 件不同的灵物装备
##   ⇒ 灵物 1 档 = 1 根触手(与 demo_spirit_slap 同一套: 塞完必须 clear + apply_all 重算档位, 否则触手不登场)。
## 录 REC_SECS 秒(默认 24, 游戏秒 = 视频秒)后自己 quit。[REC] 行打触手状态变化与拍击账本。
##
## 跑法 —— 录视频(窗口只开右屏、静音):
##   SHIP=1 APPDATA=<单独目录> XDG_DATA_HOME=<同一目录> WINDOW=1 bash godot-quiet.sh --position 2000,80 \
##     --resolution 1560x720 --write-movie <输出>/spirit.avi --fixed-fps 60 --quit-after 3000 res://tests/_rec_spirit_ingame.tscn
## 跑法 —— 无头自查: bash godot-quiet.sh --quit-after 3000 res://tests/_rec_spirit_ingame.tscn(同样设 APPDATA / XDG_DATA_HOME)
## 可选: REC_SECS=秒 · REC_EQ=逗号分隔的装备 id(默认 p2eq_046,p2eq_062)

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
## 与 TentacleVfx 的 enum { ST_EMERGE, ST_IDLE, ST_REAR, ST_SLAM, ST_RECOVER, ST_RETRACT, ST_WARN } 同序; -1 = 不在场
const STATE_NAMES := {-1: "不在场", 0: "出土", 1: "待机", 2: "抬起", 3: "拍下", 4: "收回", 5: "钻地", 6: "预警"}

var _scn = null
var _el := 0.0
var _secs := 24.0
var _armed := false
var _last_st := -99
var _n_state := {}


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	if OS.has_environment("REC_SECS"):
		_secs = float(OS.get_environment("REC_SECS"))
	## REC_PAL=<配色名>: 临时换触手配色(染色法认「画面上哪一团是触手」, 例 coral = 红)
	if OS.has_environment("REC_PAL"):
		TentacleMeshVfx.palette_override = OS.get_environment("REC_PAL")
	_scn = load(BATTLE_SCENE).instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame
	var ids: Array = ["p2eq_046", "p2eq_062"]
	if OS.has_environment("REC_EQ"):
		ids = Array(OS.get_environment("REC_EQ").split(",", false))
	var carrier = null
	for u in _scn._units:
		if u is Dictionary and str(u.get("side", "")) == "left" and u.get("alive", false) \
				and not u.get("is_trainer", false) and not u.get("is_summon", false):
			carrier = u
			break
	if carrier == null:
		print("REC FAIL: 左方没有能带装备的龟")
		get_tree().quit(1)
		return
	var eqs: Array = (carrier.get("equips", []) as Array).duplicate()
	for iid in ids:
		eqs.append({"id": str(iid), "star": 1})
	carrier["equips"] = eqs
	_scn._synergy.clear()
	_scn._synergy.apply_all()
	print("[REC] 带装备的龟 %s · 灵物档位 左 %d / 右 %d · 外形 %s" % [str(carrier.get("id", "?")),
		_scn._spirit_syn._side_tier("left"), _scn._spirit_syn._side_tier("right"),
		str(TentacleMeshVfx.palette_override if TentacleMeshVfx.palette_override != "" else TentacleMeshVfx.PALETTE_DEFAULT)])
	_armed = true


func _process(delta: float) -> void:
	if not _armed:
		return
	_el += delta
	var st: int = int(_scn._tentacle_vfx.state_of("left", 0))
	if st != _last_st:
		print("[REC] %.2f 秒 触手 → %s(%d)" % [_el, str(STATE_NAMES.get(st, "?")), st])
		_n_state[st] = int(_n_state.get(st, 0)) + 1
		_last_st = st
	if _el >= _secs:
		_armed = false
		print("[REC] 拍击账本 %s · 各状态进入次数 %s" % [str(_scn._spirit_syn._pk), str(_n_state)])
		var ok: bool = int(_n_state.get(3, 0)) >= 2
		print("REC OK" if ok else "REC FAIL: 拍下不到 2 次")
		get_tree().quit(0 if ok else 1)
