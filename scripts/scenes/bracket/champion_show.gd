class_name ChampionShow
extends CanvasLayer
## champion_show.gd —— 冠军收盘总流程(G10)/ 组冠军缩短版。可以叠在任何一屏上的独立层。
## 方案书 docs/plans/20261031c-周日赛事界面重做.md 块 D ①②; 依据 ref/20261031-周日赛事参考/学到的.md
##   C-3(Clash 夺冠 12 s 情绪曲线: 结果 → 蓄力 → 全屏白闪 → 奖杯从光里出 → 称号 + 规模, 整段不放按钮)、
##   5-3(揭晓前停一拍)、6-6(先亚军后冠军)、6-7 / 10-6 / 8-7(夺冠阵容逐只特写)、J-8(「夺冠之路」逐轮)、
##   2-10 / 9-10(冠军定格卡常驻)、2-11(今晚之最)、反面 5-8(夺冠只有一行字)。
##
## 拍子(冠军杯, 约 13~15 s; 组冠军约 8.5~10 s):
##   reveal   「决赛完成 · 揭晓中」停一拍
##   runner   亚军卡(银缎带「冠军杯亚军」)                       —— 只冠军杯有
##   crown    冠军头像收成光球蓄力 → 全屏白闪 → 奖杯(组冠军: 奖章)从光里升起 →「冠军」大字 → 名字缎带 → 规模 + 届数日期; 彩带
##   lineup   夺冠阵容(三统领)逐只特写, 再排成一排                 —— 没拿到阵容就跳过, 时长补给 crown
##   path     夺冠之路: 每一轮 轮次 · 对手 · 比分 · 胜
##   bests    今晚之最(2~3 张)                                     —— 只冠军杯、有数据才有
##   card     冠军定格卡(常驻, 直到玩家关掉; 这一拍落定后才出按钮)
## ★整段(card 之前)场上没有一颗按钮; 点屏只把**这一拍**拨到终态(再停 SKIP_HOLD 秒进下一拍), 不跳过整段。
## ★演出全部「按拍内时间 t 算状态」, 不用 Tween: `advance(dt)` 推进(平时 `_process` 自己喂; 门禁关掉
##   `auto_advance` 自己喂), 跳拍 = 把 t 拨到终点。
##
## ── 用法 ──
##   var show := ChampionShow.open(host, data)      # host = 任意一屏的节点; 自己加成子节点
##   show.finished.connect(...)                      # 玩家点「关闭」后发(层已自己 queue_free)
##   show.wall_requested.connect(...)                # 点「冠军墙」; 没人接就自己开一个空的冠军墙
## data 由 `ChampionData.cup_show()` / `ChampionData.group_show()` 生成, 字段见该文件; 另可加:
##   "rewards": ChampionData.reward_pages(...)       # 冠军本人看时定格卡上出「领取奖励」, 点开奖励链(ChampionRewards)
##   "coin_target": Vector2                          # 奖励链里深海币飞去的点(主菜单顶栏图标的屏幕坐标); 不给就飞到本层自画的右上角小条
##   "coin_from": int                                # 深海币入账前的余额(右上角小条从它滚到新值)

signal beat_started(beat: String)
signal sequence_done            # 定格卡落定、按钮出现
signal rewards_claimed          # 奖励链走完
signal wall_requested
signal finished

