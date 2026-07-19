## 贴图生成器 (从 RealtimeBattle3DScene.gd 抽出·2026-07-19)
## 34个纯函数: 输入颜色/尺寸参数 → 输出 ImageTexture/GradientTexture2D, 零场景依赖。
## 各自的缓存变量随函数一起搬来(原来都只在自己的生成函数内使用)。
class_name VfxTex
extends RefCounted

static var _tile_tex_cache: ImageTexture = null
static func _make_tile_texture() -> ImageTexture:   # 斜网格weave(菱形地砖) + tile内边框(格线), 灰度→材质albedo_color上色
	if _tile_tex_cache != null: return _tile_tex_cache
	var N := 32
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in range(N):
		for x in range(N):
			var v := 1.0
			if (x + y) % 10 < 1 or (x - y + N) % 10 < 1:   # 双向斜线=菱形weave
				v = 1.18                                    # 亮部(#263056感)
			if x < 1 or x >= N - 1 or y < 1 or y >= N - 1:  # tile内边框=网格线
				v = 0.66
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_tile_tex_cache = ImageTexture.create_from_image(img)
	return _tile_tex_cache

# 环贴图: 中空软环 (radial: 内透明→环带亮→外淡出)
static func _make_arena_ring_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.74, Color(1, 1, 1, 0.0))
	grad.add_point(0.86, Color(1, 1, 1, 1.0))
	grad.add_point(0.93, Color(1, 1, 1, 0.55))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256; gt.height = 256
	return gt

static func _make_lightshaft_texture() -> ImageTexture:
	var w := 40; var h := 200
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var vy: float = float(y) / float(h)                 # 0=顶(亮) 1=底(淡)
		var vfall: float = (1.0 - vy) * (1.0 - vy)
		for x in range(w):
			var hx: float = absf(float(x) / float(w - 1) * 2.0 - 1.0)
			var hfall: float = 1.0 - smoothstep(0.15, 1.0, hx)
			img.set_pixel(x, y, Color(0.62, 0.86, 1.0, vfall * hfall))
	return ImageTexture.create_from_image(img)

# 气泡贴图: 透明中空 + 亮环(泡壁) + 左上高光点 → 像真气泡不是实心发光球.
static func _make_bubble_texture() -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var cc: float = (s - 1) * 0.5
	for y in range(s):
		for x in range(s):
			var r: float = sqrt(pow((x - cc) / cc, 2.0) + pow((y - cc) / cc, 2.0))
			var rim: float = smoothstep(0.55, 0.86, r) * (1.0 - smoothstep(0.9, 1.03, r))   # 泡壁亮环
			var fill: float = (1.0 - smoothstep(0.0, 0.95, r)) * 0.08                        # 极淡内填
			var hr: float = sqrt(pow((x - cc * 0.62) / (cc * 0.3), 2.0) + pow((y - cc * 0.6) / (cc * 0.3), 2.0))
			var hl: float = (1.0 - smoothstep(0.0, 1.0, hr)) * 0.85                          # 左上高光点
			var a: float = clampf(maxf(maxf(rim * 0.85, fill), hl), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.82, 0.93, 1.0, a))
	return ImageTexture.create_from_image(img)

# blob 影贴图: radial 渐变 中心黑→边缘透明 (优化: 中段加点过渡, 边缘更柔不硬切)
# 亮光晕贴图 (命中火花用): 白心→透明 (modulate 上色才会亮; blob 是黑的不能拿来当火花)
## ★#6修: 命中辉光/子弹用 GradientTexture2D radial 会露方角(角落 alpha≠0) → 改 Image 逐像素真圆(角=0).
static func _make_glow_texture() -> ImageTexture:
	var N := 96
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c   # 0中心 → 1边缘
			var a := 0.0
			if d < 0.4:
				a = lerp(1.0, 0.7, d / 0.4)
			elif d < 0.75:
				a = lerp(0.7, 0.18, (d - 0.4) / 0.35)
			elif d < 1.0:
				a = lerp(0.18, 0.0, (d - 0.75) / 0.25)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

