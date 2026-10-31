extends RefCounted
## finals_ctx.gd — 周日决赛日观战: 「这一场」是哪一项 / 哪一轮 / 第几场 / 谁对谁 / 下一场是谁(纯函数)。
## 方案书 docs/plans/20261031c-周日赛事界面重做.md §4 C 块(开场 VS / 结束分拍 / 出局卡 / 观战页都从这里取字)。
##
## ══════════════════════════════════════════════════════════════════════
##  入口约定: `ReplayRecorder.play_names`(对阵图点开一场时给; 原有的 l / r / pair 不变, 下面是 C 块加的键)
## ══════════════════════════════════════════════════════════════════════
##   "me"    : 我是 pair 里第几个(-1 = 我不在这一场 = 看别人)
##   "stage" : {cup, group(组号 1 起; 冠军杯 = 0), round, rounds, round_name, next_name, match_i, match_n}
##   "next"  : 这一场之后下一场 {a, b, at(服务端 unix 秒; 0 = 未定), r, m}; 没有 = {}
##   "mini"  : 迷你对阵 {n(这一组人数), r, m}
##   "view"  : 对阵图那一页的标识(刚才在看哪一组, P16: 返回时回到它); "bucket": 组号(服务端)
##   "cards" : [左名牌, 右名牌](按 pair 的顺序) {origin「B 组冠军」或 group(冠军杯: 他是哪一组的冠军, 组号从 0 起), record「闯关 9 胜 2 负」, title「卫冕」}; 可缺
##   "srv_off": 服务端此刻 − 本机此刻(秒), 「下一场 X 后开播」用
## ★对阵图只需一行: `names.merge(FinalsCtx.from_bucket(cur(), r, m, srv_now(), _view))`(见 from_bucket)。
##   没给这些键(旧入口 / 战绩页 / 周六)⇒ 各屏退回不写那一项, 不编。

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _B := preload("res://scripts/gamedata/bracket.gd")
const _L := preload("res://scripts/gamedata/bracket_layout.gd")
const PS := preload("res://scripts/systems/replay/premiere_schedule.gd")
## 玩家看得见的组名一律「A 组 / B 组 …」, 唯一来源 ChampionData.group_name(组号从 0 起; 主会话 10-31 定)
const ChampionDataS := preload("res://scripts/scenes/bracket/champion_data.gd")

const LANES := ["top", "bottom", "final"]
## 三路灯下的小字用短名(全称「上路战场 / 下路战场 / 终极战场」写在路间幕布上, 用户 10-07)
const LANE_SHORT := {"top": "上路", "bottom": "下路", "final": "终极"}
const TXT_ORIGIN_CUP := "组冠军"          # 冠军杯的每一位都是组冠军(入口没给组号时的写法, 不编组号)
const TXT_LOCKED := "双方阵容已锁定 · 服务器实时演算"

## 出局卡「去看 X 对 Y」/ 看别人播完自动回对阵图时留给对阵图的跟播请求(对阵图进场时 `take_follow()` 读走):
##   {"view", "bucket", "r", "m", "at"(服务端 unix)}。对阵图进场时读走并清空; 到点就开那一场(与它自己那场「揭晓后自动播」同一个做法)。
static var follow: Dictionary = {}


