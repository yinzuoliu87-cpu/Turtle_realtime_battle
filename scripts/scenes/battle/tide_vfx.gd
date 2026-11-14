extends RefCounted
## 043 海浪护符的粒子演出 + 打中水花(2026-11-14 从 battle_vfx.gd 拆出: 那个文件超了 3000 行上限, tools/arch_budget.py)。
## ★浪网格本体(`gen_tide_wall` / `_tide_vert` / `_tide_profile` / `_tide_quad`)仍留在 battle_vfx.gd ——
##   手机直播按「脚本路径 + 函数名」(VfxTex.tag 出处键)重放网格, 挪走旧录像就对不上。
## 入口(都由 battle_vfx 转发): splash(打中) / cast(起手) / emit(浪上每步撒粒子) / tex(贴图缓存) / rng(纯演出随机)。

var battle


func _init(b) -> void:
	battle = b


# ════════════════════════════════════════════════════════════════════════════
#  043 海浪护符 · 浪墙扫到谁那一下的水花
# ════════════════════════════════════════════════════════════════════════════
## 原 `_water_splash`(主场景) = `_skill_ring` 一圈**程序生成的椭圆环** + 4 颗
## `VfxTex._make_glow_texture()` 上飘光点 —— 圆环与光球都在禁区里, 实拍在每个被扫到的
## 单位脚下留下两个蓝圈, 读不出"被浪打到"。⇒ 换成真水花: 王冠状水冠 + 往外崩的水滴。
## ★2026-11-14 第二次重做: 照 LoL 娜美大招水花的做法(解包实测: 2×2 = 4 帧灰度图, 引擎里按渐变条上色) ——
##   Aseprite 里用鼠标逐笔画 4 帧灰度水花(落下 → 扇形溅起 → 最高 → 塌下散开; 每帧转折点是我定的, 点间连直线,
##   铅笔勾形 + 油漆桶填色), `tools/assetgen/build_tide_hit_splash.py` 只做「排成横条 + 五档灰换水色」。
##   取代当天早些时候模板搭的 10 帧版(那版不是手画, 用户 11-14 指出)。
const SPLASH_TEX := "res://assets/sprites/vfx/tide-hit.png"
const SPLASH_FRAMES := 4
const SPLASH_FPS := 10.0
const SPLASH_YARDS := 181.8       # 64 texel × 2.84 码/texel —— 照参考放大到比龟高(1:1 时全场视角下读不出)
const SPLASH_FOOT := 24.0         # 地面在格内第 56 行: 56 − 帧高 64/2
const SPLASH_H := 0.0
var _splash_tex: Texture2D = null


func splash(at2d: Vector2, ally: bool) -> void:
	if battle._world == null:
		return
	if _splash_tex == null:
		_splash_tex = load(SPLASH_TEX)
	if _splash_tex == null:
		return                            # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	var sp: Sprite3D = battle._vfx._sheet_sprite(_splash_tex, SPLASH_FRAMES, SPLASH_YARDS)
	sp.render_priority = 5
	## 友军偏亮、敌人偏冷 —— 同一张图两种染色是"同一件效果的两侧", 不是拿别的图顶替
	sp.modulate = Color(1.0, 1.0, 1.0) if ally else Color(0.72, 0.86, 1.0)
	sp.position = battle._world_pos(at2d, SPLASH_H + SPLASH_FOOT * sp.pixel_size)
	battle._world.add_child(sp)
	battle._anim_fx.append({
		"spr": sp, "fps": SPLASH_FPS, "n": SPLASH_FRAMES, "t0": battle._t,
	})
	## ★第三版(照娜美打中 Nami_Base_R_tar + splash): 光晕 0.5 秒 + 星形闪光 0.2 秒(都是叠加发光) + 气泡往上飘 + 软水珠崩开
	var glow: Texture2D = tex(TIDE_GLOW_TEX)
	var star: Texture2D = tex(TIDE_STAR_TEX)
	var bub: Texture2D = tex(TIDE_BUBBLE_TEX)
	var drops: Texture2D = tex(TIDE_DROPS_TEX)
	if glow == null or star == null or bub == null or drops == null:
		return
	var foot: Vector3 = battle._world_pos(at2d, 0.0)
	_tfx(glow, foot + Vector3(0.0, 0.8, 0.0), {"texel": 4.5, "life": 0.5, "s0": 0.7, "s1": 1.4, "a0": 0.9, "a1": 0.0,
		"tint": Color(0.6, 0.92, 1.0) if ally else Color(0.5, 0.78, 1.0), "add": true, "prio": 9})
	_tfx(star, foot + Vector3(0.0, 0.8, 0.0), {"texel": 4.0, "life": 0.2, "s0": 1.3, "s1": 0.6, "a1": 0.0, "add": true, "prio": 10})
	for j in range(4):
		var off := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.3, 0.9), rng.randf_range(-0.3, 0.3))
		_tfx(bub, foot + off, {"hf": 2, "vf": 2, "fr": j, "texel": 1.6,
			"vel": Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.8, 1.4), 0.0),
			"life": rng.randf_range(0.7, 1.0), "a0": 0.9, "a1": 0.0, "tint": TIDE_C_AQUA, "add": true, "prio": 8})
	for j in range(TIDE_HIT_DROPS):
		var ang: float = rng.randf_range(0.0, TAU)
		var hs: float = rng.randf_range(1.0, 2.8)
		var vel := Vector3(cos(ang) * hs, rng.randf_range(3.5, 6.0), sin(ang) * hs)
		_tfx(drops, foot + Vector3(0.0, 0.6, 0.0), {"hf": 2, "vf": 2, "fr": j % 4, "texel": 2.0, "vel": vel, "grav": 15.0,
			"life": rng.randf_range(0.45, 0.6), "a1": 0.0, "tint": TIDE_C_AQUA, "add": true, "prio": 8})