static var _blob_tex_cache: ImageTexture = null
static func _make_blob_texture() -> ImageTexture:   # Image真圆软影(角alpha=0不显方块, 替FILL_RADIAL方角bug); 黑底,modulate控浓度,缓存
	if _blob_tex_cache != null:
		return _blob_tex_cache
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := 0.0
			if d < 1.0:
				a = 0.58 * pow(1.0 - d, 1.25)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_blob_tex_cache = ImageTexture.create_from_image(img)
	return _blob_tex_cache

# 接触核影贴图: 比 blob 更小更实的深核 (紧贴脚下盖立绘/地面交界 → 强化接地)
static func _make_contact_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.85))
	grad.add_point(0.5, Color(0, 0, 0, 0.6))
	grad.add_point(0.85, Color(0, 0, 0, 0.12))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 96; gt.height = 96
	return gt

# 队伍环贴图: 队色 radial 软环 (占位; 商业版换贴图)
static var _ring_tex_cache: ImageTexture = null
static var _bolt_tex_cache: Dictionary = {}   # #6修: 子弹贴图按颜色缓存(Image 真圆, 避免每发 CPU 逐像素)
static func _make_ring_texture(_col: Color) -> ImageTexture:   # Image逐像素真圆环(角alpha=0不显方块); 白底,_skill_ring用modulate上色; 缓存(每次画太费)
	if _ring_tex_cache != null:
		return _ring_tex_cache
	var N := 96
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := 0.0
			if d < 1.0:
				a = clampf(1.0 - absf(d - 0.82) / 0.18, 0.0, 1.0) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_ring_tex_cache = ImageTexture.create_from_image(img)
	return _ring_tex_cache

static var _star_tex_cache: ImageTexture = null
static func _make_star_texture() -> ImageTexture:   # 4尖火花星(眩晕圈用·黄白·中心亮+四轴尖); 缓存
	if _star_tex_cache != null:
		return _star_tex_cache
	var N := 48
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var dx: float = float(x) - c
			var dy: float = float(y) - c
			var ax: float = absf(dx) / c
			var ay: float = absf(dy) / c
			var r: float = sqrt(dx * dx + dy * dy) / c
			var hspk: float = maxf(0.0, 1.0 - ay / 0.18) * maxf(0.0, 1.0 - ax)   # 水平尖
			var vspk: float = maxf(0.0, 1.0 - ax / 0.18) * maxf(0.0, 1.0 - ay)   # 垂直尖
			var core: float = maxf(0.0, 1.0 - r * 2.6)                            # 中心亮核
			var a: float = clampf(maxf(core, maxf(hspk, vspk)), 0.0, 1.0)
			if a <= 0.02: continue
			img.set_pixel(x, y, Color(1.0, 0.94, 0.5, a))
	_star_tex_cache = ImageTexture.create_from_image(img)
	return _star_tex_cache