const UI := preload("res://scripts/scenes/bracket/champion_ui.gd")
const FX := preload("res://scripts/scenes/bracket/champion_fx.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const DATA := preload("res://scripts/scenes/bracket/champion_data.gd")
const REWARDS_PATH := "res://scripts/scenes/bracket/champion_rewards.gd"
const WALL_PATH := "res://scripts/scenes/bracket/champion_wall.gd"

const LAYER := 96
const CUP_RANGE := Vector2(12.0, 16.0)        # 冠军杯总长(到定格卡落定)要落在这里
const GROUP_RANGE := Vector2(8.0, 11.0)
const SKIP_HOLD := 0.5                         # 点屏落定后再停多久进下一拍
const FADE_OLD := 0.22
const FADE_NEW := 0.15
const T_FLASH := 1.0                           # crown 拍内: 白闪时刻

var data: Dictionary = {}
var auto_advance := true
var beats: Array = []          # [{name, dur, anim}]
var beat_i := -1
var bt := 0.0                  # 当前拍内时间
var elapsed := 0.0             # 从开演起
var beat_log: Array = []       # [[拍名, 开始时刻]]
var settled_at := -1.0         # 定格卡落定(按钮出现)的时刻
var skips := 0

var vp := Vector2(1280, 720)
var c := Vector2(640, 360)
var _root: Control
var _bg: TextureRect
var _dim: ColorRect
var _fx
var _holder: Control
var _stage: Control
var _old: Control
var _old_t := 0.0
var _flash: ColorRect
var _flash_t := -99.0
var _cur_dur := 0.0
var _fired := {}
var _n := {}                   # 当前拍的节点
var _closed := false
var _claimed := false


static func create(d: Dictionary) -> ChampionShow:
	var s := ChampionShow.new()
	s.data = d
	return s


static func open(host: Node, d: Dictionary) -> ChampionShow:
	var s := create(d)
	host.add_child(s)
	return s


func _ready() -> void:
	layer = LAYER
	vp = data["vp"] if data.get("vp", null) is Vector2 else get_viewport().get_visible_rect().size   # 门禁量两种比例时直接给
	c = vp * 0.5
	_build_base()
	_plan()
	_enter(0, 0.0)


func _process(dt: float) -> void:
	if auto_advance:
		advance(minf(dt, 0.1))


# ═══════════════════════════════════════════════════════════════════
#  时间线
# ═══════════════════════════════════════════════════════════════════
func is_cup() -> bool:
	return str(data.get("mode", "cup")) != "group"


func lineup() -> Array:
	var out: Array = []
	var a = data.get("lineup", [])
	if a is Array:
		for x in a:
			if out.size() < 3 and UI.has_body(str(x)):
				out.append(str(x))
	return out


func path_rows() -> Array:
	var a = data.get("path", [])
	return a if a is Array else []


func bests() -> Array:
	var a = data.get("bests", [])
	return (a as Array).slice(0, 3) if a is Array else []


func _plan() -> void:
	beats.clear()
	var cup := is_cup()
	var nl := lineup().size()
	var np := path_rows().size()
	beats.append({"name": "reveal", "dur": 1.6 if cup else 1.3, "anim": 0.5})
	if cup and not (data.get("runner_up", {}) as Dictionary).is_empty():
		beats.append({"name": "runner", "dur": 2.0, "anim": 0.75})
	beats.append({"name": "crown", "dur": 4.0 if cup else 3.4, "anim": 2.45})
	if nl > 0:
		## 逐只落位, 最后一只落定后再停一拍(0.8~0.9 s)让三只并排看清
		var per := 0.55 if cup else 0.5
		beats.append({"name": "lineup", "dur": 0.35 + per * nl + (0.9 if cup else 0.8), "anim": 0.35 + per * nl + 0.15, "per": per})
	if np > 0:
		var step := 0.45 if cup else 0.4
		beats.append({"name": "path", "dur": 0.4 + step * np + (0.6 if cup else 0.5), "anim": 0.4 + step * np + 0.2, "step": step})
	if cup and not bests().is_empty():
		var nb := bests().size()
		beats.append({"name": "bests", "dur": 0.45 + 0.35 * nb + 1.0, "anim": 0.45 + 0.35 * nb + 0.6})
	beats.append({"name": "card", "dur": INF, "anim": 0.6})
	_fit(CUP_RANGE if cup else GROUP_RANGE)


## 总长落进区间: 短了就把差额补给 crown 的停留(冠军那一刻多停一会儿); 长了先压今晚之最 / 夺冠之路 / crown 的停留。
func _fit(rng: Vector2) -> void:
	var tot := total_length()
	if tot < rng.x:
		_beat("crown")["dur"] = float(_beat("crown")["dur"]) + (rng.x - tot) + 0.3
		return
	var over := tot - (rng.y - 0.2)
	for nm in ["bests", "path", "crown"]:
		if over <= 0.0:
			break
		var b := _beat(nm)
		if b.is_empty():
			continue
		var slack := float(b["dur"]) - float(b["anim"]) - 0.35
		var cut := clampf(over, 0.0, maxf(0.0, slack))
		b["dur"] = float(b["dur"]) - cut
		over -= cut


func _beat(nm: String) -> Dictionary:
	for b in beats:
		if str(b["name"]) == nm:
			return b
	return {}


## 到定格卡落定为止一共几秒(= 定格卡之前各拍 + 定格卡入场)。
func total_length() -> float:
	var s := 0.0
	for b in beats:
		s += float(b["anim"]) if str(b["name"]) == "card" else float(b["dur"])
	return s


func current_beat() -> String:
	return str(beats[beat_i]["name"]) if beat_i >= 0 and beat_i < beats.size() else ""


func is_settled() -> bool:
	return settled_at >= 0.0


func node(nm: String) -> Node:
	return _root.find_child(nm, true, false) if _root != null else null


func advance(dt: float) -> void:
	if _closed or beat_i < 0:
		return
	elapsed += dt
	bt += dt
	_fx.step(dt)
	if _old != null:
		_old_t += dt
		_old.modulate.a = 1.0 - UI.seg(_old_t, 0.0, FADE_OLD)
		if _old_t >= FADE_OLD:
			_old.queue_free()
			_old = null
	while beat_i < beats.size() - 1 and bt >= _cur_dur:
		_enter(beat_i + 1, bt - _cur_dur)
	_apply()
	var fa := elapsed - _flash_t
	_flash.color.a = 1.0 if (fa >= 0.0 and fa < 0.034) else (1.0 - UI.seg(fa, 0.034, 0.13)) * (1.0 if fa >= 0.0 else 0.0)
	if current_beat() == "card" and bt >= float(beats[beat_i]["anim"]) and settled_at < 0.0:
		settled_at = elapsed
		_show_buttons()
		sequence_done.emit()


## 点屏: 这一拍直接到终态, 再停 SKIP_HOLD 秒进下一拍(定格卡: 只落定)。
func skip_beat() -> void:
	if _closed or beat_i < 0:
		return
	var b: Dictionary = beats[beat_i]
	if bt < float(b["anim"]):
		skips += 1
		bt = float(b["anim"])
	if str(b["name"]) != "card":
		_cur_dur = minf(_cur_dur, bt + SKIP_HOLD)
	_apply()
	if str(b["name"]) == "card" and settled_at < 0.0:
		settled_at = elapsed
		_show_buttons()
		sequence_done.emit()


func _enter(i: int, carry: float) -> void:
	if _old != null:
		_old.queue_free()
	_old = _stage
	_old_t = 0.0
	beat_i = i
	bt = carry
	_cur_dur = float(beats[i]["dur"])
	_fired = {}
	_n = {}
	_stage = Control.new()
	_stage.name = "Stage_" + str(beats[i]["name"])
	_stage.size = vp
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_stage)
	beat_log.append([str(beats[i]["name"]), elapsed - carry])
	match str(beats[i]["name"]):
		"reveal": _build_reveal()
		"runner": _build_runner()
		"crown": _build_crown()
		"lineup": _build_lineup()
		"path": _build_path()
		"bests": _build_bests()
		"card": _build_card()
	_apply()
	beat_started.emit(str(beats[i]["name"]))