## 对阵图一组(`SupabaseNet._bucket_from` 的形状)+ 点开的那一场 ⇒ play_names 要多带的键。纯函数。
##   名字取种子名(对阵图自己的 `competitor()` 另有拉黑 / 重名带号的处理 ⇒ 对阵图可以再用它的 pair 覆盖)。
static func from_bucket(b: Dictionary, r: int, m: int, now: int, view: String = "") -> Dictionary:
	var n := int(b.get("size", 0))
	if n < 2 or r < 1:
		return {}
	var done: Dictionary = b.get("done", {}) if b.get("done", {}) is Dictionary else {}
	var bk := int(b.get("bucket", -1))
	var cup := bk == P2C.FINALS_CUP_BUCKET
	var rounds := _B.rounds_for(n)
	var sa := _B.occupant_seed(r, m, 0, n, done)
	var sb := _B.occupant_seed(r, m, 1, n, done)
	var me_seed := int(b.get("me", -1))
	var me := -1
	if me_seed >= 0:
		me = 0 if sa == me_seed else (1 if sb == me_seed else -1)
	var st := {"cup": cup, "group": 0 if cup else bk + 1, "round": r, "rounds": rounds,
		"round_name": _L.round_label(n, r), "next_name": _L.round_label(n, r + 1) if r < rounds else ""}
	var ln: Array = PS.lineup(b, r)
	var idx := -1
	for i in range(ln.size()):
		if int(ln[i][0]) == m:
			idx = i
	if idx >= 0:
		st["match_i"] = idx + 1
		st["match_n"] = ln.size()
	var nx := {}
	if idx >= 0 and idx + 1 < ln.size():
		var m2 := int(ln[idx + 1][0])
		nx = _pair_at(b, r, m2, int(ln[idx + 1][1]))
	elif r < rounds:
		## 本轮最后一场 ⇒ 下一轮第一场(对手由 done 推出; 推不出 = 待定 ⇒ 不写)
		nx = _pair_at(b, r + 1, 0, 0)
	## 备战结束到翻面之间(premiere_schedule.settling): 时刻还没排出来 ⇒ 下一场条写「结算中 · 即将开播」
	if not nx.is_empty() and int(nx.get("at", 0)) <= 0 and PS.settling(b, now):
		nx["settling"] = true
	var out := {"pair": [_seed_name(b, sa), _seed_name(b, sb)], "me": me, "stage": st, "next": nx,
		"mini": {"n": n, "r": r, "m": m}, "view": view, "bucket": bk}
	if now > 0:
		out["srv_off"] = now - int(Time.get_unix_time_from_system())
	return out


static func _seed_name(b: Dictionary, sd: int) -> String:
	var names: Array = b.get("names", []) if b.get("names", []) is Array else []
	return str(names[sd]) if sd >= 0 and sd < names.size() else ""


static func _pair_at(b: Dictionary, r: int, m: int, at: int) -> Dictionary:
	var n := int(b.get("size", 0))
	var done: Dictionary = b.get("done", {}) if b.get("done", {}) is Dictionary else {}
	var a := _seed_name(b, _B.occupant_seed(r, m, 0, n, done))
	var c := _seed_name(b, _B.occupant_seed(r, m, 1, n, done))
	if a == "" or c == "":
		return {}
	return {"a": a, "b": c, "at": at, "r": r, "m": m}


## 入口给的轮次(没给 / 形状不对 = {})。
static func stage_of(pn: Dictionary) -> Dictionary:
	var st = pn.get("stage", {})
	return st if st is Dictionary else {}


## 是周日决赛日的一场吗(入口给了冠军杯或组号)。
static func is_finals(pn: Dictionary) -> bool:
	var st := stage_of(pn)
	return bool(st.get("cup", false)) or int(st.get("group", 0)) > 0


## 冠军杯决赛(整套换金; 结束时交给冠军仪式)。
static func is_cup_final(st: Dictionary) -> bool:
	return bool(st.get("cup", false)) and int(st.get("rounds", 0)) > 0 and int(st.get("round", 0)) == int(st.get("rounds", 0))


## 开场 VS 顶上那一行: 「冠军杯赛 · 半决赛」/「小组赛 · B 组 · 半决赛」。没给 = ""。
static func round_title(st: Dictionary) -> String:
	var rn := str(st.get("round_name", ""))
	var tail := (" · " + rn) if rn != "" else ""
	if bool(st.get("cup", false)):
		return P2C.STAGE_CUP + tail
	if int(st.get("group", 0)) > 0:
		return "%s · %s%s" % [P2C.STAGE_GROUP, ChampionDataS.group_name(int(st["group"]) - 1), tail]
	return ""


## 观战页角落的阶段标签: 轮次 + 「第 1 / 2 场」(这一轮只有一场时不写场次)。
static func stage_tag(st: Dictionary) -> String:
	var t := round_title(st)
	if t == "":
		return ""
	var mi := int(st.get("match_i", 0))
	var mn := int(st.get("match_n", 0))
	if mi >= 1 and mn > 1:
		t += " · 第 %d / %d 场" % [mi, mn]
	return t


## 「去看 X 对 Y」(出局卡 / 轮空的主按钮, G25); 下一场没定 = ""。
static func go_label(nx: Dictionary) -> String:
	if str(nx.get("a", "")) == "" or str(nx.get("b", "")) == "":
		return ""
	return "去看 %s 对 %s" % [str(nx["a"]), str(nx["b"])]