static func _make_slash_texture(col: Color) -> ImageTexture:   # 斜劈斩弧: 一段新月弧(左上→右下), 亮核软边
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(S) * 0.5; var cy := float(S) * 0.5
	var R := float(S) * 0.42; var thick := float(S) * 0.1
	for y in range(S):
		for x in range(S):
			var dx := float(x) - cx; var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if absf(d - R) > thick: continue
			var a := atan2(dy, dx)                       # 只画一段弧 (斜劈: -150°→30°, 左上→右下)
			if a < deg_to_rad(-150.0) or a > deg_to_rad(30.0): continue
			var edge := 1.0 - absf(d - R) / thick
			var taper := sin(PI * clampf((a - deg_to_rad(-150.0)) / deg_to_rad(180.0), 0.0, 1.0))   # 两端尖
			var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.4, 0.0, 1.0) * 0.75)
			c.a = edge * edge * taper
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _make_flyslash_texture(col: Color) -> ImageTexture:   # 飞斩剑气(彗星新月): 前刃凸面朝上(+Y=行进方向·配wisp_dir令尖朝目标)+白热芯+向后(下)渐隐拖尾
	var W := 72; var H := 128
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(W) * 0.5
	var arc_cy := float(H) * 0.40          # 前刃圆心(取其"上冠"一段=凸面朝上)
	var R := float(H) * 0.33
	var thick := float(H) * 0.060
	var tail_top := arc_cy - R + thick     # 拖尾从前刃后缘起
	for y in range(H):
		for x in range(W):
			var dx := float(x) - cx
			var acc := Color(0, 0, 0, 0)
			# --- ① 前刃新月弧带(白热芯) ---
			var dyd := float(y) - arc_cy
			var d := sqrt(dx * dx + dyd * dyd)
			if absf(d - R) <= thick:
				var a := atan2(dyd, dx)     # 正上=-90°; 上冠 -142°..-38°
				if a >= deg_to_rad(-142.0) and a <= deg_to_rad(-38.0):
					var frac := clampf((a + deg_to_rad(142.0)) / deg_to_rad(104.0), 0.0, 1.0)
					var edge := 1.0 - absf(d - R) / thick
					var taper := sin(PI * frac)
					var cc := col.lerp(Color(1, 1, 1), clampf(edge * 1.8, 0.0, 1.0) * 0.92)
					acc = Color(cc.r, cc.g, cc.b, clampf(edge * edge * taper * 1.15, 0.0, 1.0))
			# --- ② 向后(图像下=-Y=行进反方向)渐隐锥形拖尾 ---
			if float(y) > tail_top:
				var tprog := clampf((float(y) - tail_top) / (float(H) - tail_top), 0.0, 1.0)
				var halfw := lerpf(float(W) * 0.16, 1.0, pow(tprog, 0.65))   # 宽根→尖尾
				var dxc := absf(dx)
				if dxc <= halfw:
					var lat := 1.0 - dxc / maxf(halfw, 0.001)
					var ta := lat * lat * (1.0 - tprog) * 0.55
					var tc := col.lerp(Color(1, 1, 1), 0.25)
					if ta > acc.a: acc = Color(tc.r, tc.g, tc.b, ta)
			if acc.a > 0.003:
				img.set_pixel(x, y, acc)
	return ImageTexture.create_from_image(img)