func _apply() -> void:
	var nm := current_beat()
	if nm == "":
		return
	if nm != "reveal" and nm != "card":
		_stage.modulate.a = UI.seg(bt, 0.0, FADE_NEW)
	match nm:
		"reveal": _apply_reveal(bt)
		"runner": _apply_runner(bt)
		"crown": _apply_crown(bt)
		"lineup": _apply_lineup(bt)
		"path": _apply_path(bt)
		"bests": _apply_bests(bt)
		"card": _apply_card(bt)


func _fire(key: String) -> bool:
	if _fired.has(key):
		return false
	_fired[key] = true
	return true


func _flash_now(at_beat_t: float) -> void:
	_flash_t = elapsed - (bt - at_beat_t)


# ═══════════════════════════════════════════════════════════════════
#  底座: 竞技场背景 + 压暗 + 特效 + 白闪 + 吃点击的整屏
# ═══════════════════════════════════════════════════════════════════
func _build_base() -> void:
	_root = Control.new()
	_root.name = "ChampionRoot"
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)
	_bg = UI.tex_rect(UI.TEX_BG, vp, "ArenaBg")
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.position = Vector2.ZERO
	_bg.modulate = Color(0.5, 0.45, 0.5, 0.0)
	_root.add_child(_bg)
	_dim = UI.box(_root, Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.03, 0.0), "Dim")
	_fx = FX.new()
	_fx.size = vp
	_root.add_child(_fx)
	_holder = Control.new()
	_holder.name = "Stages"
	_holder.size = vp
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_holder)
	_flash = UI.box(_root, Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0), "WhiteFlash")


func _on_root_input(ev: InputEvent) -> void:
	## ★松手才算(memory fb-press-trigger-eats-drag); 触屏走引擎默认的「触摸模拟鼠标」, 不另收 ScreenTouch(否则一下算两下)。
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (ev as InputEventMouseButton).pressed:
		skip_beat()
		_root.accept_event()


# ═══════════════════════════════════════════════════════════════════
#  ① 揭晓中
# ═══════════════════════════════════════════════════════════════════
func _build_reveal() -> void:
	var cup := is_cup()
	var head := "决赛完成" if cup else "%s决赛完成" % str(data.get("group", ""))
	_n["sil_c"] = Vector2(c.x, c.y - 150)
	_n["sil"] = UI.tex_at(_stage, UI.TEX_TROPHY if cup else UI.TEX_MEDAL, _n["sil_c"],
		Vector2(192, 192) if cup else Vector2(128, 128), "Silhouette")
	_n["sil"].modulate = Color(0.16, 0.12, 0.10, 0.0)
	_n["head"] = UI.label_in(_stage, Rect2(0, c.y - 34, vp.x, 88), head, 72, UI.GOLD, true, "RevealText")
	_n["sub"] = UI.label_in(_stage, Rect2(c.x - 200, c.y + 62, 400, 52), "揭晓中", 36, UI.TXT, true, "RevealSub")
	var dots: Array = []
	for i in range(3):
		dots.append(UI.box(_stage, Rect2(c.x - 30 + i * 24, c.y + 126, 12, 12), UI.GOLD, "RevealDot%d" % i))
	_n["dots"] = dots


## 「决赛完成」先砸出来, 「揭晓中」一呼一吸; 背后光束越收越紧、越转越快, 火花往奖杯剪影里聚 —— 让人知道在等结果。
func _apply_reveal(t: float) -> void:
	var dur := float(beats[beat_i]["dur"])
	var k := UI.ease_out(UI.seg(t, 0.0, 0.35))
	_bg.modulate.a = k
	_dim.color.a = 0.6 * k
	var sc: Vector2 = _n["sil_c"]
	if _fire("reveal_sparks"):
		_fx.converge(sc, 34, dur * 0.95, 460.0)
	var head: Control = _n["head"]
	var kh := UI.seg(t, 0.05, 0.3)
	head.modulate.a = kh
	head.scale = Vector2.ONE * lerpf(1.3, 1.0, UI.ease_out(kh))
	var br := 0.5 + 0.5 * sin(t * 5.5)
	var sub: Control = _n["sub"]
	sub.modulate.a = UI.seg(t, 0.25, 0.45) * (0.5 + 0.5 * br)
	sub.scale = Vector2.ONE * (1.0 + 0.06 * br)
	var kg := UI.seg(t, 0.0, dur)
	var sil: Control = _n["sil"]
	sil.modulate = Color(0.16 + 0.34 * kg, 0.12 + 0.26 * kg, 0.10 + 0.12 * kg, 0.9 * UI.seg(t, 0.05, 0.4))
	sil.scale = Vector2.ONE * (1.0 + 0.04 * sin(t * 6.0))
	_fx.rays_col = Color("#ffd772")
	_fx.rays_center = sc
	_fx.rays_radius = maxf(vp.x, vp.y) * lerpf(0.95, 0.3, UI.ease_in(kg))
	_fx.rays_alpha = 0.3 * UI.seg(t, 0.0, 0.4)
	_fx.rays_speed = 0.3 + 1.8 * kg
	for i in range(3):
		var on := int(floor(t * 4.0)) % 4 > i
		(_n["dots"][i] as ColorRect).color = UI.GOLD if on else Color(UI.GOLD, 0.25)


# ═══════════════════════════════════════════════════════════════════
#  ② 亚军
# ═══════════════════════════════════════════════════════════════════
func _build_runner() -> void:
	var ru: Dictionary = data.get("runner_up", {})
	_n["rib"] = UI.ribbon(_stage, Vector2(c.x, c.y - 196), 480, "冠军杯赛亚军", 48, "silver", "RunnerRibbon")
	_n["face"] = UI.portrait(_stage, Vector2(c.x, c.y - 14), 216, str(ru.get("avatar", "")), UI.SILVER, "RunnerFace")
	_n["name"] = UI.label_in(_stage, Rect2(0, c.y + 100, vp.x, 60), str(ru.get("name", "")), 48, UI.SILVER, true, "RunnerName")
	var sub := "第 2 名"
	if str(ru.get("origin", "")) != "":
		sub = "第 2 名（%s）" % str(ru["origin"])          # 来历作补充放括号里, 不用「·」拼
	_n["sub"] = UI.label_in(_stage, Rect2(0, c.y + 160, vp.x, 32), sub, 24, UI.TXT_DIM, false, "RunnerSub")
	_n["rib_y"] = (_n["rib"] as Control).position.y
	_n["face_x"] = (_n["face"] as Control).position.x


