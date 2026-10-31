class_name UnitCardArt
extends RefCounted
## 单位卡的画法: 窗口底色 / 全身立绘 / 像素木框 / 稀有度色名字横幅 —— 背包页与选龟页共用这一份。
## 由来: 2026-10-30 用户「你这还是一股浏览器的感觉啊，压根没有游戏的感觉」⇒ 选龟页照背包页那套重画
##   (方案书 docs/plans/20261030-选龟页重做.md)。同一只龟在两页必须长同一张脸, 各抄一份必然漂
##   (memory fb-hand-rolled-copies-drift), 所以从 InventoryScene 抽到这里; 尺寸 / 横幅位置由调用方按自己的版式给。
## 叠放顺序(调用方照这个顺序 add_child): 窗口底色 → 立绘 → 框(角饰 / 贝壳 / 侧扣压在立绘上) → 横幅。

const FRAME_TEX := "res://assets/sprites/inventory/unit-card.png"            # 统领 / 精英: 金饰框
const FRAME_MINION_TEX := "res://assets/sprites/inventory/unit-card-minion.png"   # 普通小将: 铜饰框
const WINDOW_BG := Color("#162231")   # 窗口底色(= 原框图内窗那块深海蓝)
## 框图原生 192×252, 框到内窗 15(= 原生 5 × 3)。别的尺寸按比例算。
const NATIVE := Vector2(192.0, 252.0)
const NATIVE_BORDER := 15.0

## 立绘裁边缓存(贴图路径 + 取帧区域 → 去掉透明留边后的区域)
static var _used_cache: Dictionary = {}


## 这个尺寸的卡, 框到内窗多宽。
static func border_for(size: Vector2) -> float:
	return roundf(NATIVE_BORDER * size.x / NATIVE.x)


## 窗口底色(框里那块深色)。
static func window(size: Vector2, border: float) -> ColorRect:
	var wbg := ColorRect.new(); wbg.name = "WindowBg"
	wbg.color = WINDOW_BG
	wbg.position = Vector2(border, border); wbg.size = size - Vector2(2.0, 2.0) * border
	wbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return wbg


## 一只龟的全身立绘: [贴图, 取帧区域]。pets.json 的 img 按 sprite 的 frameW / frameH 取第 0 帧(与图鉴同一张);
##   没有全身图 ⇒ 退回 avatars/ 头像。都没有 ⇒ [null, Rect2()]。
static func pet_body(pid: String) -> Array:
	var pdef: Dictionary = DataRegistry.pet_by_id.get(pid, {})
	var img_path := "res://assets/sprites/%s" % str(pdef.get("img", ""))
	var region := Rect2()
	var sm = pdef.get("sprite", null)
	if sm is Dictionary and (sm as Dictionary).has("frameW"):
		var fw: float = float((sm as Dictionary)["frameW"])
		region = Rect2(0, 0, fw, float((sm as Dictionary).get("frameH", fw)))
	if str(pdef.get("img", "")) == "" or not ResourceLoader.exists(img_path):
		img_path = "res://assets/sprites/avatars/%s.png" % pid
		region = Rect2()
	if not ResourceLoader.exists(img_path):
		return [null, Rect2()]
	return [load(img_path), region]


## 立绘: 裁掉透明留边, 放进窗口 pw(卡内坐标), 脚底落在 foot_y(卡内坐标); 小图按整数倍放大保持像素硬边。
static func portrait(tex: Texture2D, region: Rect2, pw: Rect2, foot_y: float) -> Control:
	var clip := Control.new(); clip.name = "Portrait"
	clip.clip_contents = true
	clip.position = pw.position; clip.size = pw.size
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reg: Rect2 = region if region.size.x > 0.0 else Rect2(Vector2.ZERO, tex.get_size())
	var key := "%s|%s" % [tex.resource_path, str(reg)]
	var used: Rect2 = reg
	if _used_cache.has(key):
		used = _used_cache[key]
	else:
		var img := tex.get_image()
		if img != null:
			var ur: Rect2i = img.get_region(Rect2i(reg)).get_used_rect()
			if ur.size.x > 0 and ur.size.y > 0:
				used = Rect2(reg.position + Vector2(ur.position), Vector2(ur.size))
		_used_cache[key] = used
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = used
	var a := TextureRect.new(); a.name = "Body"
	a.texture = at
	a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	a.stretch_mode = TextureRect.STRETCH_SCALE
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var foot: float = foot_y - pw.position.y
	var k: float = minf((pw.size.x - 8.0) / used.size.x, (foot - 4.0) / used.size.y)
	if used.size.y <= 120.0 and k >= 2.0:   # 放大不到 2 倍时取整会掉成 1 倍(变脸龟 71×75 只剩一半大)
		k = floorf(k)
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if k >= 1.0 else CanvasItem.TEXTURE_FILTER_LINEAR
	var sz: Vector2 = used.size * k
	a.size = sz
	a.position = Vector2((pw.size.x - sz.x) * 0.5, foot - sz.y)
	clip.add_child(a)
	return clip


