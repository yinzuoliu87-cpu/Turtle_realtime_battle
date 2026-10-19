class_name StreamHud
extends RefCounted
## 服务器逐帧直播 · 播放端 HUD。方案书 docs/plans/20261019-服务器逐帧直播.md §2.5。
##
## ★原则: 播放端**照常跑现有 HUD 代码**(头像框栏 `_build_team_panels` / 每帧 `_update_team_panels`、法术圆盘、
##   顶部 PK 条 + topbar_status、路名计时牌 `_dl_update_hud`、幕布), 只是喂给它们的字段来自流:
##   单位代理上的字段 + 战斗场上几个 HUD 读的状态。本文件只管两件事:
##   ① 录流器那一侧: 把 HUD 要、而单位层名单里没有的东西算成**纯值**(合成单位字段 `@eq` / `@hud`, 全局 `hud`)。
##      录流器每个采样步调一次 `unit_field` / `glob`, 变了才发(和其它字段同一套比对)。
##   ② 播放器那一侧: 收到后还原成 HUD 代码读的形状(`equips` / `eq_state` / `_synergy._by_side` / `_sd_t0` …),
##      并在**本机会建 HUD 的那几个时刻**照样建(新单位进场 ⇒ 头像框栏; 我方大师进场 ⇒ 法术圆盘)。
##
## 合成字段(全是纯值, 不含单位字典 / 节点):
##   `@eq`  = [[[装备 id, 星级], …], 古灵精怪枪数, [立绘首帧路径, hframes, vframes]]
##            —— 头像框装备格(`_refresh_panel_equips` 读 `equips` / `gremlin_guns`); 没有方头像的(小将)头像取立绘首帧(`idle_sd`)
##   `@hud` = {HUD_UKEYS 里非空的那几个, "c:<eid>": 层数徽章整数, "g:<eid>": 充能条 0..CHG_Q}
##            —— 装备格读数(EquipReadouts.COUNT / CHARGE, 只取头像框真画的那几件)、蛋副条(哪侧 / 围栏)、侵入阵营
##   全局 `h.<项>`(每项单独比、变了才发) = {syn: 两侧羁绊档位, lr: 各路胜负, t0: 本战场开打时刻, sd: 加时层数, wu: 破蛋窗口截止,
##                 pl: 本路待记败方, eh: 两侧蛋血, sv: 上下路幸存名单}
##            —— 羁绊 chips、路点、路名计时牌(「上路战场 0:23」/ 加时 / 破蛋倒数)、幕布(战果 / 蛋血 / 终极战场对阵)

## 合成单位字段的键(录流器按这个顺序逐个比、变了才发)
const UNIT_KEYS := ["@eq", "@hud"]
## `@hud` 里直接照抄的单位标量(HUD 读、单位层名单里没有的)
const HUD_UKEYS := ["egg_side_lr", "_egg_fence", "_eggImmune", "hijacked", "_hijack_orig_side"]
## 充能条量化级数(条宽 44 像素 ⇒ 误差 ≤ 0.02 像素)
const CHG_Q := 1024.0


# ═══════════════════════════════════════════════════════════════════════
#  ① 录流器那一侧(纯函数: 只读战斗状态, 不改任何东西)
# ═══════════════════════════════════════════════════════════════════════
static func unit_field(u: Dictionary, k: String):
	if k == "@eq":
		var out: Array = []
		for e in u.get("equips", []):
			if e is Dictionary:
				out.append([str((e as Dictionary).get("id", "")), int((e as Dictionary).get("star", 1))])
		var isd: Array = []
		var sd = u.get("idle_sd")
		if sd is Dictionary and (sd as Dictionary).get("tex") is Texture2D:
			var tp := str(((sd as Dictionary)["tex"] as Texture2D).resource_path)
			if tp != "" and tp.find("::") < 0:
				isd = [tp, int((sd as Dictionary).get("hframes", 1)), int((sd as Dictionary).get("vframes", 1))]
		return [out, int(u.get("gremlin_guns", 0)), isd]
	var d := {}
	for k2 in HUD_UKEYS:
		var v = u.get(k2)
		var t := typeof(v)
		if t == TYPE_BOOL or t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_STRING:
			d[k2] = v
	var es = u.get("eq_state")
	if es is Dictionary and not (es as Dictionary).is_empty():
		for eid in _panel_ids(u):
			var st = (es as Dictionary).get(eid)
			if not (st is Dictionary):
				continue
			if EquipReadouts.COUNT.has(eid):
				d["c:" + eid] = int((st as Dictionary).get(str(EquipReadouts.COUNT[eid]), 0))
			if EquipReadouts.CHARGE.has(eid):
				var spec: Array = EquipReadouts.CHARGE[eid]
				var fr: float = clampf(float((st as Dictionary).get(str(spec[0]), 0.0)) / float(spec[1]), 0.0, 1.0)
				d["g:" + eid] = int(roundf(fr * CHG_Q))
	return d