func _apply_runner(t: float) -> void:
	_bg.modulate.a = 1.0
	_dim.color.a = 0.55
	## 银色背光(亚军: 比冠军那一拍弱一档)
	_fx.rays_col = UI.SILVER
	_fx.rays_center = Vector2(c.x, c.y - 14)
	_fx.rays_radius = maxf(vp.x, vp.y) * 0.45
	_fx.rays_alpha = 0.35 * UI.ease_out(UI.seg(t, 0.15, 0.6))
	_fx.rays_speed = 0.25
	var rib: Control = _n["rib"]
	rib.position.y = lerpf(-rib.size.y, float(_n["rib_y"]), UI.ease_back(UI.seg(t, 0.0, 0.4)))
	var face: Control = _n["face"]
	var kf := UI.ease_out(UI.seg(t, 0.12, 0.5))
	face.position.x = float(_n["face_x"]) - 260.0 * (1.0 - kf)
	face.modulate.a = kf
	face.position.y = c.y - 14 - face.size.y * 0.5 + (sin((t - 0.5) * 2.2) * 3.0 if t > 0.5 else 0.0)
	for k in ["name", "sub"]:
		var l: Control = _n[k]
		l.modulate.a = UI.seg(t, 0.35, 0.75)


# ═══════════════════════════════════════════════════════════════════
#  ③ 冠军仪式: 蓄力 → 白闪 → 奖杯 / 奖章从光里升起 → 大字 → 名字 → 规模 + 届数
# ═══════════════════════════════════════════════════════════════════
func _build_crown() -> void:
	var ch: Dictionary = data.get("champion", {})
	var cup := is_cup()
	var ty := c.y - 150.0
	_n["orb"] = UI.portrait(_stage, Vector2(c.x, ty + 20), 180, str(ch.get("avatar", "")), UI.GOLD, "Orb")
	if cup:
		_n["ped"] = UI.tex_at(_stage, UI.TEX_PEDESTAL, Vector2(c.x, c.y - 26), Vector2(256, 128), "Pedestal")
		_n["trophy"] = UI.tex_at(_stage, UI.TEX_TROPHY, Vector2(c.x, ty), Vector2(192, 192), "Trophy")
	else:
		_n["trophy"] = UI.tex_at(_stage, UI.TEX_MEDAL, Vector2(c.x, ty + 4), Vector2(128, 128), "Trophy")
		_n["ped"] = UI.ribbon(_stage, Vector2(c.x, c.y - 40), 320, str(data.get("group", "")) + "冠军", 36, "red", "GroupRibbon")
	_n["ty"] = ty
	_n["big"] = UI.label_in(_stage, Rect2(0, c.y + 6, vp.x, 100), "冠军" if cup else "组冠军", 96, UI.GOLD, true, "BigWord")
	_n["banner"] = UI.ribbon(_stage, Vector2(c.x, c.y + 180), 480, str(ch.get("name", "")), 48, "gold", "NameBanner")
	_n["banner_y"] = (_n["banner"] as Control).position.y
	var n := int(data.get("entrants", 0))
	var scale_line := ""
	if cup:
		scale_line = "%s冠军（%d 人参赛）" % [_P2C.STAGE_CUP, n] if n > 0 else "%s冠军" % _P2C.STAGE_CUP
	else:
		scale_line = "%s冠军（%d 人参赛）" % [str(data.get("group", "")), n] if n > 0 else str(data.get("group", "")) + "冠军"
	_n["l1"] = UI.label_in(_stage, Rect2(0, c.y + 244, vp.x, 32), scale_line, 24, UI.TXT, false, "ScaleLine")
	_n["l2"] = UI.label_in(_stage, Rect2(0, c.y + 276, vp.x, 28),
		DATA.edition_line(int(data.get("week", 0)), int(data.get("edition", -1))), 20, UI.TXT_DIM, false, "DateLine")
	for k in ["trophy", "ped", "big", "banner", "l1", "l2"]:
		(_n[k] as Control).modulate.a = 0.0