## 会动的立绘(待机帧循环)。没有逐帧待机图的龟 ⇒ 退回静态 `portrait`。
##   ★裁边按「所有帧合起来」的不透明范围(只算一次、缓存), 每帧用同一个框裁 ⇒ 动起来不被切掉一块, 站位与静态版一致。
##   帧率与选龟页原来的 `_apply_pet_idle_texture` 同一公式。autoplay = false ⇒ 停在第 0 帧(悬停时再 play, 见 meta "idle_tw")。
## 由来: 2026-10-30 用户「他们游戏是动态的，并不是你看到这么静态的」。
static func portrait_anim(pid: String, pw: Rect2, foot_y: float, autoplay: bool = true) -> Control:
	var body: Array = pet_body(pid)
	if body[0] == null:
		return null
	var tex: Texture2D = body[0]
	var pdef: Dictionary = DataRegistry.pet_by_id.get(pid, {})
	var sm = pdef.get("sprite", null)
	if not (sm is Dictionary) or not (sm as Dictionary).has("frameW") or (body[1] as Rect2).size.x <= 0.0:
		return _still_breathing(portrait(tex, body[1], pw, foot_y), autoplay)
	var fw := int((sm as Dictionary)["frameW"])
	var fh := int((sm as Dictionary).get("frameH", fw))
	var n: int = maxi(1, mini(int((sm as Dictionary).get("frames", 1)), int(floor(float(tex.get_width()) / float(maxi(1, fw))))))
	if n <= 1:
		return _still_breathing(portrait(tex, body[1], pw, foot_y), autoplay)
	var key := "%s|union%d" % [tex.resource_path, n]
	var u: Rect2
	if _used_cache.has(key):
		u = _used_cache[key]
	else:
		u = Rect2()
		var img := tex.get_image()
		if img != null:
			for i in range(n):
				var ur: Rect2i = img.get_region(Rect2i(i * fw, 0, fw, fh)).get_used_rect()
				if ur.size.x > 0 and ur.size.y > 0:
					u = Rect2(ur) if u.size.x <= 0.0 else u.merge(Rect2(ur))
		if u.size.x <= 0.0:
			u = Rect2(0, 0, fw, fh)
		_used_cache[key] = u
	var clip := portrait(tex, Rect2(u.position, u.size), pw, foot_y)
	## portrait() 会再按「这一帧」裁一次边 —— 给的已经是合起来的框, 第 0 帧可能更小 ⇒ 换回合起来的框重新摆
	var a := clip.get_node("Body") as TextureRect
	var at := a.texture as AtlasTexture
	at.region = u
	var foot: float = foot_y - pw.position.y
	var k: float = minf((pw.size.x - 8.0) / u.size.x, (foot - 4.0) / u.size.y)
	if u.size.y <= 120.0 and k >= 2.0:
		k = floorf(k)
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if k >= 1.0 else CanvasItem.TEXTURE_FILTER_LINEAR
	a.size = u.size * k
	a.position = Vector2((pw.size.x - a.size.x) * 0.5, foot - a.size.y)
	var dur_ms: float = float((sm as Dictionary).get("duration", 800))
	var fps: float = maxf(4.0, roundf(float(n) * 1000.0 / maxf(200.0, dur_ms)))
	var ux: float = u.position.x
	var tw := TweenKit.loop_on(a)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(a) and a.texture is AtlasTexture:
			var r: Rect2 = (a.texture as AtlasTexture).region
			r.position.x = float((int(v) % n) * fw) + ux
			(a.texture as AtlasTexture).region = r,
		0.0, float(n), float(n) / fps)
	a.set_meta("idle_tw", tw)
	if not autoplay:
		tw.pause()
	return clip