## 起手召浪: 施法者脚下播一遍手画序列帧(起浪点在身后 1200 码, 常在画面外 ⇒ 起手画在施法者处, 照参考)。
## 帧推进走 `_anim_fx`(t0 = 游戏钟, 与 wave_splash 同一条路)。
func cast(at2d: Vector2) -> void:
	if battle._world == null:
		return
	## ★第三版(2026-11-14 晚, 照娜美配方): 起手 = 叠加发光的大光晕 + 星形闪光 + 一圈往上冒的水雾刺 + 水珠喷泉,
	##   全是手画灰度小元素(tools/assetgen/paint_tide_fx.py), 颜色在这里上。取代模板搭的 `tide-cast.png` 和字符画光爆。
	var glow: Texture2D = tex(TIDE_GLOW_TEX)
	var star: Texture2D = tex(TIDE_STAR_TEX)
	var mist: Texture2D = tex(TIDE_MIST_TEX)
	var drops: Texture2D = tex(TIDE_DROPS_TEX)
	if glow == null or star == null or mist == null or drops == null:
		return                            # 缺图就不画, 不拿别的图顶替
	var t0: float = battle._t
	var foot: Vector3 = battle._world_pos(at2d, 0.0)
	_tfx(glow, foot + Vector3(0.0, 0.9, 0.0), {"texel": 10.0, "life": 0.6, "s0": 0.7, "s1": 1.6, "a0": 1.0, "a1": 0.0,
		"tint": Color(0.55, 0.9, 1.0), "add": true, "prio": 9, "t0": t0})
	_tfx(glow, foot + Vector3(0.0, 0.9, 0.0), {"texel": 4.5, "life": 0.4, "s0": 1.0, "s1": 1.3, "a0": 1.0, "a1": 0.0,
		"tint": Color.WHITE, "add": true, "prio": 10, "t0": t0})   # 亮芯: 两层光晕叠出「最亮」
	_tfx(star, foot + Vector3(0.0, 0.9, 0.0), {"texel": 6.0, "life": 0.22, "s0": 1.4, "s1": 0.7, "a0": 1.0, "a1": 0.0,
		"add": true, "prio": 10, "t0": t0})
	## 光爆后一大团白水雾往外扩(娜美 Mist: smoke_clouds 每秒 80 颗)
	var foam: Texture2D = tex(TIDE_FOAM_TEX)
	for j in range(12):
		var ang2: float = TAU * float(j) / 12.0 + rng.randf_range(-0.25, 0.25)
		var d2 := Vector3(cos(ang2), 0.0, sin(ang2))
		_tfx(foam, foot + d2 * 0.4 + Vector3(0.0, 0.6, 0.0), {"texel": 3.2, "vel": d2 * rng.randf_range(2.0, 3.5) + Vector3(0.0, 0.8, 0.0),
			"life": rng.randf_range(0.8, 1.1), "s0": 0.8, "s1": 2.0, "a0": 0.7, "a1": 0.0, "tint": TIDE_C_WHITE, "prio": 6,
			"t0": t0 + 0.06})
	for j in range(8):
		var ang: float = TAU * float(j) / 8.0 + rng.randf_range(-0.2, 0.2)
		var off := Vector3(cos(ang), 0.0, sin(ang)) * 0.7
		_tfx(mist, foot + off + Vector3(0.0, 0.4, 0.0), {"texel": 2.4, "vel": off * 1.5 + Vector3(0.0, 3.0, 0.0), "life": 0.6,
			"s0": 0.8, "s1": 1.4, "a0": 0.8, "a1": 0.0, "tint": TIDE_C_WHITE, "prio": 7, "t0": t0})
	for j in range(TIDE_FOUNTAIN_N):
		var ang: float = rng.randf_range(0.0, TAU)
		var hs: float = rng.randf_range(0.6, 2.6)
		var vel := Vector3(cos(ang) * hs, rng.randf_range(5.5, 9.0), sin(ang) * hs)
		_tfx(drops, foot + Vector3(0.0, 0.3, 0.0), {"hf": 2, "vf": 2, "fr": j % 4, "texel": 2.4, "vel": vel, "grav": 17.0,
			"life": rng.randf_range(0.7, 0.95), "a1": 0.0, "tint": TIDE_C_AQUA, "add": true, "prio": 8,
			"t0": t0 + float(j % 4) * 0.025})