func _apply_crown(t: float) -> void:
	_bg.modulate.a = 1.0
	_dim.color.a = 0.62
	var ty: float = _n["ty"]
	var tc := Vector2(c.x, ty)
	if _fire("converge"):
		_fx.converge(tc + Vector2(0, 20), 54, T_FLASH * 0.95)
	## 蓄力: 冠军头像收成一颗光球
	var orb: Control = _n["orb"]
	orb.visible = t < T_FLASH
	var kc := UI.ease_in(UI.seg(t, 0.15, T_FLASH))
	orb.scale = Vector2.ONE * lerpf(1.0, 0.1, kc)
	orb.modulate = Color(1.0 + 2.2 * kc, 1.0 + 1.8 * kc, 1.0 + 1.0 * kc, 1.0)
	## 白闪(高潮) + 彩带三炮
	if t >= T_FLASH and _fire("flash"):
		_flash_now(T_FLASH)
		_fx.burst(tc + Vector2(0, 40), 70, 560.0)
		_fx.burst(Vector2(vp.x * 0.08, vp.y + 10), 36, 820.0)
		_fx.burst(Vector2(vp.x * 0.92, vp.y + 10), 36, 820.0)
		_fx.rain_rate = 7.0
	## 背光: 蓄力时淡淡地越转越快(能量在聚), 白闪之后整圈亮起、放慢
	_fx.rays_col = Color("#ffd772")
	_fx.rays_center = tc
	_fx.rays_radius = maxf(vp.x, vp.y) * 0.62
	if t < T_FLASH:
		_fx.rays_alpha = 0.22 * kc
		_fx.rays_speed = 0.4 + 3.2 * kc
	else:
		_fx.rays_alpha = 0.6 * UI.ease_out(UI.seg(t, T_FLASH, T_FLASH + 0.4))
		_fx.rays_speed = 0.35
	## 奖杯从光里升起: 先小后冲过头再落定, 之后轻轻浮动
	var tr: Control = _n["trophy"]
	var kt := UI.seg(t, T_FLASH, T_FLASH + 0.45)
	tr.modulate.a = 1.0 if t >= T_FLASH else 0.0
	tr.scale = Vector2.ONE * (0.4 + 0.6 * UI.ease_back(kt))
	var bob := sin((t - 1.5) * 2.4) * 4.0 if t > 1.5 else 0.0
	tr.position.y = roundf(ty - tr.size.y * 0.5 + 70.0 * (1.0 - UI.ease_out(kt)) + bob)   # 整像素: 浮动时不糊格子
	(_n["ped"] as Control).modulate.a = UI.seg(t, T_FLASH, T_FLASH + 0.25)
	## 「冠军」大字砸下(从 2.2 倍落到 1 倍) + 落定那一下屏震
	var big: Control = _n["big"]
	var kb := UI.seg(t, 1.45, 1.7)
	big.modulate.a = kb
	big.scale = Vector2.ONE * lerpf(2.2, 1.0, UI.ease_out(kb))
	var ks := UI.seg(t, 1.7, 1.9)
	_stage.position = Vector2(sin(t * 90.0) * 5.0 * (1.0 - ks), 0.0) if (t >= 1.7 and ks < 1.0) else Vector2.ZERO
	## 名字缎带落下 → 规模 + 届数日期
	var bn: Control = _n["banner"]
	var kn := UI.seg(t, 1.75, 2.1)
	bn.modulate.a = kn
	bn.position.y = float(_n["banner_y"]) - 40.0 * (1.0 - UI.ease_back(kn))
	(_n["l1"] as Control).modulate.a = UI.seg(t, 2.0, 2.3)
	(_n["l2"] as Control).modulate.a = UI.seg(t, 2.1, 2.45)


# ═══════════════════════════════════════════════════════════════════
#  ④ 夺冠阵容逐只特写
# ═══════════════════════════════════════════════════════════════════
func _build_lineup() -> void:
	var ids := lineup()
	UI.label_in(_stage, Rect2(0, c.y - 262, vp.x, 52), "夺冠阵容", 36, UI.GOLD, true, "LineupTitle")
	UI.label_in(_stage, Rect2(0, c.y - 214, vp.x, 30), "%s 的三统领" % str((data.get("champion", {}) as Dictionary).get("name", "")),
		20, UI.TXT_DIM, false, "LineupSub")
	var n := ids.size()
	var gap := minf(380.0, (vp.x - 100.0) / maxf(1.0, float(n)))
	var foot_y := c.y + 118.0
	var items: Array = []
	for i in range(n):
		var id := str(ids[i])
		var rar := UI.pet_rarity(id)
		var col: Color = UI.RARITY.get(rar, UI.BRONZE)
		var x := c.x + (float(i) - float(n - 1) * 0.5) * gap
		var slot := Control.new()
		slot.name = "Turtle%d" % i
		slot.size = Vector2(gap, 330)
		slot.position = Vector2(x - gap * 0.5, foot_y - 262)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(slot)
		var foot := Vector2(gap * 0.5, 262)
		var sh := UI.shadow(slot, foot + Vector2(0, 2), 86)
		var bd := UI.body(slot, foot, 210.0, id, "BodyHolder")
		UI.label_in(slot, Rect2(0, 270, gap, 40), UI.pet_name(id), 36, UI.TXT, true, "TurtleName%d" % i)
		var chip := UI.label_in(slot, Rect2(0, 306, gap, 26), rar, 22, col, false, "Rarity")
		chip.add_theme_constant_override("outline_size", 5)
		items.append({"slot": slot, "body": bd, "shadow": sh, "foot": slot.position + foot, "y0": bd.position.y})
	_n["items"] = items


## 逐只从上方落到自己的位置(落地压扁一下 + 扬尘 + 一下亮), 落定后待机帧一直在走; 三只的位置一开始就是最终那一排(居中)。
func _apply_lineup(t: float) -> void:
	_fx.rays_center = Vector2(c.x, c.y)
	_fx.rays_alpha = 0.26
	_fx.rays_speed = 0.3
	var per: float = float(beats[beat_i].get("per", 0.55))
	var items: Array = _n["items"]
	for i in range(items.size()):
		var it: Dictionary = items[i]
		var slot: Control = it["slot"]
		var ti := 0.35 + per * float(i)
		if t < ti:
			slot.visible = false
			continue
		slot.visible = true
		var lt := t - ti
		var bd: Control = it["body"]
		var kd := UI.seg(lt, 0.0, 0.22)
		bd.position.y = float(it["y0"]) - 300.0 * (1.0 - UI.ease_in(kd))
		var ks := UI.seg(lt, 0.22, 0.44)
		var sq := sin(PI * ks) if ks > 0.0 and ks < 1.0 else 0.0
		bd.scale = Vector2(1.0 + 0.12 * sq, 1.0 - 0.16 * sq)
		var fl := 1.0 - UI.seg(lt, 0.22, 0.42)
		bd.modulate = Color(1.0 + 1.6 * fl * float(lt >= 0.22), 1.0 + 1.6 * fl * float(lt >= 0.22), 1.0 + 1.4 * fl * float(lt >= 0.22), 1.0)
		if lt >= 0.22 and _fire("land%d" % i):
			_fx.dust(it["foot"], 18, 170.0)
		UI.body_step(bd, lt)
		(it["shadow"] as Control).modulate.a = UI.seg(lt, 0.0, 0.22)
		for nm in ["TurtleName%d" % i, "Rarity"]:
			var l := slot.find_child(nm, false, false) as Control
			if l != null:
				l.modulate.a = UI.seg(lt, 0.26, 0.46)