## 没有逐帧待机图的龟: 立绘以脚底为轴轻轻「呼吸」(高 +2.5%、宽 −1%, 一呼一吸 2.4 秒)。
##   ★2026-10-31 录屏逐帧量: 28 只里 11 只没有逐帧图(变脸 / 凤凰 / 闪电 / 彩虹…), 选了它们的统领卡 9 秒一个像素都不动。
##   幅度按立绘窗口留的 4px 顶边定(高 150 的立绘伸 3.75px), 不会被窗口裁掉。meta "idle_tw" 与逐帧版同一用法(悬停 play / 离开 pause)。
static func breathe_idle(body: Control, autoplay: bool = true) -> Tween:
	body.pivot_offset = Vector2(body.size.x * 0.5, body.size.y)
	var tw := TweenKit.loop_on(body)
	tw.tween_property(body, "scale", Vector2(0.99, 1.025), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(body, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	body.set_meta("idle_tw", tw)
	if not autoplay:
		tw.pause()
	return tw


static func _still_breathing(clip: Control, autoplay: bool) -> Control:
	var a := clip.get_node_or_null("Body") as Control
	if a != null:
		breathe_idle(a, autoplay)
	return clip


## 像素木框(卡的外框; 素材没到位时退回纯色框)。dim = 占位 / 空位(压暗偏冷), elite = 精英小将(偏暖)。
static func frame(size: Vector2, minion: bool = false, dim: bool = false, elite: bool = false) -> Control:
	var path: String = FRAME_MINION_TEX if minion else FRAME_TEX
	if ResourceLoader.exists(path):
		var fr := TextureRect.new(); fr.name = "CardFrame"
		fr.texture = load(path)
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode = TextureRect.STRETCH_SCALE
		fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fr.size = size
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if dim:
			fr.modulate = Color(0.62, 0.66, 0.74)
		elif elite:
			fr.modulate = Color(1.0, 0.9, 0.7)
		return fr
	var pnl := Panel.new(); pnl.name = "CardFrame"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#22304a") if dim else Color("#16202c")
	sb.border_color = Color("#c79a3a") if elite else Color("#7a5530")
	sb.set_border_width_all(int(border_for(size) / 2.0))
	pnl.add_theme_stylebox_override("panel", sb)
	pnl.size = size
	pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pnl


## 卡外一圈像素直边(四条 ColorRect, 不用圆角盒 / 描边盒): 选中 / 待填 / 正在看的那一张。
##   四条边装在一个叫「Ring」的容器里(同名兄弟会被引擎改成 @ColorRect@… —— 按名字找 / 删只找得到一条)。
static func ring(box: Control, size: Vector2, col: Color, w: float) -> Control:
	var holder := Control.new(); holder.name = "Ring"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in [Rect2(-w, -w, size.x + 2.0 * w, w), Rect2(-w, size.y, size.x + 2.0 * w, w),
			Rect2(-w, 0, w, size.y), Rect2(size.x, 0, w, size.y)]:
		var e := ColorRect.new()
		e.color = col
		e.position = r.position; e.size = r.size
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(e)
	box.add_child(holder)
	return holder


## 名字横幅: 压在立绘下沿, 两端伸出窗口压到边框上; 底色 / 边色 = 稀有度色(压暗 / 原色), 外面一圈黑描边(像素样)。
##   rect = 卡内坐标; fs = 字号。
static func banner(txt: String, col: Color, rect: Rect2, fs: int) -> Control:
	var root := Control.new(); root.name = "NameBanner"
	root.position = rect.position; root.size = rect.size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := ColorRect.new()
	edge.color = Color("#0d0805")
	edge.position = Vector2(-2, -2); edge.size = root.size + Vector2(4, 4)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(edge)
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.36, col.g * 0.36, col.b * 0.36, 1.0)
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel", sb)
	p.size = root.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	var l := Label.new(); l.name = "Name"
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color("#fff4dc"))
	l.add_theme_color_override("font_outline_color", Color("#1a0e05")); l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.position = Vector2(6, 0); l.size = root.size - Vector2(12, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return root