## 043 浪墙的粒子小元素(第三版, 2026-11-14 晚; 照娜美大招配方): 手画灰度贴图(tools/assetgen/paint_tide_fx.py)
##   × 引擎里成批抛洒 + 运动 + 一部分叠加发光。颜色在这里上(灰度图 × 色), 同娜美「灰度图 + 引擎调色」。
const TIDE_FOAM_TEX := "res://assets/sprites/vfx/tide-foam.png"
const TIDE_MIST_TEX := "res://assets/sprites/vfx/tide-mist.png"
const TIDE_CRESC_TEX := "res://assets/sprites/vfx/tide-crescent.png"
const TIDE_GLOW_TEX := "res://assets/sprites/vfx/tide-glow.png"
const TIDE_STAR_TEX := "res://assets/sprites/vfx/tide-star.png"
const TIDE_BUBBLE_TEX := "res://assets/sprites/vfx/tide-bubble.png"
const TIDE_DROPS_TEX := "res://assets/sprites/vfx/tide-dropsoft.png"
const TIDE_C_AQUA := Color(0.62, 0.96, 0.92)
const TIDE_C_WHITE := Color(0.92, 1.0, 1.0)
## 浪上撒粒子: [间隔秒(游戏钟), 每次几颗]。娜美每秒 700+ 颗; 我们每颗是一个 Sprite3D 节点 + 逐帧直播, 控制在约 1/5。
## 浪速 850 → 600 时间隔同比 ×1.4: 每道浪的粒子总数(= 直播数据量)不涨, 单位路程上的密度不变。
const TIDE_EMIT := {"foam": [0.07, 2], "mist": [0.085, 2], "cresc": [0.13, 2], "drop": [0.085, 3]}
const TIDE_FOUNTAIN_N := 26
const TIDE_HIT_DROPS := 8
var _tide_texs: Dictionary = {}
var _tide_mats: Dictionary = {}
## 纯演出用的随机数(每道浪按起浪时刻定种子, 不碰 sim 的随机流; 节点状态逐帧直播照录)
var rng := RandomNumberGenerator.new()


func tex(path: String) -> Texture2D:
	if not _tide_texs.has(path):
		_tide_texs[path] = load(path)
	return _tide_texs[path]


## 粒子材质: 灰度贴图 × 顶点色(= modulate 上色 / 变淡); `add` = 叠加发光(娜美约一半发射器是这个)。按(贴图, 混合, 层级)共用一份。
func _mat(tex: Texture2D, add: bool, prio: int) -> StandardMaterial3D:
	var key := "%s|%d|%d" % [tex.resource_path, int(add), prio]
	if _tide_mats.has(key):
		return _tide_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = prio
	_tide_mats[key] = m
	return m


## 一颗粒子。o: hf/vf(帧图格子) · fr(第几格) · n/fps(连放几帧) · texel(码/像素) · vel/grav(米/秒) · life · s0/s1 · a0/a1 · tint · add · prio · t0
## 运动全是游戏钟的函数(battle_render._tick_anim_fx), 节点逐帧直播照录。
func _tfx(tex: Texture2D, p0: Vector3, o: Dictionary) -> void:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.hframes = int(o.get("hf", 1))
	sp.vframes = int(o.get("vf", 1))
	sp.frame = int(o.get("fr", 0))
	sp.pixel_size = float(o.get("texel", 2.0)) * battle.WS
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.no_depth_test = true
	sp.material_override = _mat(tex, bool(o.get("add", false)), int(o.get("prio", 6)))
	var tint: Color = o.get("tint", Color.WHITE)
	tint.a = float(o.get("a0", 1.0))
	sp.modulate = tint
	var s0: float = float(o.get("s0", 1.0))
	sp.scale = Vector3.ONE * s0
	sp.position = p0
	var t0: float = float(o.get("t0", battle._t))
	if t0 > battle._t:
		sp.visible = false
	battle._world.add_child(sp)
	var f := {"spr": sp, "t0": t0, "fps": float(o.get("fps", 1.0)), "n": int(o.get("n", 1)), "base": int(o.get("fr", 0)),
		"life": float(o.get("life", 0.5)), "p0": p0, "vel": o.get("vel", Vector3.ZERO), "grav": float(o.get("grav", 0.0)),
		"s0": s0, "s1": float(o.get("s1", s0)), "a0": float(o.get("a0", 1.0)), "a1": float(o.get("a1", 0.0))}
	if t0 > battle._t:
		f["show_at"] = t0
	battle._anim_fx.append(f)