# ═══════════════════════════════════════════════════════════════════
#  ⑤ 夺冠之路
# ═══════════════════════════════════════════════════════════════════
func _build_path() -> void:
	var rows := path_rows()
	UI.label_in(_stage, Rect2(0, c.y - 262, vp.x, 52), "夺冠之路", 36, UI.GOLD, true, "PathTitle")
	var w := minf(vp.x - 200.0, 1120.0)
	var rh := 100.0
	var gap := 18.0
	var y0 := c.y + 24.0 - (rh * rows.size() + gap * (rows.size() - 1)) * 0.5
	var items: Array = []
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		var pl := UI.plate(_stage, Rect2(c.x - w * 0.5, y0 + i * (rh + gap), w, rh), UI.BRONZE, UI.PLATE, "PathRow%d" % i)
		UI.label_in(pl, Rect2(26, 0, 230, rh), str(r.get("round", "")), 36, UI.GOLD, true, "PathRound%d" % i, HORIZONTAL_ALIGNMENT_LEFT)
		if bool(r.get("bye", false)):
			UI.label_in(pl, Rect2(270, 0, w - 600, rh), "轮空晋级", 36, UI.TXT_DIM, true, "PathFoe%d" % i, HORIZONTAL_ALIGNMENT_LEFT)
		else:
			UI.label_in(pl, Rect2(262, 0, 40, rh), "对", 28, UI.TXT_DIM, false, "", HORIZONTAL_ALIGNMENT_LEFT)
			UI.portrait(pl, Vector2(350, rh * 0.5), 80, str(r.get("foe_avatar", "")), UI.BRONZE_HI, "PathFoeFace%d" % i)
			UI.label_in(pl, Rect2(408, 0, w - 408 - 340, rh), str(r.get("foe", "")), 36, UI.TXT, true, "PathFoe%d" % i, HORIZONTAL_ALIGNMENT_LEFT)
			var sc: Array = r.get("score", [])
			if sc.size() == 2:
				UI.label_in(pl, Rect2(w - 320, 0, 180, rh), "%d : %d" % [int(sc[0]), int(sc[1])], 48, UI.TXT, true, "PathScore%d" % i)
		var stamp := Control.new()
		stamp.name = "PathWin%d" % i
		stamp.size = Vector2(96, 96)
		stamp.pivot_offset = Vector2(48, 48)
		stamp.position = Vector2(w - 122, (rh - 96) * 0.5)
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pl.add_child(stamp)
		UI.tex_at(stamp, UI.TEX_MEDAL, Vector2(48, 48), Vector2(96, 96))
		UI.label_in(stamp, Rect2(0, 8, 96, 60), "胜", 36, Color("#5a3200"), true)
		items.append({"row": pl, "stamp": stamp})
	_n["items"] = items
	_n["w"] = w


## 每一行像盖章一样砸下来(1.3 倍 → 1 倍 + 扬尘 + 轻震), 再盖「胜」章(2.4 倍 → 1 倍回弹)。
func _apply_path(t: float) -> void:
	_fx.rays_alpha = 0.16
	var step: float = float(beats[beat_i].get("step", 0.45))
	var items: Array = _n["items"]
	var shake := 0.0
	for i in range(items.size()):
		var ti := 0.4 + step * float(i)
		var row: Control = items[i]["row"]
		row.visible = t >= ti
		var k := UI.seg(t, ti, ti + 0.16)
		row.scale = Vector2.ONE * lerpf(1.3, 1.0, UI.ease_out(k))
		row.modulate.a = k
		if t >= ti + 0.16 and _fire("row%d" % i):
			_fx.dust(row.position + Vector2(row.size.x * 0.5, row.size.y), 22, float(_n["w"]) * 0.45)
		var after := t - (ti + 0.16)
		if after >= 0.0 and after < 0.12:
			shake = maxf(shake, 1.0 - after / 0.12)
		var st: Control = items[i]["stamp"]
		var ks := UI.seg(t, ti + 0.2, ti + 0.34)
		st.modulate.a = ks
		st.scale = Vector2.ONE * lerpf(2.4, 1.0, UI.ease_back(ks))
	_stage.position = Vector2(sin(t * 95.0) * 4.0 * shake, 0.0) if shake > 0.0 else Vector2.ZERO


