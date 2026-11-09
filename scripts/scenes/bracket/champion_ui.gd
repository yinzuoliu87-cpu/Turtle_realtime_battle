class_name ChampionUi
extends RefCounted
## champion_ui.gd —— 冠军收盘这几层(ChampionShow / ChampionIntro / ChampionRewards / ChampionWall)共用的小件。
## 配色与对阵图试做(bracket_hero.gd)同一套夜晚竞技场暖色; 素材:
##   assets/sprites/bracket/  奖杯 / 红缎带 / 奖章 / 默认头像(周日专门出的, 直接复用)
##   assets/sprites/champion/ 金缎带 / 银缎带 / 冠军卡框 / 奖杯台座(这一路新出的)
## ★演出一律「按时间算状态」(给一个 t 就能画出那一刻), 不用 Tween —— 跳拍 = 把 t 拨到终点, 门禁也不依赖 tween 跑完(CLAUDE.md §3.5)。

const TEX_BG := "res://assets/sprites/bracket/bracket-bg-arena.png"
const TEX_TROPHY := "res://assets/sprites/bracket/bracket-trophy.png"
const TEX_RIBBON_RED := "res://assets/sprites/bracket/bracket-ribbon.png"
const TEX_MEDAL := "res://assets/sprites/bracket/bracket-medal.png"
const TEX_AVATAR_DEFAULT := "res://assets/sprites/bracket/bracket-avatar-default.png"
const TEX_RIBBON_GOLD := "res://assets/sprites/champion/champion-ribbon-gold.png"
const TEX_RIBBON_SILVER := "res://assets/sprites/champion/champion-ribbon-silver.png"
const TEX_FRAME := "res://assets/sprites/champion/champion-frame.png"
const TEX_PEDESTAL := "res://assets/sprites/champion/champion-pedestal.png"
const TEX_COIN := "res://assets/sprites/menu/ic-deepsea.png"    # 深海币: 与主菜单顶栏同一个图标(同一种货币)

const GOLD := Color("#f4c552")
const GOLD_DEEP := Color("#9a6a1c")
const SILVER := Color("#d6dde6")
const BRONZE := Color("#7a5d3e")
const BRONZE_HI := Color("#b48a58")
const PLATE := Color("#211a22")
const PLATE_HEAD := Color("#352823")
const INK := Color("#0b0809")
const TXT := Color("#f6ecd9")
const TXT_DIM := Color("#b3a493")
const WIN := Color("#7ee08a")

const BTN_H := 81.0
## 缎带字: [字色, 描边色]。金 / 银底都是中间调 ⇒ 浅字 + 近黑描边; 红底本身够深 ⇒ 奶油字 + 深红描边。
const RIBBON_INK := {
	"gold": [Color("#fff7e0"), Color("#2e1300")],
	"silver": [Color("#ffffff"), Color("#141a24")],
	"red": [Color("#fff1d6"), Color("#2a0606")],
}
const RIBBON_MIN_FS := 36          # 触屏按钮高(与观战收尾卡同一条: ≥ 81)
const RARITY := {
	"C": Color("#06d6a0"), "B": Color("#4cc9f0"), "A": Color("#3a9abf"),
	"S": Color("#c77dff"), "SS": Color("#ffd93d"), "SSS": Color("#ff6b6b"),
}