static var _slash_sheet_cache: ImageTexture = null
static func _make_slash_sheet(col: Color) -> ImageTexture:   # Undertale式红色像素斩击 5帧(斜向弧: 白热芯+红光, 生成→峰值→断裂消散); NEAREST放大=像素感; 缓存
	if _slash_sheet_cache != null:
		return _slash_sheet_cache
	var FN := 5; var FW := 44
	var img := Image.create(FW * FN, FW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var env := [0.6, 1.0, 1.0, 0.6, 0.28]   # 每帧亮度包络(生成→峰→消散)
	for f in range(FN):
		var ox := f * FW
		var tt := float(f) / float(FN - 1)
		var br: float = env[f]
		for y in range(FW):
			for x in range(FW):
				var nx := float(x) / float(FW - 1)
				var ny := float(y) / float(FW - 1)
				var along := clampf((nx - ny + 1.0) * 0.5, 0.0, 1.0)   # 沿反对角线位置
				if along < 0.07 or along > 0.93: continue   # 两端截断
				if f == 0 and along > 0.72: continue   # 第0帧: 斩弧刚划入前段
				if tt > 0.5 and sin(along * 33.0 + float(f) * 3.1) > lerpf(1.2, -0.15, (tt - 0.5) / 0.5): continue   # 后段断裂缺口
				var bow := 0.17 * sin(PI * along)   # sabre弧弯
				var d := (nx + ny - 1.0) * 0.70710678 - bow   # 到斩弧带状距离
				var taper := pow(sin(PI * along), 0.5)   # 中间段更饱满(broader plateau)
				var th := 0.092 * (0.34 + 1.05 * taper)   # 中间更粗两端尖(叶形斩弧)
				var ad := absf(d)
				if ad > th: continue
				var e := (1.0 - ad / th) * br
				var core := 1.0 - clampf(ad / (th * 0.42), 0.0, 1.0)   # 白热芯(放大)
				img.set_pixel(ox + x, y, Color(lerpf(col.r, 1.0, core), lerpf(col.g, 1.0, core), lerpf(col.b, 1.0, core), clampf(e, 0.0, 1.0)))
	_slash_sheet_cache = ImageTexture.create_from_image(img)
	return _slash_sheet_cache

static func _make_sword_texture(col: Color) -> ImageTexture:   # 剑刃(尖指+X): 柄→刃身→尖
	var W := 56; var H := 14
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(H - 1) / 2.0
	for x in range(W):
		var fx := float(x) / float(W - 1)
		var halfw: float = (1.0 - fx) / 0.15 * 4.0 if fx > 0.85 else (4.0 if fx > 0.2 else 2.0)
		for y in range(H):
			var dy := absf(float(y) - cy)
			if dy <= halfw:
				var edge := 1.0 - dy / maxf(0.6, halfw)
				var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.5, 0.0, 1.0) * 0.85)
				c.a = clampf(edge + 0.35, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _make_qi_texture(col: Color) -> ImageTexture:   # 竖剑气: 竖向弯月能量刃(前凸/两端尖/亮核软光)
	var W := 34; var H := 88
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(H):
		var fy := float(y) / float(H - 1)
		var taper := sin(PI * fy)
		var cx := float(W) * 0.38 + 7.0 * sin(PI * fy)
		var thick := 5.0 * taper + 1.0
		for x in range(W):
			var dx := absf(float(x) - cx)
			if dx <= thick:
				var edge := 1.0 - dx / thick
				var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.6, 0.0, 1.0) * 0.8)
				c.a = edge * edge * (0.35 + 0.65 * taper)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _make_vblade_texture(col: Color) -> ImageTexture:   # 竖剑刃(尖朝上): 尖→刃身→柄
	var W := 18; var H := 76
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(W - 1) / 2.0
	for y in range(H):
		var fy := float(y) / float(H - 1)
		var halfw: float = fy / 0.12 * 5.0 if fy < 0.12 else (5.0 if fy < 0.8 else 2.5)
		for x in range(W):
			var dx := absf(float(x) - cx)
			if dx <= halfw:
				var edge := 1.0 - dx / maxf(0.6, halfw)
				var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.5, 0.0, 1.0) * 0.85)
				c.a = clampf(edge + 0.35, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _make_bladewall_texture(col: Color) -> ImageTexture:   # 阔剑007剑气墙: 宽幅浅新月(凸刃朝上=纹理+Y=行进方向·配wisp_dir朝向)·白蓝亮刃+向后短拖
	var W := 132; var H := 80
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(W) * 0.5
	var cy := float(H) * 1.42          # 圆心落下方外 → 可见宽浅顶弧(凸面朝上=行进方向)
	var R := float(H) * 1.30
	var thick := float(H) * 0.20       # 更厚的刃带(读成"墙")
	var tail_top := cy - R + thick
	for y in range(H):
		for x in range(W):
			var dx := float(x) - cx
			var acc := Color(0, 0, 0, 0)
			var dyd := float(y) - cy
			var d := sqrt(dx * dx + dyd * dyd)
			if absf(d - R) <= thick:
				var a := atan2(dyd, dx)     # 正上=-90°; 宽弧 -150°..-30°
				if a >= deg_to_rad(-150.0) and a <= deg_to_rad(-30.0):
					var frac := clampf((a + deg_to_rad(150.0)) / deg_to_rad(120.0), 0.0, 1.0)
					var edge := 1.0 - absf(d - R) / thick
					var taper := sin(PI * frac)
					var cc := col.lerp(Color(1, 1, 1), pow(clampf(edge, 0.0, 1.0), 2.4) * 0.8)   # 仅band中心一条细芯白热·刃身留赤金本色(不再整条发白)
					acc = Color(cc.r, cc.g, cc.b, clampf(edge * edge * taper * 1.3, 0.0, 1.0))
			if float(y) > tail_top:          # 向后(下)能量填充体 → 读成"剑气墙"不是一条线
				var tprog := clampf((float(y) - tail_top) / (float(H) - tail_top), 0.0, 1.0)
				var halfw := lerpf(float(W) * 0.46, float(W) * 0.06, pow(tprog, 0.65))
				if absf(dx) <= halfw:
					var lat := 1.0 - absf(dx) / maxf(halfw, 0.001)
					var ta := lat * (1.0 - tprog) * 0.6
					var tc := col.lerp(Color(1, 1, 1), 0.35)
					if ta > acc.a: acc = Color(tc.r, tc.g, tc.b, ta)
			if acc.a > 0.003:
				img.set_pixel(x, y, acc)
	return ImageTexture.create_from_image(img)

static func _make_shellhalf_texture() -> ImageTexture:   # 守护贝壳018: 扇贝半壳(铰链在下缘·穹顶朝上)·玉青壳身+暗壳沟+奶金壳缘+深描边(实心物体感·非光效)
	var W := 76; var H := 42
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var jade := Color(0.13, 0.60, 0.57)      # 壳身玉青(暗部)
	var jade2 := Color(0.44, 0.88, 0.79)     # 壳身亮部
	var rim := Color(1.00, 0.92, 0.68)       # 壳缘奶金
	var line := Color(0.05, 0.19, 0.23)      # 描边/壳沟深色
	var cx := float(W) * 0.5
	var hy := float(H) - 1.0                 # 铰链=底边中点
	var rad := float(H) - 2.0
	for y in range(H):
		for x in range(W):
			var dx := float(x) - cx
			var dy := hy - float(y)                       # 向上为正
			if dy < 0.0: continue
			var d := sqrt(dx * dx * 0.30 + dy * dy)       # 横向压扁=扇贝更宽
			if d > rad: continue
			var ang := atan2(dy, dx * 0.55)               # 0..PI 扇面角
			var t := d / rad                              # 0=铰链 1=外缘
			var edge := clampf(sin(ang) * 2.6, 0.0, 1.0)  # 两个铰链角收成尖
			if edge <= 0.02: continue
			var rib := 0.5 + 0.5 * sin(ang * 11.0)        # 放射壳肋(沟=暗)
			var c := jade.lerp(jade2, clampf(0.30 + 0.55 * rib - 0.25 * t, 0.0, 1.0))
			c = c.lerp(line, 0.30 * (1.0 - rib))          # 壳沟压暗(不是发白射线)
			if t > 0.80 and t <= 0.94:
				c = c.lerp(rim, (t - 0.80) / 0.14 * 0.85)  # 外圈奶金壳缘
			if t > 0.94 or edge < 0.30:
				c = c.lerp(line, 0.75)                     # 外缘+两侧尖角深描边
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(edge * 1.6, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

static func _make_coralspike_texture() -> ImageTexture:   # 珊瑚尖刺: 锯齿珊瑚橙尖刺(尖朝上=纹理+Y=行进方向·配wisp_dir)·浅珊瑚白尖
	var W := 44; var H := 78
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var coral := Color(1.0, 0.44, 0.32)
	var coral2 := Color(1.0, 0.74, 0.62)
	for y in range(H):
		var ty := float(y) / float(H - 1)          # 0=尖(上) 1=根(下)
		var halfw := lerpf(0.5, float(W) * 0.30, pow(ty, 0.85)) * (1.0 + 0.20 * sin(ty * 24.0))   # 尖→宽 + 锯齿边
		for x in range(W):
			var dxl := absf(float(x) - float(W) * 0.5)
			if dxl > halfw: continue
			var lat := 1.0 - dxl / maxf(halfw, 0.001)
			var tipmix := clampf((0.42 - ty) / 0.42, 0.0, 1.0)
			var c := coral.lerp(coral2, tipmix * 0.75).lerp(Color(1, 1, 1), tipmix * 0.3)
			var a := clampf(lat * 1.4, 0.0, 1.0) * clampf(1.12 - ty * 0.28, 0.0, 1.0)
			if a > img.get_pixel(x, y).a:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)

# 霰弹弹珠: 一颗小铅丸从muzzle沿扇形方向喷出+淡出(霰弹散射, 一次喷一片)
static func _make_pellet_texture() -> ImageTexture:   # 小圆金属铅丸: 亮心+硬边圆
	var S := 16
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(S - 1) / 2.0
	for y in range(S):
		for x in range(S):
			var d := Vector2(float(x) - c, float(y) - c).length()
			if d <= c - 0.5:
				var t := d / c
				var a := 1.0 if t < 0.82 else clampf((1.0 - t) / 0.18, 0.0, 1.0)
				var br := clampf(1.25 - t * 0.85, 0.45, 1.0)
				img.set_pixel(x, y, Color(1.0 * br, 0.9 * br, 0.5 * br, a))
	return ImageTexture.create_from_image(img)

# 尖尖能量波弹道贴图 (程序画: 透镜状两端尖, 白核+col边, 按伤害色上色)
static func _make_wave_texture(col: Color) -> ImageTexture:
	var W := 52
	var H := 20
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(H - 1) / 2.0
	for x in range(W):
		var fx := float(x) / float(W - 1)
		var half := (float(H) / 2.0 - 0.5) * sin(PI * fx)   # 透镜: 两端尖中间宽
		if half < 0.4:
			continue
		for y in range(H):
			var dy := absf(float(y) - cy)
			if dy <= half:
				var edge := 1.0 - dy / half
				var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.4, 0.0, 1.0) * 0.75)   # 核心偏白
				c.a = edge * edge   # 软边
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