## 头像框装备格画的那几件(与 `_refresh_panel_equips` 同口径: 前 4 件 + 古灵精怪枪虚拟格; 036 温泉蛋还给等级牌加临时等级)
static func _panel_ids(u: Dictionary) -> Array:
	var ids: Array = []
	var eq: Array = u.get("equips", [])
	for i in range(eq.size()):
		if eq[i] is Dictionary:
			var eid := str((eq[i] as Dictionary).get("id", ""))
			if i < 4 or eid == "p2eq_036":
				ids.append(eid)
	if int(u.get("gremlin_guns", 0)) > 0:
		ids.append("gremlin_gun")
	return ids


static func glob(battle) -> Dictionary:
	var syn := {}
	if battle._synergy != null:
		var bs: Dictionary = battle._synergy._by_side
		for side in bs:
			syn[str(side)] = (bs[side] as Dictionary).duplicate() if bs[side] is Dictionary else {}
	var gs = battle.get_node_or_null("/root/GameState")
	var lr := {}
	if gs != null and gs.get("lane_results") is Dictionary:
		lr = (gs.lane_results as Dictionary).duplicate()
	var eh := {}
	var sv := {}
	if gs != null:
		if gs.get("egg_hp") is Dictionary:
			for k in gs.egg_hp:
				eh[k] = int(gs.egg_hp[k])     # 幕布只写整数(「龟蛋生命 我方 4704」) ⇒ 只发整数, 蛋挨打的小数不触发重发
		if gs.get("dual_survivors") is Dictionary:
			sv = _pure(gs.dual_survivors)
	return {"syn": syn, "lr": lr, "t0": float(battle._sd_t0), "sd": int(battle._sd_stacks), "wu": float(battle._dl_window_until),
		"pl": str(battle._dl_pending_loser), "eh": eh, "sv": sv}


## 这一步有没有「手机当场按状态建 HUD」的事件(幕布进场): 有就连同全局 `hud` 一起发, 不等下一个采样步 ——
##   幕布(战果 / 蛋血 / 比分)在事件那一步就按 `pl` / `eh` / `lr` 建好了, 晚一步拿到就是上一路的数(实测抓到: 「本路胜利 2:0」对「本路失败 1:1」)。
static func wants_glob(evs: Array) -> bool:
	for e in evs:
		if str(e[0]) == "curtain_in":
			return true
	return false


## 只留纯值(数 / 串 / 布尔 / 向量, 以及由它们组成的数组和字典): 流里不许带对象引用
static func _pure(v):
	if v is Dictionary:
		var d := {}
		for k in v:
			var x = _pure(v[k])
			if x != null:
				d[k] = x
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			var y = _pure(x)
			if y != null:
				a.append(y)
		return a
	var t := typeof(v)
	if t == TYPE_OBJECT or t == TYPE_CALLABLE or t == TYPE_SIGNAL or t == TYPE_RID or t == TYPE_NIL:
		return null
	return v


## 播放端顶栏 / 幕布的两个名字: 与录像回放同一个口径(`ReplayRecorder.side_names`: 入口 stream_watch 给的
##   `play_names` 优先; 没给就「看的人自己 vs 对手快照里的名字」)。录像的开局状态由入口写进了 GameState(`begin_play`)。
static func side_names() -> Dictionary:
	var gs = Engine.get_main_loop().root.get_node_or_null("/root/GameState") if Engine.get_main_loop() is SceneTree else null
	var g = gs.dual_ghost if gs != null else {}
	return ReplayRecorder.side_names({"state": {"dual_ghost": g}}, ReplayRecorder.viewer_name)


# ═══════════════════════════════════════════════════════════════════════
#  ② 播放器那一侧
# ═══════════════════════════════════════════════════════════════════════
var battle
var player
var _panel_sig: Array = []        # 上一次看到的「该进头像框栏的单位」(idx:有效阵营)
var _disc_done := false
## 计数(门禁分母)
var panels_built := 0
var equips_set := 0


func _init(b, p) -> void:
	battle = b
	player = p


## 播放器 `_unit_set` 收到合成字段时调
func apply_unit(u: Dictionary, k: String, v) -> void:
	if k == "@eq" and v is Array and (v as Array).size() >= 2:
		var eq: Array = []
		for e in (v[0] as Array):
			eq.append({"id": str(e[0]), "star": int(e[1])})
		u["equips"] = eq
		u["gremlin_guns"] = int(v[1])
		var isd: Array = v[2] if (v as Array).size() > 2 and v[2] is Array else []
		if isd.size() >= 3 and ResourceLoader.exists(str(isd[0])):
			u["idle_sd"] = {"tex": load(str(isd[0])), "hframes": int(isd[1]), "vframes": int(isd[2])}
		equips_set += 1
		if u.get("panel_eq_row") != null and is_instance_valid(u.get("panel_eq_row")):
			battle._refresh_panel_equips(u)      # 本机: 招财进宝 / 古灵精怪枪运行时改装备后同样调它
		return
	if k == "@hud" and v is Dictionary:
		var d: Dictionary = v
		for k2 in HUD_UKEYS:
			if d.has(k2):
				u[k2] = d[k2]
			else:
				u.erase(k2)
		var es := {}
		for key in d:
			var ks := str(key)
			if ks.begins_with("c:"):
				var eid := ks.substr(2)
				if not es.has(eid):
					es[eid] = {}
				es[eid][str(EquipReadouts.COUNT[eid])] = int(d[key])
			elif ks.begins_with("g:"):
				var eid2 := ks.substr(2)
				var spec: Array = EquipReadouts.CHARGE[eid2]
				if not es.has(eid2):
					es[eid2] = {}
				es[eid2][str(spec[0])] = float(d[key]) / CHG_Q * float(spec[1])
		u["eq_state"] = es