## 浪上撒粒子(每个 sim 步调一次, 各发射器按自己的节奏)。沿浪墙只撒在场内那一段(u 0.3~0.7)。
func emit(w: Dictionary, rise: float, trav: float) -> void:
	if battle._world == null:
		return
	var dir2: Vector2 = w["dir"]
	var c: Vector2 = battle._arena_center
	var ws: float = battle.WS
	## 浪推进的世界速度(米/秒): 骑在浪身上的粒子要跟着走
	var p_a: Vector3 = VfxTex.wpos(c, ws, Vector2.ZERO, 0.0)
	var fwd: Vector3 = (VfxTex.wpos(c, ws, dir2 * 100.0, 0.0) - p_a).normalized()
	var wave_v: Vector3 = fwd * (float(w["dist"]) / maxf(0.001, float(w["travel"]))) * ws
	for kind in TIDE_EMIT:
		var key: String = "emit_" + str(kind)
		if battle._t < float(w.get(key, 0.0)):
			continue
		var spec: Array = TIDE_EMIT[kind]
		w[key] = battle._t + float(spec[0])
		for j in range(int(spec[1])):
			var u: float = rng.randf_range(0.3, 0.7)
			if kind == "foam":
				## 浪峰上冒出来、几乎留在原地(浪走后留一条泡沫带)、变大变淡 —— 娜美 foam_R / foam_L
				var v: Array = BattleVfx._tide_vert(w["start"], dir2, w["perp"], float(w["half"]), rise, trav, u, 0.78)
				_tfx(tex(TIDE_FOAM_TEX), VfxTex.wpos(c, ws, v[0], float(v[1]) * BattleVfx.TIDE_CREST_H),
					{"texel": 2.0, "vel": wave_v * 0.12 + Vector3(0.0, 0.25, 0.0), "life": rng.randf_range(0.8, 1.1),
					 "s0": 0.8, "s1": 1.8, "a0": 0.55, "a1": 0.0, "tint": TIDE_C_WHITE, "prio": 5})
			elif kind == "mist":
				## 前沿往上冒的水雾刺 —— 娜美 Mist3 / Mist4(waterspike)
				var v: Array = BattleVfx._tide_vert(w["start"], dir2, w["perp"], float(w["half"]), rise, trav, u, 0.97)
				_tfx(tex(TIDE_MIST_TEX), VfxTex.wpos(c, ws, v[0], 0.5),
					{"texel": 2.2, "vel": wave_v * 0.9 + Vector3(0.0, 2.2, 0.0), "life": rng.randf_range(0.5, 0.7),
					 "s0": 0.7, "s1": 1.3, "a0": 0.7, "a1": 0.0, "tint": TIDE_C_WHITE, "prio": 7})
			elif kind == "cresc":
				## 骑在浪身上的小卷浪 4 帧 —— 娜美 little_waves(WaterCrescent 2×2)
				var v: Array = BattleVfx._tide_vert(w["start"], dir2, w["perp"], float(w["half"]), rise, trav, u, rng.randf_range(0.35, 0.75))
				_tfx(tex(TIDE_CRESC_TEX), VfxTex.wpos(c, ws, v[0], float(v[1]) * BattleVfx.TIDE_CREST_H + 0.15),
					{"hf": 2, "vf": 2, "n": 4, "fps": 6.5, "texel": 2.6, "vel": wave_v, "life": 0.6,
					 "s0": 1.0, "s1": 1.2, "a0": 0.9, "a1": 0.2, "tint": TIDE_C_WHITE, "prio": 7})
			else:
				## 浪头往前上方甩的水珠(叠加发光) —— 娜美 LoopSplash(BlurDrops)
				var v: Array = BattleVfx._tide_vert(w["start"], dir2, w["perp"], float(w["half"]), rise, trav, u, 0.78)
				var vel: Vector3 = wave_v * rng.randf_range(0.9, 1.15) + Vector3(0.0, rng.randf_range(2.5, 4.5), 0.0)
				_tfx(tex(TIDE_DROPS_TEX), VfxTex.wpos(c, ws, v[0], float(v[1]) * BattleVfx.TIDE_CREST_H),
					{"hf": 2, "vf": 2, "fr": rng.randi_range(0, 3), "texel": 2.2, "vel": vel, "grav": 12.0,
					 "life": rng.randf_range(0.45, 0.65), "a1": 0.0, "tint": TIDE_C_AQUA, "add": true, "prio": 8})