## ★#6修: 子弹从 GradientTexture2D(radial 露方角) → Image 逐像素真圆(角 alpha=0). 按颜色缓存.
static func _make_bolt_texture(col: Color) -> ImageTexture:
	var key := "%d" % col.to_rgba32()
	if _bolt_tex_cache.has(key):
		return _bolt_tex_cache[key]
	var N := 32
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := 0.0
			if d < 0.6:
				a = lerp(1.0, 0.9, d / 0.6)
			elif d < 1.0:
				a = lerp(0.9, 0.0, (d - 0.6) / 0.4)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	var tex := ImageTexture.create_from_image(img)
	_bolt_tex_cache[key] = tex
	return tex

static func _make_venomfang_texture() -> ImageTexture:   # 双生毒牙: 两枚向内弯的獠牙(紫品红身+毒绿白尖·尖朝上=纹理+Y=行进方向配wisp_dir)
	var W := 56; var H := 76
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.70, 0.28, 0.90)   # 紫品红獠牙身
	var venom := Color(0.66, 1.0, 0.30)   # 毒绿尖
	for fi in range(2):
		var side := -1.0 if fi == 0 else 1.0
		for y in range(H):
			var ty := float(y) / float(H - 1)          # 0=尖(上) 1=根(下)
			var cxl := (0.5 + side * lerpf(0.13, 0.27, ty)) * float(W)   # 中心线: 尖靠内·根靠外→向内弯
			var halfw := lerpf(0.4, float(W) * 0.115, pow(ty, 0.8))      # 尖细→根宽
			for x in range(W):
				var dxl := absf(float(x) - cxl)
				if dxl > halfw: continue
				var lat := 1.0 - dxl / maxf(halfw, 0.001)
				var tipmix := clampf((0.34 - ty) / 0.34, 0.0, 1.0)       # 上段偏毒绿白
				var c := body.lerp(venom, tipmix * 0.85).lerp(Color(1, 1, 1), tipmix * 0.4)
				var a := clampf(lat * 1.35, 0.0, 1.0) * clampf(1.12 - ty * 0.35, 0.0, 1.0)
				if a > img.get_pixel(x, y).a:
					img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)