## 下一场条: 「下一场 X 对 Y · 20:14」(时刻按设备时区; 结算中 ⇒ 「· 结算中 · 即将开播」; 没排上时刻只写对阵)。
static func next_line(nx: Dictionary) -> String:
	if str(nx.get("a", "")) == "" or str(nx.get("b", "")) == "":
		return ""
	var t := "下一场  %s 对 %s" % [str(nx["a"]), str(nx["b"])]
	var at := int(nx.get("at", 0))
	if at > 0:
		t += " · " + P2C.local_hhmm(at)
	elif bool(nx.get("settling", false)):
		t += " · " + PS.TXT_SETTLE
	return t


## 出局卡那一句(G18): 「止步半决赛 · 输给 X」; 没给轮次 ⇒ 「输给 X」。
static func out_line(st: Dictionary, foe: String) -> String:
	var rn := str(st.get("round_name", ""))
	var head := ("止步" + rn) if rn != "" else ""
	if foe == "":
		return head
	return (head + " · 输给 " + foe) if head != "" else ("输给 " + foe)


## 名牌下的来历: 入口给的字优先; 给了组号 ⇒「B 组冠军」(组名 ChampionData.group_name); 冠军杯都没给 ⇒「组冠军」
##   (冠军杯每一位都是组冠军, 说的是实话); 小组赛没给 ⇒ ""。
static func origin_of(card: Dictionary, st: Dictionary) -> String:
	var o := str(card.get("origin", ""))
	if o != "":
		return o
	if card.has("group") and int(card["group"]) >= 0 and bool(st.get("cup", false)):
		return ChampionDataS.group_name(int(card["group"])) + "冠军"
	return TXT_ORIGIN_CUP if bool(st.get("cup", false)) else ""


## 左右名牌(按录像左右排; 入口的 cards 按 pair 的顺序给)。`names` = {"l", "r"}。
static func side_cards(pn: Dictionary, names: Dictionary) -> Dictionary:
	var cards = pn.get("cards", [])
	var pair = pn.get("pair", [])
	var out := {"left": {}, "right": {}}
	if not (cards is Array) or not (pair is Array) or (pair as Array).size() != 2 or (cards as Array).size() != 2:
		return out
	for i in range(2):
		var c = cards[i]
		if not (c is Dictionary):
			continue
		var nm := str(pair[i])
		if nm != "" and nm == str(names.get("l", "")):
			out["left"] = c
		elif nm != "" and nm == str(names.get("r", "")):
			out["right"] = c
	return out


## 剩余总血量(拔河条): 单位表里活着的按左右加起来。播到哪算到哪(单位表就是此刻屏上那一路)。返回 [左, 右]。
static func tug(units: Array) -> Array:
	var l := 0.0
	var r := 0.0
	for u in units:
		if not (u is Dictionary) or not bool((u as Dictionary).get("alive", false)):
			continue
		var hp := maxf(0.0, float((u as Dictionary).get("hp", 0.0)))
		var sd := str((u as Dictionary).get("side", ""))
		if sd == "left":
			l += hp
		elif sd == "right":
			r += hp
	return [l, r]


## 拔河条左边占几成(0..1); 两边都没血 = 0.5。
static func tug_frac(lr: Array) -> float:
	var s := float(lr[0]) + float(lr[1])
	return 0.5 if s <= 0.0 else clampf(float(lr[0]) / s, 0.0, 1.0)


## 三路灯: [[路, 赢家 "left"/"right"/""(没打完), 正在打?], …](上路 → 下路 → 终极)。只读各路结果, 不预告(G19 不剧透)。
static func lamps(lane_results: Dictionary, cur_lane: String) -> Array:
	var out: Array = []
	for ln in LANES:
		var w := str(lane_results.get(ln, ""))
		if w != "left" and w != "right":
			w = ""
		out.append([ln, w, w == "" and ln == cur_lane])
	return out


## 比分 [左, 右] = 各自赢下的路数。
static func lamp_score(lp: Array) -> Array:
	var s := [0, 0]
	for it in lp:
		if str(it[1]) == "left":
			s[0] += 1
		elif str(it[1]) == "right":
			s[1] += 1
	return s