# ── 缓动 ──
static func seg(t: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0 if t >= b else 0.0
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


static func ease_in(x: float) -> float:
	return pow(clampf(x, 0.0, 1.0), 2.4)


static func ease_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var u := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u


# ── 贴图 ──
static func tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func avatar_path(id: String) -> String:
	if id != "":
		var p := "res://assets/sprites/avatars/%s.png" % id
		if ResourceLoader.exists(p):
			return p
	return TEX_AVATAR_DEFAULT


static func pet_name(id: String) -> String:
	var p: Dictionary = DataRegistry.pet_by_id.get(id, {})
	return str(p.get("name", id)) if not p.is_empty() else id


static func pet_rarity(id: String) -> String:
	var p: Dictionary = DataRegistry.pet_by_id.get(id, {})
	return str(p.get("rarity", "C")) if not p.is_empty() else "C"


static func tex_rect(path: String, sz: Vector2, nm: String = "") -> TextureRect:
	var tr := TextureRect.new()
	if nm != "":
		tr.name = nm
	tr.texture = tex(path)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size = sz
	tr.pivot_offset = sz * 0.5
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 中心放在 c 的贴图。
static func tex_at(parent: Control, path: String, c: Vector2, sz: Vector2, nm: String = "") -> TextureRect:
	var tr := tex_rect(path, sz, nm)
	tr.position = c - sz * 0.5
	parent.add_child(tr)
	return tr


static func box(parent: Control, r: Rect2, col: Color, nm: String = "") -> ColorRect:
	var cr := ColorRect.new()
	if nm != "":
		cr.name = nm
	cr.color = col
	cr.position = r.position
	cr.size = Vector2(maxf(r.size.x, 1.0), maxf(r.size.y, 1.0))
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cr)
	return cr


## 一块硬边像素牌: 墨线 + 青铜边 + 上沿高光 + 卡身。返回卡身(内容往里放)。
static func plate(parent: Control, r: Rect2, edge: Color = BRONZE, body: Color = PLATE, nm: String = "") -> Control:
	var holder := Control.new()
	if nm != "":
		holder.name = nm
	holder.position = r.position
	holder.size = r.size
	holder.pivot_offset = r.size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	box(holder, Rect2(Vector2(-3, -3), r.size + Vector2(6, 6)), INK)
	box(holder, Rect2(Vector2.ZERO, r.size), edge)
	box(holder, Rect2(Vector2(3, 3), r.size - Vector2(6, 6)), body)
	box(holder, Rect2(Vector2(3, 3), Vector2(r.size.x - 6, 2)), edge.lightened(0.25))
	return holder


# ── 字 ──
## `title` = 像素标题字(`UISkin.title_font()`, 缝合像素 12px)。三条像素格规矩(verify_title_font 同一套, 本层门禁逐个量):
##   字号是 12 的倍数(调用点都写成 24 / 36 / 48 / 60 / 72 / 96)、描边 = 字号 / 3(每边一个源像素)、落影偏移 = 字号 / 12。
## ★不走 UISkin 的 title_label 包一层传变量字号: 那条静态扫描读不出变量(会判红); 字号由调用点写死, 这里只挂字体。
const TITLE_STEP := 12


static func title_px(fs: int) -> int:
	return maxi(TITLE_STEP, (fs / TITLE_STEP) * TITLE_STEP)


static func label(t: String, fs: int, col: Color, outline: bool = true, title: bool = false, nm: String = "") -> Label:
	var lb := Label.new()
	if nm != "":
		lb.name = nm
	lb.text = t
	var px := fs
	if title:
		px = title_px(fs)
		var f := UISkin.title_font()
		if f != null:
			lb.add_theme_font_override("font", f)
	lb.add_theme_font_size_override("font_size", px)
	lb.add_theme_color_override("font_color", col)
	if outline:
		lb.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.02, 0.95))
		lb.add_theme_constant_override("outline_size", (px / 3) if title else maxi(4, px / 6))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