# 水平冰锥贴图(程序画: 后宽前尖朝右, 冰蓝+白核; 修竖冰柱方向错)
static func _make_ice_cone_texture() -> ImageTexture:
	var W := 56
	var H := 22
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(H - 1) / 2.0
	for x in range(W):
		var fx := float(x) / float(W - 1)
		var half := (float(H) / 2.0 - 0.5) * (1.0 - fx * fx)   # 后宽前尖(锥)
		if half < 0.4:
			continue
		for y in range(H):
			var dy := absf(float(y) - cy)
			if dy <= half:
				var edge := 1.0 - dy / half
				var c := Color(0.45, 0.78, 1.0).lerp(Color(0.92, 0.98, 1.0), clampf(edge * 1.3, 0.0, 1.0) * 0.8)
				c.a = clampf(edge * 1.2, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static var _disc_tex_cache: ImageTexture = null
static func _make_disc_texture() -> ImageTexture:   # Image真圆(角alpha=0); 白底modulate上色; 缓存
	if _disc_tex_cache != null:
		return _disc_tex_cache
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c   # 0=心 1=边
			var a := 0.0
			if d < 1.0:
				a = (1.0 - d) * 0.55                              # 软径向衰减, 边=0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_disc_tex_cache = ImageTexture.create_from_image(img)
	return _disc_tex_cache

static var _fire_glow_cache: ImageTexture = null
static func _make_fire_glow_tex() -> ImageTexture:   # Image真圆软发光(亮核软边, 角alpha=0不显方块); 火焰blob用, 缓存
	if _fire_glow_cache != null:
		return _fire_glow_cache
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := 0.0
			if d < 1.0:
				a = pow(1.0 - d, 1.5)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_fire_glow_cache = ImageTexture.create_from_image(img)
	return _fire_glow_cache

static var _thin_ring_cache: ImageTexture = null
static var _cone_tex_cache: ImageTexture = null
static func _make_cone_tex() -> ImageTexture:   # 实心扇形(Camille W式·apex在中心·朝上·半角50度·外半环更亮·2026-07-17)
	if _cone_tex_cache != null:
		return _cone_tex_cache
	var N := 256
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(N - 1) / 2.0
	var half := deg_to_rad(50.0)
	for y in range(N):
		for x in range(N):
			var dx: float = float(x) - c
			var dy: float = c - float(y)                    # 朝上为正
			var dist: float = sqrt(dx * dx + dy * dy) / c   # 0-1
			if dist > 1.0: continue
			var ang: float = atan2(dx, dy)                  # 距+Y(上)的夹角
			if absf(ang) > half: continue
			var edge: float = 1.0 - smoothstep(half - 0.06, half, absf(ang))   # 锥界软边
			var rim: float = 1.0 - smoothstep(0.97, 1.0, dist)                  # 外缘软边
			var a: float = 0.32 * edge * rim
			if dist > 0.5: a += 0.30 * edge * rim           # 外半环加成区更亮
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_cone_tex_cache = ImageTexture.create_from_image(img)
	return _cone_tex_cache

static func _make_thin_ring_tex() -> ImageTexture:   # 高分细线圆环(256px·细带2px软边; 大范围预告圈用——48px像素环放大到1000码会糊成格子; 白色modulate上色)
	if _thin_ring_cache != null:
		return _thin_ring_cache
	var N := 256
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length()
			var a := clampf(1.0 - absf(d - 124.0) / 2.2, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_thin_ring_cache = ImageTexture.create_from_image(img)
	return _thin_ring_cache

static var _pixel_ring_cache: ImageTexture = null
static func _make_pixel_ring_tex() -> ImageTexture:   # 硬边像素圆环(48px低分辨率·无AA·NEAREST放大=像素锯齿边; 白色modulate上色)
	if _pixel_ring_cache != null:
		return _pixel_ring_cache
	var N := 48
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length()
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if (d >= 18.5 and d <= 23.0) else 0.0))   # 硬边环带(无渐变)
	_pixel_ring_cache = ImageTexture.create_from_image(img)
	return _pixel_ring_cache