## 一边的阵容(开场 VS / 结束第二拍): 规格表 → [{pid, minion}](上路在前, 下路在后)。
static func lineup_pids(specs: Array) -> Array:
	var out: Array = []
	for s in specs:
		if not (s is Dictionary):
			continue
		var d: Dictionary = s
		var minion := str(d.get("kind", "")) == "minion" or d.has("role")
		var pid := "" if minion else str(d.get("id", ""))
		out.append({"pid": pid, "minion": minion, "kind": MinionCodex.kind_of(d) if minion else ""})
	return out


## ── 字: 像素标题字(12 的整数倍; 描边 = 字号 ÷ 3 ⇒ 每边一个源像素, verify_title_font)。开场 / 结束 / 观战页共用一份。
const COL_INK := Color("#070b16")


static func title_lbl(txt: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match fs:
		96:
			UISkin.title_label(l, 96)
			l.add_theme_constant_override("outline_size", 32)
		72:
			UISkin.title_label(l, 72)
			l.add_theme_constant_override("outline_size", 24)
		48:
			UISkin.title_label(l, 48)
			l.add_theme_constant_override("outline_size", 16)
		36:
			UISkin.title_label(l, 36)
			l.add_theme_constant_override("outline_size", 12)
		_:
			UISkin.title_label(l, 24)
			l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", COL_INK)
	return l


## 深色描边(没有底板, 字要自己立得住)。
static func outline(l: Label, w: int) -> void:
	l.add_theme_color_override("font_outline_color", COL_INK)
	l.add_theme_constant_override("outline_size", w)


## ── 动效曲线(开场 / 结束 / 观战页共用一份)。★只用 + − × ÷: 本目录按 sim 文件扫(tools/det_math_lint.py),
##   sin / pow / lerpf 一律不许裸调; 画面用不着三角函数, 呼吸用三角波。
static func k01(x: float, t0: float, dur: float) -> float:
	return clampf((x - t0) / dur, 0.0, 1.0)


static func ease_out(x: float) -> float:
	var u := 1.0 - x
	return 1.0 - u * u * u


static func ease_back(x: float) -> float:
	var u := x - 1.0
	return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u


static func mix(a: float, b: float, w: float) -> float:
	return a + (b - a) * w


## 三角波: 每 1 个单位 0 → 1 → 0。
static func wave(x: float) -> float:
	var f := x - floorf(x)
	return 1.0 - absf(2.0 * f - 1.0)


## 光芒的 8 个方向(单位向量)与各自的法向: 写死, 不在运行时算角度(本目录不许裸调 sin / cos)。
const RAY_DIRS := [Vector2(1, 0), Vector2(0.7071, 0.7071), Vector2(0, 1), Vector2(-0.7071, 0.7071),
	Vector2(-1, 0), Vector2(-0.7071, -0.7071), Vector2(0, -1), Vector2(0.7071, -0.7071)]
const RAY_SIDE := [Vector2(0, 1), Vector2(-0.7071, 0.7071), Vector2(-1, 0), Vector2(-0.7071, -0.7071),
	Vector2(0, -1), Vector2(0.7071, -0.7071), Vector2(1, 0), Vector2(0.7071, 0.7071)]


## ── 大字美术字(结算屏同一套做法: 大格子像素字 + 描边 + 渐变 + 落影, memory project-big-title-art-1027)。
##   这几屏自己的那几张在 assets/sprites/finals/bt-*.png(生成脚本见方案书 C 块记录; 与 tools/build_big_titles.py 同一个栅格化 / 渐变)。
##   「胜利」仍走 BigTitle.BIG(普通结算那一张, 不另出一份)。
const ART_DIR := "res://assets/sprites/finals/"
const ART_SCALE := 3
const ART_NODE := "FinalsArt"
const ART := {"惜败": "bt-xibai", "开战": "bt-kaizhan", "获胜": "bt-huosheng",
	"晋级决赛": "bt-adv-final", "晋级半决赛": "bt-adv-semi", "晋级8强": "bt-adv-8", "晋级16强": "bt-adv-16",
	"晋级冠军杯赛": "bt-adv-cup", "冠军杯赛冠军": "bt-cup-champ",
	"上路战场": "bt-lane-top", "下路战场": "bt-lane-bottom", "终极战场": "bt-lane-final"}


## 一张美术字(×3 最近邻, 不吃点击)。没有这张图 ⇒ null。
static func art_rect(file: String) -> TextureRect:
	var p := ART_DIR + file + ".png"
	if not ResourceLoader.exists(p):
		return null
	var tr := TextureRect.new()
	tr.name = ART_NODE
	tr.texture = load(p)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = tr.texture.get_size() * ART_SCALE
	return tr


## 给标签贴上它那句话的美术字: 标签的字保留(门禁 / 读屏读 text)、自己透明, 图挂成子节点居中。返回 true = 贴上了。
static func dress_art(l: Label) -> bool:
	if not ART.has(l.text):
		return false
	var art := art_rect(str(ART[l.text]))
	if art == null:
		return false
	l.add_child(art)
	l.self_modulate.a = 0.0
	var sz := art.size
	var center := func() -> void:
		if is_instance_valid(art) and is_instance_valid(l):
			art.position = ((l.size - sz) / 2.0).floor()
	l.resized.connect(center)
	center.call()
	return true


## 比分数字(0~3)美术字: 领先 / 赢的一边金色, 另一边冷灰。标签的 text 照旧是数字。
static func set_digit(l: Label, v: int, gold: bool) -> void:
	l.text = str(v)
	var file := ("bt-n%d" if gold or v > 2 else "bt-g%d") % clampi(v, 0, 3)
	var art := l.get_node_or_null(ART_NODE) as TextureRect
	if art == null:
		art = art_rect(file)
		if art == null:
			return
		l.add_child(art)
		l.self_modulate.a = 0.0
	elif art.texture == null or art.texture.resource_path.get_file() != file + ".png":
		art.texture = load(ART_DIR + file + ".png")
		art.size = art.texture.get_size() * ART_SCALE
	art.position = ((l.size - art.size) / 2.0).floor()


## 底纹: 斜向细条(每 step 像素一条 2px), 只画在 r 里。硬边, 不做渐变。
static func draw_hatch(c: CanvasItem, r: Rect2, col: Color, step: float) -> void:
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(maxf(x, r.position.x), r.position.y + maxf(0.0, r.position.x - x))
		var b := Vector2(minf(x + r.size.y, r.end.x), r.end.y - maxf(0.0, x + r.size.y - r.end.x))
		if a.y < b.y:
			c.draw_line(a, b, col, 2.0)
		x += step


## 光芒(8 道, 方向写死): 从 ctr 往外, 半径 rr, 宽 w。
static func draw_rays(c: CanvasItem, ctr: Vector2, rr: float, w: float, col: Color) -> void:
	for i in range(RAY_DIRS.size()):
		var d: Vector2 = RAY_DIRS[i]
		var n: Vector2 = RAY_SIDE[i]
		c.draw_colored_polygon(PackedVector2Array([ctr + n * (w * 0.1), ctr + d * rr + n * w, ctr + d * rr - n * w, ctr - n * (w * 0.1)]), col)


## 缎带(正身 + 两端压在后面的燕尾 + 折角暗块 + 2px 深描边)。body_h = 正身高; red = 红缎带(上面压金色美术字时用, 金压金看不清)。
static func draw_ribbon(c: CanvasItem, s: Vector2, body_h: float, red: bool = false) -> void:
	var e := 48.0
	var ink := Color("#2a0608") if red else Color("#2a1606")
	var tail := Color("#7c1c22") if red else Color("#a8661a")
	var fold := Color("#3e0a0e") if red else Color("#5c3408")
	var face := Color("#b02a30") if red else Color("#e0a526")
	var hi := Color("#e0605a") if red else Color("#ffd668")
	var lo := Color("#74161c") if red else Color("#b07418")
	var top := 12.0
	var bot := s.y - 2.0
	for flip in [false, true]:
		var pts := PackedVector2Array([Vector2(0, top), Vector2(e + 6.0, top), Vector2(e + 6.0, bot), Vector2(0, bot),
			Vector2(e * 0.42, (top + bot) * 0.5)])
		if flip:
			for i in range(pts.size()):
				pts[i] = Vector2(s.x - pts[i].x, pts[i].y)
		var out := PackedVector2Array(pts)
		out.append(pts[0])
		c.draw_colored_polygon(pts, tail)
		c.draw_polyline(out, ink, 2.0)
	var body := Rect2(e * 0.5, 0.0, s.x - e, body_h)
	c.draw_rect(body.grow(2.0), ink)
	c.draw_rect(body, face)
	c.draw_rect(Rect2(body.position.x, 2.0, body.size.x, 4.0), hi)
	c.draw_rect(Rect2(body.position.x, body_h - 8.0, body.size.x, 6.0), lo)
	if red:
		c.draw_rect(Rect2(body.position.x, 8.0, body.size.x, 2.0), Color("#ffd668"))
		c.draw_rect(Rect2(body.position.x, body_h - 12.0, body.size.x, 2.0), Color("#ffd668"))
	for flip in [false, true]:
		var fp := PackedVector2Array([Vector2(e * 0.5, body_h + 2.0), Vector2(e + 6.0, body_h + 2.0), Vector2(e + 6.0, bot)])
		if flip:
			for i in range(fp.size()):
				fp[i] = Vector2(s.x - fp[i].x, fp[i].y)
		c.draw_colored_polygon(fp, fold)


## ── 全局决赛日小条(autoload FinalsDay, scripts/ui/finals_day_layer.gd)在这几屏让路 / 停靠:
##   AVOID = 不是按钮、但不许被小条盖住的(比分条 / 阶段标签 / 下一场条 …);
##   DOCK  = 一块空 Control(大小 = 想让小条待的那块地), 小条居中贴在它上面。同一时刻只留一块看得见的停靠位。
const BAR_AVOID := "finals_bar_avoid"
const BAR_DOCK := "finals_bar_dock"
const BAR_W := 560.0                # = FinalsDay 的 BAR_MAX_W
const BAR_H := 48.0


static func bar_dock(nm: String, r: Rect2) -> Control:
	var d := Control.new()
	d.name = nm
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.position = r.position
	d.size = r.size
	d.add_to_group(BAR_DOCK)
	return d


## 全局决赛日小条此刻在不在场(autoload FinalsDay 的 bar 看得见)。只读。
static func bar_on() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var fd = tree.root.get_node_or_null("FinalsDay") if tree != null else null
	var b = fd.get("bar") if fd != null else null
	return b is CanvasItem and (b as CanvasItem).visible


## 换了一层(开场 VS 收掉 / 收尾出来 / 路间插卡进出)⇒ 让小条马上重新找停靠位(它自己每秒才找一次, 中间那一下会压在旧位置上)。
static func bar_nudge() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var fd = tree.root.get_node_or_null("FinalsDay") if tree != null else null
	if fd != null and bar_on() and fd.has_method("tick"):
		fd.tick()


static func bar_avoid(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n) and n is Node and not (n as Node).is_in_group(BAR_AVOID):
			(n as Node).add_to_group(BAR_AVOID)


## ── 叠层的每帧钟: 开场 VS / 收尾三拍 / 观战页那几样都是 RefCounted, 没有自己的 _process ——
##   在叠层根节点下挂一个只管转发的节点, 每帧把 `_process(delta)` 的 delta 交给 `obj._tick(dt)`(做法同 stream_source._Pump)。
##   ★不读 get_process_delta_time(): verify_determinism_b ⑧ 的静态棘轮扫整个 scripts/scenes/battle/(对局模拟路径),
##     演出要真实 delta 就从 _process 的参数拿。数值与原来一样(_process 的 delta 就是那个值), 暂停 / 录屏定帧率下也一样。
##   挂成内部子节点 ⇒ get_children / find_child 看不到它, 不打乱各屏的子节点顺序; 根一释放它跟着走; 叠层对象没了它自己退。
const TICKER_NODE := "FinalsTicker"


class Ticker extends Node:
	var obj: WeakRef = null

	func _process(dt: float) -> void:
		var o = obj.get_ref() if obj != null else null
		if o == null:
			queue_free()
			return
		o._tick(dt)


static func start_ticker(host: Node, obj: Object) -> Node:
	var tk := Ticker.new()
	tk.name = TICKER_NODE
	tk.obj = weakref(obj)
	tk.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(tk, false, Node.INTERNAL_MODE_BACK)
	return tk


## 停钟: 当场不再转发(这一帧里也不再调 _tick), 节点随后释放。形参不标类型: 根已释放时传进来的是失效实例。
static func stop_ticker(tk) -> void:
	if is_instance_valid(tk) and tk is Node:
		(tk as Node).set_process(false)
		(tk as Node).queue_free()


## 秒数 → 「1 分 05 秒」/「42 秒」。
static func span_text(sec: int) -> String:
	sec = maxi(0, sec)
	if sec >= 60:
		return "%d 分 %02d 秒" % [sec / 60, sec % 60]
	return "%d 秒" % sec