## 居中摆在矩形 r 里的一行字。
static func label_in(parent: Control, r: Rect2, t: String, fs: int, col: Color, title: bool = false,
		nm: String = "", align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var lb := label(t, fs, col, true, title, nm)
	lb.position = r.position
	lb.size = r.size
	lb.pivot_offset = r.size * 0.5
	lb.horizontal_alignment = align
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.clip_text = false
	parent.add_child(lb)
	return lb


## 缎带(金 / 银 / 红) + 中间一行字。中心放在 c。新素材缺失时退回红缎带, 再缺就是一条纯色带(不崩、不空白)。
static func ribbon(parent: Control, c: Vector2, w: float, t: String, fs: int, kind: String = "gold", nm: String = "") -> Control:
	var h := roundf(w * 0.25)
	var holder := Control.new()
	if nm != "":
		holder.name = nm
	holder.size = Vector2(w, h)
	holder.position = c - holder.size * 0.5
	holder.pivot_offset = holder.size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var path := TEX_RIBBON_GOLD if kind == "gold" else (TEX_RIBBON_SILVER if kind == "silver" else TEX_RIBBON_RED)
	if not ResourceLoader.exists(path):
		path = TEX_RIBBON_RED
	var tr := tex_rect(path, holder.size)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	holder.add_child(tr)
	if tr.texture == null:
		box(holder, Rect2(Vector2(0, h * 0.2), Vector2(w, h * 0.6)), GOLD_DEEP if kind == "gold" else Color("#5e6670"))
	## ★浅字 + 深描边 + 落影(主会话 10-31 逐帧审: 原来暗金字压金底「几乎读不出」)。判据在门禁: 字与描边对比 ≥ 7、
	##   描边(或字本身)与缎带本体对比 ≥ 4.5、字号 ≥ 36(手机 1560×720 一眼读得出)。
	var ink: Color = RIBBON_INK.get(kind, RIBBON_INK["red"])[0]
	var edge: Color = RIBBON_INK.get(kind, RIBBON_INK["red"])[1]
	var px := title_px(maxi(fs, RIBBON_MIN_FS))
	var lb := label(t, px, ink, false, true, "Text")
	lb.add_theme_color_override("font_outline_color", edge)
	lb.add_theme_constant_override("outline_size", px / 3)                 # 每边一个源像素(像素格上)
	lb.add_theme_color_override("font_shadow_color", Color(edge, 0.85))
	lb.add_theme_constant_override("shadow_offset_x", 0)
	lb.add_theme_constant_override("shadow_offset_y", px / TITLE_STEP)      # 往下一个源像素
	lb.position = Vector2(w * 0.12, h * 0.02)
	lb.size = Vector2(w * 0.76, h * 0.72)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(lb)
	return holder


## 头像框(墨线 + 边色 + 暗底 + 头像)。中心放在 c, 边长 s。
static func portrait(parent: Control, c: Vector2, s: float, avatar_id: String, edge: Color, nm: String = "") -> Control:
	var holder := Control.new()
	if nm != "":
		holder.name = nm
	holder.size = Vector2(s, s)
	holder.position = c - holder.size * 0.5
	holder.pivot_offset = holder.size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	box(holder, Rect2(Vector2(-4, -4), Vector2(s + 8, s + 8)), INK)
	box(holder, Rect2(Vector2(-2, -2), Vector2(s + 4, s + 4)), edge)
	box(holder, Rect2(Vector2(2, 2), Vector2(s - 4, s - 4)), Color("#120e12"))
	var tr := tex_rect(avatar_path(avatar_id), Vector2(s - 8, s - 8), "Face")
	tr.position = Vector2(4, 4)
	holder.add_child(tr)
	return holder


## 卡片里的动作钮: card_button 皮(用户 10-22 定死, 不用木牌)。
static func button(t: String, w: float, nm: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = t
	b.custom_minimum_size = Vector2(w, BTN_H)
	b.size = Vector2(w, BTN_H)
	b.add_theme_font_size_override("font_size", 28)
	UISkin.card_button(b)
	if primary:
		b.add_theme_color_override("font_color", Color("#ffe9a8"))
	b.focus_mode = Control.FOCUS_NONE
	return b


## 场景里所有 Button(门禁量「整段无按钮」用)。
static func buttons_under(n: Node) -> Array:
	var out: Array = []
	if n == null:
		return out
	for c in n.find_children("*", "Button", true, false):
		out.append(c)
	return out


# ── 全身立绘(待机帧) ──
## 龟的完整立绘: 取 pets.json 的 img + sprite(帧宽高 / 帧数), 取第 0 帧**不透明包围盒**定高 ——
##   原图每帧四周留白不一, 按帧框缩会让有的龟显得小一圈; 按包围盒缩, 三只看起来一样高。
##   放置: 包围盒的底边中点落在 foot。返回一个 Control(名字 = nm), 里面是 Sprite2D; 待机帧用 `body_step(holder, t)` 走。
##   没有这只龟 / 没有立绘 ⇒ 返回 null(调用方整只不画, 不出占位)。
static var _bbox_cache := {}


static func body(parent: Control, foot: Vector2, target_h: float, id: String, nm: String = "") -> Control:
	## 界面待机帧补丁(变脸龟; PetUiIdle 头注释): 没登记逐帧待机图的龟换成界面那套, 不改 DataRegistry
	var pet: Dictionary = PetUiIdle.of(DataRegistry.pet_by_id.get(id, {}))
	var img := str(pet.get("img", ""))
	var path := "res://assets/sprites/%s" % img
	if img == "" or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var meta: Dictionary = pet.get("sprite", {}) if pet.get("sprite", {}) is Dictionary else {}
	var fw := maxi(1, int(meta.get("frameW", tex.get_width())))
	var fh := maxi(1, int(meta.get("frameH", tex.get_height())))
	var hf := maxi(1, tex.get_width() / fw)
	var vf := maxi(1, tex.get_height() / fh)
	var idle_n := clampi(int(meta.get("frames", 1)), 1, hf * vf)
	var bb: Rect2 = _bbox_cache.get(path, Rect2())
	if bb.size == Vector2.ZERO:
		var im := tex.get_image()
		if im != null:
			if im.is_compressed():
				im.decompress()
			var ur := im.get_region(Rect2i(0, 0, fw, fh)).get_used_rect()
			bb = Rect2(ur.position, ur.size) if ur.size.x > 0 else Rect2(0, 0, fw, fh)
		else:
			bb = Rect2(0, 0, fw, fh)
		_bbox_cache[path] = bb
	var sc := minf(target_h / bb.size.y, target_h * 1.8 / bb.size.x)     # 龟大多是横着的: 宽给到高的 1.8 倍才能一样高
	var holder := Control.new()
	if nm != "":
		holder.name = nm
	holder.size = Vector2(bb.size.x * sc, bb.size.y * sc)
	holder.position = foot - Vector2(holder.size.x * 0.5, holder.size.y)
	holder.pivot_offset = Vector2(holder.size.x * 0.5, holder.size.y)      # 以脚底为轴(落地压扁 / 呼吸都从脚底起)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var spr := Sprite2D.new()
	spr.name = "Body"
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = false
	spr.frame = 0
	spr.hframes = hf
	spr.vframes = vf
	spr.frame = 0
	spr.scale = Vector2(sc, sc)
	spr.position = -bb.position * sc
	holder.add_child(spr)
	holder.set_meta("idle_n", idle_n)
	holder.set_meta("fps", 8.0)
	return holder


## 待机帧按时间走(与演出同一根时间轴, 不另起计时器)。
static func body_step(holder: Control, t: float) -> void:
	if holder == null:
		return
	var spr := holder.get_node_or_null("Body") as Sprite2D
	if spr == null:
		return
	var n := int(holder.get_meta("idle_n", 1))
	spr.frame = (int(floor(maxf(0.0, t) * float(holder.get_meta("fps", 8.0)))) % maxi(1, n)) if n > 1 else 0


## 这只龟有没有能画的全身立绘(没有就不进阵容那一拍)。
static func has_body(id: String) -> bool:
	var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
	return str(pet.get("img", "")) != "" and ResourceLoader.exists("res://assets/sprites/%s" % str(pet["img"]))


## 一块像素风椭圆影子(三层叠出阶梯边, 不做软渐变)。中心 c、半宽 rw。
static func shadow(parent: Control, c: Vector2, rw: float, col: Color = Color(0, 0, 0, 0.45)) -> Control:
	var holder := Control.new()
	holder.name = "Shadow"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = c
	parent.add_child(holder)
	for k in range(3):
		var w := rw * (1.0 - 0.22 * k)
		var hh := 8.0 + 4.0 * (2 - k)
		box(holder, Rect2(-w, -hh * 0.5, w * 2.0, hh), Color(col, col.a * (0.5 + 0.25 * k)))
	return holder