static var _pixel_block_cache: ImageTexture = null
static func _make_pixel_block_tex() -> ImageTexture:   # 6px实心像素块(尘土/碎屑用·白色modulate上色)
	if _pixel_block_cache != null:
		return _pixel_block_cache
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	_pixel_block_cache = ImageTexture.create_from_image(img)
	return _pixel_block_cache

# 瞄准/锁定框贴图: 圆环 + 上下左右四刻线(跨圈), 中心留空(不挡脸)
static func _make_reticle_texture(col: Color) -> ImageTexture:
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(S - 1) / 2.0
	var R := c - 5.0
	for y in range(S):
		for x in range(S):
			var dx := float(x) - c
			var dy := float(y) - c
			var d := sqrt(dx * dx + dy * dy)
			var a := 0.0
			if absf(d - R) < 1.8:
				a = 1.0                                                      # 外圈
			if absf(dx) < 1.6 and absf(absf(dy) - R) < 6.0:
				a = maxf(a, 1.0)                                             # 上下竖刻线
			if absf(dy) < 1.6 and absf(absf(dx) - R) < 6.0:
				a = maxf(a, 1.0)                                             # 左右横刻线
			if a > 0.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)

# 目标锁定角标([ ]四角方括号) — 持续标记(靶向器055/飞镖056)专用, 视觉区别于054十字准星圆环
static func _make_target_bracket_texture(col: Color) -> ImageTexture:
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var lo := 9.0
	var hi := float(S) - 9.0
	var arm := 16.0     # 每角短臂长
	var th := 2.4       # 半线宽
	for y in range(S):
		for x in range(S):
			var fx := float(x); var fy := float(y)
			var on := false
			for cx in [lo, hi]:
				for cy in [lo, hi]:
					var hx0: float = cx if cx == lo else cx - arm
					var hx1: float = cx + arm if cx == lo else cx
					if absf(fy - cy) < th and fx >= hx0 - th and fx <= hx1 + th:
						on = true              # 横臂
					var vy0: float = cy if cy == lo else cy - arm
					var vy1: float = cy + arm if cy == lo else cy
					if absf(fx - cx) < th and fy >= vy0 - th and fy <= vy1 + th:
						on = true              # 竖臂
			if on:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))
	return ImageTexture.create_from_image(img)