## 播放器 `_globals` 收到全局 `hud` 时调
func apply_glob(g: Dictionary) -> void:
	if g.get("syn") is Dictionary and battle._synergy != null:
		var bs := {"left": {}, "right": {}}
		for side in (g["syn"] as Dictionary):
			bs[str(side)] = (g["syn"][side] as Dictionary).duplicate()
		battle._synergy._by_side = bs
	if g.has("t0"):
		battle._sd_t0 = float(g["t0"])
	if g.has("sd"):
		var sd0 := int(battle._sd_stacks)
		battle._sd_stacks = int(g["sd"])
		if sd0 == 0 and int(battle._sd_stacks) == 1 and player.firing and battle._hud != null and battle._hud._topbar != null:
			battle._hud._topbar.show_splash()     # 本机 `_sd_tick` 升到第 1 档时播一次「加时」大字(`_announce_sudden`)
	if g.has("wu"):
		battle._dl_window_until = float(g["wu"])
	if g.has("pl"):
		battle._dl_pending_loser = str(g["pl"])
	if player.gs_sandboxed():
		var gs = battle.get_node_or_null("/root/GameState")
		if g.get("lr") is Dictionary:
			gs.lane_results = (g["lr"] as Dictionary).duplicate()
		if g.get("eh") is Dictionary:
			gs.egg_hp = (g["eh"] as Dictionary).duplicate(true)
		if g.get("sv") is Dictionary:
			gs.dual_survivors = (g["sv"] as Dictionary).duplicate(true)


## 每应用完一步调: 本机会建 HUD 的时刻, 播放端照样建。
##   · 头像框栏: 本机在每路建场(`_dl_build_lane_field` 末尾)和驯服归顺时重建 —— 都是「该进栏的单位多了 / 换了阵营」。
##     ★单位**少了**不重建: 本机一路里死掉的单位留在 `_units`(框变暗), 换路清场后旧框也是留到下一路建场才换。
##   · 法术圆盘: 本机在第一次摆出我方大师时建(`_build_spell_disc` 自带「建过就不再建」)。
func after_step() -> void:
	var sig: Array = []
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var d: Dictionary = u
		if bool(d.get("is_summon", false)) or bool(d.get("is_trainer", false)) or InfoPanel.is_egg_unit(d):
			continue
		sig.append("%d:%s" % [int(d.get("_stream_idx", -1)), battle._eff_side(d)])
	var grew := false
	for s in sig:
		if not _panel_sig.has(s):
			grew = true
			break
	_panel_sig = sig
	if grew and battle._ui_layer != null:
		battle._hud._build_team_panels()
		panels_built += 1
	if not _disc_done:
		for u in battle._units:
			if bool((u as Dictionary).get("is_trainer", false)) and str((u as Dictionary).get("side", "")) == "left":
				battle._hud._build_spell_disc(str(u.get("_tr_active", "")), str(u.get("_tr_passive", "")))
				_disc_done = true
				break


## 收尾: 服务器那一局 `_dl_finish(won, 延时)` 录成事件 `finish`。顺播到那一步 ⇒ 照本机那样隔「延时」秒出收尾;
##   跳转快进时跳过了那一步(不放事件)⇒ 播放器播到结尾(state == "ended")时补出。只出一次。
var won := false
var finished := false
var end_shown := false


func on_finish(w: bool, delay: float) -> void:
	won = w
	finished = true
	if player.firing:
		_show_end(delay)


func on_ended() -> void:
	if end_shown:
		return
	if not finished and battle._dl_sys != null:
		won = bool(battle._dl_sys._dl_overall_won())   # 流里没有 finish(不该发生): 按各路胜负算
	_show_end(0.0)


func _show_end(delay: float) -> void:
	if end_shown or battle._hud == null:
		return
	end_shown = true
	if delay > 0.0 and battle.is_inside_tree():
		## 与本机 `_dl_finish` 同: 蛋碎后晚一点出。Timer 挂在战斗场景上 ⇒ 场景没了它跟着没(树级计时器会活过场景释放)。
		var bt := Timer.new()
		bt.one_shot = true
		bt.wait_time = delay
		bt.process_mode = Node.PROCESS_MODE_ALWAYS
		battle.add_child(bt)
		bt.timeout.connect(battle._hud.show_stream_end.bind(won))
		bt.start()
	else:
		battle._hud.show_stream_end(won)


## 跳转清场后: 下一次 after_step 按新单位重建头像框栏(圆盘建一次就常驻, 与本机相同)
func reset() -> void:
	_panel_sig = []