# ═══════════════════════════════════════════════════════════════════
#  ⑥ 今晚之最
# ═══════════════════════════════════════════════════════════════════
func _build_bests() -> void:
	var bs := bests()
	UI.label_in(_stage, Rect2(0, c.y - 262, vp.x, 52), "今晚之最", 36, UI.GOLD, true, "BestsTitle")
	var cw := 330.0
	var chh := 250.0
	var gap := 28.0
	var x0 := c.x - (cw * bs.size() + gap * (bs.size() - 1)) * 0.5
	var items: Array = []
	for i in range(bs.size()):
		var b: Dictionary = bs[i]
		var pl := UI.plate(_stage, Rect2(x0 + i * (cw + gap), c.y - chh * 0.5 + 20, cw, chh), UI.GOLD_DEEP, UI.PLATE, "Best%d" % i)
		UI.box(pl, Rect2(3, 3, cw - 6, 40), UI.PLATE_HEAD)
		UI.label_in(pl, Rect2(0, 3, cw, 40), str(b.get("title", "")), 22, UI.GOLD, false, "BestTitle%d" % i)
		var tid := str(b.get("turtle", ""))
		if tid != "":
			UI.portrait(pl, Vector2(64, 104), 76, tid, UI.RARITY.get(UI.pet_rarity(tid), UI.BRONZE), "BestFace%d" % i)
		var vl := UI.label_in(pl, Rect2(110 if tid != "" else 0, 66, cw - (120 if tid != "" else 0), 72), str(b.get("value", "")),
			48, UI.TXT, true, "BestValue%d" % i)
		UI.label_in(pl, Rect2(12, 150, cw - 24, 34), str(b.get("who", "")), 26, UI.GOLD, false, "BestWho%d" % i)
		var sub := UI.label_in(pl, Rect2(12, 186, cw - 24, 56), str(b.get("sub", "")), 18, UI.TXT_DIM, false, "BestSub%d" % i)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		items.append({"card": pl, "value": vl, "b": b})
	_n["items"] = items


func _apply_bests(t: float) -> void:
	_fx.rays_alpha = 0.18
	var items: Array = _n["items"]
	for i in range(items.size()):
		var ti := 0.45 + 0.35 * float(i)
		var card: Control = items[i]["card"]
		var k := UI.ease_out(UI.seg(t, ti, ti + 0.24))
		card.scale = Vector2(maxf(0.02, k), 1.0)
		card.modulate.a = 1.0 if t >= ti else 0.0
		## 数字滚出来(不是直接出现)
		var b: Dictionary = items[i]["b"]
		var kr := UI.seg(t, ti + 0.2, ti + 0.8)
		var vl: Label = items[i]["value"]
		if b.has("value_sec"):
			vl.text = DATA.mmss(float(b["value_sec"]) * kr) if kr < 1.0 else str(b.get("value", ""))
		elif b.has("value_num"):
			vl.text = str(int(round(float(b["value_num"]) * kr))) if kr < 1.0 else str(b.get("value", ""))


# ═══════════════════════════════════════════════════════════════════
#  ⑦ 冠军定格卡(常驻)
# ═══════════════════════════════════════════════════════════════════
func _build_card() -> void:
	var cup := is_cup()
	var ch: Dictionary = data.get("champion", {})
	var w := minf(vp.x - 100.0, 1080.0)
	var h := minf(vp.y - 60.0, 600.0)
	var card := Control.new()
	card.name = "ChampionCard"
	card.size = Vector2(w, h)
	card.position = c - card.size * 0.5
	card.pivot_offset = card.size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(card)
	_n["card"] = card
	## 框: 新出的冠军卡框(九宫格); 缺图退回金边像素牌
	UI.box(card, Rect2(10, 10, w - 20, h - 20), Color("#17111a"), "CardBody")
	var ft := UI.tex(UI.TEX_FRAME)
	if ft != null:
		var np := NinePatchRect.new()
		np.name = "CardFrame"
		np.texture = ft
		np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var m := int(ft.get_width() * 0.28)
		np.patch_margin_left = m
		np.patch_margin_right = m
		np.patch_margin_top = m
		np.patch_margin_bottom = m
		np.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
		np.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
		np.size = Vector2(w, h)
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(np)
	else:
		UI.plate(card, Rect2(0, 0, w, h), UI.GOLD_DEEP, Color("#17111a"), "CardFrame")
	## 左栏: 奖杯(组冠军: 奖章) + 台座 + 缎带
	var lx := 200.0
	_n["trophy_c"] = Vector2(lx, 196)
	if cup:
		UI.tex_at(card, UI.TEX_PEDESTAL, Vector2(lx, 300), Vector2(256, 128), "CardPedestal")
		_n["trophy"] = UI.tex_at(card, UI.TEX_TROPHY, Vector2(lx, 196), Vector2(192, 192), "CardTrophy")
	else:
		_n["trophy"] = UI.tex_at(card, UI.TEX_MEDAL, Vector2(lx, 220), Vector2(192, 192), "CardTrophy")
	UI.ribbon(card, Vector2(lx, 406), 320, "冠军杯赛冠军" if cup else str(data.get("group", "")) + "冠军", 36,
		"gold" if cup else "red", "CardRibbon")
	## 右栏
	var rx := 390.0
	var rw := w - rx - 50.0
	var ed := DATA.edition_line(int(data.get("week", 0)), int(data.get("edition", -1)))
	UI.label_in(card, Rect2(rx, 36, rw, 28), (_P2C.STAGE_CUP + "　" + ed) if cup else ed, 20, UI.TXT_DIM, false, "CardEdition",
		HORIZONTAL_ALIGNMENT_LEFT)
	UI.label_in(card, Rect2(rx, 64, rw, 60), str(ch.get("name", "")), 48, UI.GOLD, true, "CardName", HORIZONTAL_ALIGNMENT_LEFT)
	## 一行一件事: 来历(冠军杯) / 参赛规模; 头衔一行
	var scale := ("%d 人参赛" % int(data["entrants"])) if int(data.get("entrants", 0)) > 0 else ""
	if str(ch.get("origin", "")) != "" and cup:
		scale = str(ch["origin"]) + (("（%s）" % scale) if scale != "" else "")
	## 组冠军: 这一行写去向(「晋级冠军杯赛（19:00 开赛）」), 规模那一组只有几个人不值一行
	if not cup and str(data.get("next_text", "")) != "":
		scale = str(data["next_text"])
	UI.label_in(card, Rect2(rx, 124, rw, 30), scale, 24, UI.TXT, false, "CardScale", HORIZONTAL_ALIGNMENT_LEFT)
	var tl := "获得「%s」头衔（%s）" % ["冠军" if cup else "组冠军", DATA.title_until_line()]
	UI.label_in(card, Rect2(rx, 156, rw, 30), tl, 22, UI.GOLD, false, "CardTitleLine", HORIZONTAL_ALIGNMENT_LEFT)
	## 夺冠阵容(小)
	var ids := lineup()
	if not ids.is_empty():
		UI.label_in(card, Rect2(rx, 196, rw, 24), "夺冠阵容", 18, UI.TXT_DIM, false, "CardLineupHead", HORIZONTAL_ALIGNMENT_LEFT)
		for i in range(ids.size()):
			var id := str(ids[i])
			UI.portrait(card, Vector2(rx + 44 + i * 112, 266), 80, id, UI.RARITY.get(UI.pet_rarity(id), UI.BRONZE), "CardTurtle%d" % i)
			UI.label_in(card, Rect2(rx - 8 + i * 112, 308, 104, 26), UI.pet_name(id), 18, UI.TXT, false, "CardTurtleName%d" % i)
	## 夺冠之路(小)
	var rows := path_rows()
	var py := 344.0 if not ids.is_empty() else 200.0
	if not rows.is_empty():
		UI.label_in(card, Rect2(rx, py, rw, 24), "夺冠之路", 18, UI.TXT_DIM, false, "CardPathHead", HORIZONTAL_ALIGNMENT_LEFT)
		for i in range(rows.size()):
			var r: Dictionary = rows[i]
			var sc: Array = r.get("score", [])
			var line := "%s　%s" % [str(r.get("round", "")), "轮空晋级" if bool(r.get("bye", false)) else "对 " + str(r.get("foe", ""))]
			if sc.size() == 2:
				line += "　%d : %d" % [int(sc[0]), int(sc[1])]
			line += "　胜"
			UI.label_in(card, Rect2(rx, py + 26 + i * 30, rw, 28), line, 22, UI.TXT, false, "CardPath%d" % i, HORIZONTAL_ALIGNMENT_LEFT)
	## 按钮(落定后才出; 主按钮在右)
	var specs: Array = []
	var viewer_champ := bool(data.get("viewer_is_champion", false)) and not (data.get("rewards", []) as Array).is_empty()
	if cup:
		specs.append(["冠军墙", "BtnWall", false])
	if viewer_champ:
		specs.append(["领取奖励", "BtnClaim", true])
	else:
		specs.append(["关闭", "BtnClose", true])
	var bw := 220.0
	var bx := w - 46.0 - bw * specs.size() - 20.0 * (specs.size() - 1)
	var btns: Array = []
	for i in range(specs.size()):
		var sp: Array = specs[i]
		var b := UI.button(str(sp[0]), bw, str(sp[1]), bool(sp[2]))
		b.position = Vector2(bx + i * (bw + 20.0), h - UI.BTN_H - 30.0)
		b.visible = false
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(b)
		b.pressed.connect(_on_btn.bind(str(sp[1])))
		btns.append(b)
	_n["btns"] = btns
	_fx.rain_rate = 3.0