static func _make_moon_sheet(col: Color) -> ImageTexture:   # 弯月黄色闪电斩 5帧(与预警扇区同几何: 顶点左中/环650码带/±30度; 锯齿闪电; 生成→峰值→消散)
	var FW := 128; var FN := 5
	var img := Image.create(FW * FN, FW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(FW) * 0.5
	var half := deg_to_rad(30.0)
	var midr := 0.81   # 650/800 环中心
	for f in range(FN):
		var t := float(f) / float(FN - 1)
		var bright: float = (minf(t / 0.32, 1.0)) if t <= 0.5 else (maxf(0.0, 1.0 - (t - 0.5) / 0.5))
		var ht := 0.03 + 0.075 * sin(PI * clampf(t, 0.0, 1.0))   # 带半厚(fraction)
		var ox := f * FW
		for y in range(FW):
			for x in range(FW):
				var dx := float(x); var dy := float(y) - cy
				var dist := sqrt(dx * dx + dy * dy) / float(FW - 1)
				var a := atan2(dy, dx)
				if absf(a) > half: continue
				var jag := sin(a * 10.0 + t * 6.0) * 0.02 + sin(a * 27.0 + float(f)) * 0.012   # 闪电锯齿
				var dd := absf(dist - (midr + jag))
				if dd > ht: continue
				if t > 0.55 and sin(a * 16.0 + float(f) * 2.3) > lerpf(1.1, -0.3, (t - 0.55) / 0.45): continue
				var e := (1.0 - dd / ht) * bright
				if e <= 0.02: continue
				var c := col.lerp(Color(1, 1, 1), clampf(e * 1.4, 0.0, 1.0) * 0.78)
				c.a = clampf(e * e + 0.08 * bright, 0.0, 1.0)
				img.set_pixel(ox + x, y, c)
	return ImageTexture.create_from_image(img)

static func _make_sector_tex(col: Color) -> ImageTexture:   # 环形扇区(顶点在左中, 沿+X扇开; 环500~800=inner0.625, 60度): 预警用
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(S) / 2.0
	var half := deg_to_rad(30.0)
	for y in range(S):
		for x in range(S):
			var dx := float(x)
			var dy := float(y) - cy
			var dist := sqrt(dx * dx + dy * dy) / float(S - 1)
			if dist < 0.625 or dist > 1.0: continue
			var a := atan2(dy, dx)
			if absf(a) > half: continue
			var er := minf((dist - 0.625) / 0.09, (1.0 - dist) / 0.09)
			var ea := (half - absf(a)) / deg_to_rad(9.0)
			var e := clampf(minf(minf(er, ea), 1.0), 0.0, 1.0)
			var c := col; c.a = col.a * (0.3 + 0.7 * e)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _make_laser_beam_tex(col: Color) -> ImageTexture:   # 激光束(白热核+色光晕/两端尖), 沿+X
	var W := 100; var H := 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(H - 1) / 2.0
	for x in range(W):
		var fx := float(x) / float(W - 1)
		var taper := sin(PI * fx)
		if taper <= 0.02: continue
		for y in range(H):
			var dy := absf(float(y) - cy) / (float(H) * 0.5)
			var core := clampf(1.0 - dy * 3.2, 0.0, 1.0)
			var glow := clampf(1.0 - dy, 0.0, 1.0)
			var c := Color(1, 1, 1).lerp(col, 1.0 - core)
			c.a = clampf((core + glow * 0.55) * taper, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