func _apply_card(t: float) -> void:
	var card: Control = _n["card"]
	var k := UI.seg(t, 0.0, 0.45)
	card.scale = Vector2.ONE * lerpf(0.86, 1.0, UI.ease_back(k))
	card.modulate.a = UI.seg(t, 0.0, 0.3)
	_stage.modulate.a = 1.0
	var tr: Control = _n["trophy"]
	var tc: Vector2 = _n["trophy_c"]
	tr.position.y = roundf(tc.y - tr.size.y * 0.5 + sin(t * 2.2) * 3.0)
	_fx.rays_col = Color("#ffd772")
	_fx.rays_center = c
	_fx.rays_radius = maxf(vp.x, vp.y) * 0.7
	_fx.rays_alpha = 0.32 * UI.seg(t, 0.1, 0.5)
	_fx.rays_speed = 0.18


func _show_buttons() -> void:
	for b in (_n.get("btns", []) as Array):
		(b as Button).visible = true
		(b as Button).mouse_filter = Control.MOUSE_FILTER_STOP


func _on_btn(id: String) -> void:
	match id:
		"BtnClose":
			close()
		"BtnWall":
			## 没人接就自己开冠军墙: 带了往届就直接画, 没带就自己按周去取(finals_week_view, 近 8 届)
			if wall_requested.get_connections().is_empty():
				var es: Array = data.get("wall_entries", []) if data.get("wall_entries", []) is Array else []
				var wl = load(WALL_PATH).create({"entries": es, "loading": es.is_empty()})
				get_parent().add_child(wl)
				wl.layer = layer + 1
				if es.is_empty():
					wl.load_weeks(int(data.get("week", 0)))
			wall_requested.emit()
		"BtnClaim":
			_open_rewards()


func _open_rewards() -> void:
	Audio.play_sfx("reward_rare")   # 冠军领奖(音效事件表; 2026-11-04 A5)
	var rd := {"pages": data.get("rewards", []), "coin_from": int(data.get("coin_from", -1))}
	if data.has("coin_target"):
		rd["coin_target"] = data["coin_target"]
	var rw = load(REWARDS_PATH).create(rd)
	get_parent().add_child(rw)
	rw.layer = layer + 1
	rw.finished.connect(_after_claim)


## 领完: 「领取奖励」换成「关闭」(同一个位置, 主按钮仍在右)。
func _after_claim() -> void:
	_claimed = true
	rewards_claimed.emit()
	for b in (_n.get("btns", []) as Array):
		var bb := b as Button
		if bb.name == "BtnClaim":
			bb.name = "BtnClose"
			bb.text = "关闭"
			for cn in bb.pressed.get_connections():
				bb.pressed.disconnect(cn["callable"])
			bb.pressed.connect(_on_btn.bind("BtnClose"))


func close() -> void:
	if _closed:
		return
	_closed = true
	finished.emit()
	queue_free()
