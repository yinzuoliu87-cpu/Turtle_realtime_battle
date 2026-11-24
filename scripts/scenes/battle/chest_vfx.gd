extends RefCounted
## 宝箱龟普攻【宝箱砸击】专属特效(2026-11-20 重做; 只管画面, 不读写对局状态, 不动 RULES_VER)。
## 用户 11-20「它的普攻特效…需要去重做吧…不是普通普攻动画，是普攻特效」(方案书 docs/plans/20261120-宝箱龟图鉴战利品与普攻特效.md)。
##   原来是通用火焰光晕 + 通用能量光带 + 一张爆闪图, 实拍几乎看不见、也看不出是宝箱。
## 参考(逐帧, 外部商业游戏): 奥恩 Q「火山裂隙」docs/studies/20261120-宝箱砸击参考-奥恩Q逐帧.md —— 砸地爆闪 → 碎石崩飞 →
##   亮裂缝带着亮头沿地面推进 → 身后冷却 → 尽头炸开 → 0.55 秒收干净。宝箱主题: 碎石 → 金币宝石, 岩浆裂缝 → 金色裂光, 炸开 → 金币溅开。
## 素材: Blender 建模 + 卡通着色 + 物理抛出, 按游戏镜头 40° 渲序列帧(tools/assetgen/blender_chest_fx.py → build_chest_sheets.py);
##   引擎里只留叠加发光的亮芯 / 波头 / 星闪(tools/assetgen/paint_chest_fx.py 按公式画的灰度图)。
## 帧推进 / 运动 / 寿命全按游戏钟(battle_render._tick_anim_fx; 带 p0 + life ⇒ 直播只发出生参数 `@afx`)。
## 时机: basic_slam 在 ChestSystem._chest_basic 被调用那一刻(宝箱砸到地 = 结算排程起点); 波头 / 沿线迸出按「波头扫到那一处」的时刻
##   (与结算排程同一个公式: BASIC_WAVE_SEC × 沿线距离 / 射程); basic_hit 在伤害结算那一刻(_pending_shots 回调里, 与伤害数字同一刻)。

const SLAM_TEX := "res://assets/sprites/vfx/chest-slam.png"          # 18 帧 × 192, 9 × 2; 正交宽 3.0 米, 画面中心离地 0.4 米
const SLAM_GND_TEX := "res://assets/sprites/vfx/chest-slam-gnd.png"  # 同排法; 正上方 3.0 米
const POP_TEX := "res://assets/sprites/vfx/chest-pop.png"            # 两种 × 15 帧 × 128, 10 × 3; 正交 2.0 米, 中心离地 0.3 米
const POP_GND_TEX := "res://assets/sprites/vfx/chest-pop-gnd.png"    # 同排法; 正上方 2.0 米
const HIT_TEX := "res://assets/sprites/vfx/chest-hit.png"            # 14 帧 × 128, 7 × 2; 正交 2.4 米, 中心离地 0.45 米
const WAVE_TEX := "res://assets/sprites/vfx/chest-wave-gnd.png"      # 22 帧 × 256×48, 2 × 11; 正上方, 图宽 3.2 米, 裂光长 = 砸点到射程尽头(124 码)
const WAVE_ORTHO_M := 3.2
const WAVE_CELL_W := 256
const WAVE_LEN := 124.0                                               # 渲染时裂光的长度(码) = BASIC_REACH − BASIC_SLAM_FWD
const GLOW_TEX := "res://assets/sprites/vfx/chest-glow.png"          # 64 × 64 软光晕(叠加)
const GLINT_TEX := "res://assets/sprites/vfx/chest-glint.png"        # 48 × 48 宝石星闪(叠加)
const SEQ_FPS := 30.0
## 沿线迸出的位置(占射程的比例; 砸点在 46 / 170 ≈ 0.27 之后): 三处, 两种序列轮流
const POP_AT := [0.45, 0.68, 0.92]
const TRAIL_N := 6                       # 波头身后贴地热光几处
## 放大(用户 11-20 看第二版:「特效可以更大一点…宝箱…光还不够大…特效还不够明显」): 整场画面里龟只有三四十像素高,
##   原尺寸金币约 12 像素、裂光两三像素宽、宝箱光十来像素 ⇒ 序列帧整体放大(挂点高度同比抬, 落地点仍贴地), 叠加光一并加大。
const SLAM_K := 1.35
const POP_K := 1.25
const HIT_K := 1.3

const C_HOT := Color(1.0, 0.97, 0.85)    # 白金(爆闪 / 星闪)
const C_GOLD := Color(1.0, 0.78, 0.28)   # 金(亮芯 / 波头光晕)

var battle
var rng := RandomNumberGenerator.new()   # 纯演出随机(不碰 sim 的随机流)
var _texs := {}
var _mats := {}


func _init(b) -> void:
	battle = b
	rng.seed = 201120


func tex(path: String) -> Texture2D:
	if not _texs.has(path):
		_texs[path] = load(path) if ResourceLoader.exists(path) else null
	return _texs[path]


## 宝箱砸地那一刻: 砸点爆闪 + 金币宝石崩飞 + 贴地金色裂光沿砸出去的方向推进 + 波头光 + 沿线三处金币蹦出。
## u = 宝箱龟, dir = 砸出去的方向(单位向量), reach = 这一下的射程(码; 带【锁链】时被放大)。
func basic_slam(u: Dictionary, dir: Vector2, reach: float) -> void:
	if battle._world == null:
		return
	var sl: Texture2D = tex(SLAM_TEX)
	var slg: Texture2D = tex(SLAM_GND_TEX)
	var po: Texture2D = tex(POP_TEX)
	var pog: Texture2D = tex(POP_GND_TEX)
	var wv: Texture2D = tex(WAVE_TEX)
	var glow: Texture2D = tex(GLOW_TEX)
	var glint: Texture2D = tex(GLINT_TEX)
	if sl == null or slg == null or po == null or pog == null or wv == null or glow == null or glint == null:
		return                            # 缺图就不画, 不拿别的图顶替
	var t0: float = battle._t
	var o2: Vector2 = u["pos"]
	var p0: Vector2 = o2 + dir * ChestSystem.BASIC_SLAM_FWD
	## ① 砸点爆闪(叠加; 参考第 6~7 帧): 星闪 0.1 秒 + 金色亮芯 0.22 秒
	var hp: Vector3 = battle._world_pos(p0, 0.3)
	_p(glint, hp, {"texel": 1.7, "life": 0.11, "s0": 1.3, "s1": 0.7, "a0": 1.0, "a1": 0.0, "tint": C_HOT, "add": true, "prio": 12, "t0": t0})
	_p(glow, hp, {"texel": 1.45, "life": 0.24, "s0": 0.7, "s1": 1.3, "a0": 0.9, "a1": 0.0, "tint": C_GOLD, "add": true, "prio": 10, "t0": t0})
	## ② Blender 序列帧(砸点): 金币宝石往上崩、落地弹跳 + 沙尘; 贴地层 = 沙尘环 + 影子
	_seq(sl, p0, 0.4, 9, 2, 0, 18, 3.0, 192, t0, SLAM_K)
	_seq_gnd(slg, p0, 9, 2, 0, 18, 3.0, 192, t0, SLAM_K)
	## ③ 金色裂光(贴地, 画在龟脚下; 沿砸出去的方向转; 带锁链时按射程整体放大)
	var wl: float = maxf(1.0, reach - ChestSystem.BASIC_SLAM_FWD)
	var wc: Vector2 = p0 + dir * (wl * 0.5)
	_p(wv, battle._world_pos(wc, 0.03), {"hf": 2, "vf": 11, "fr": 0, "n": 22, "fps": SEQ_FPS, "life": 22.0 / SEQ_FPS,
		"px_m": WAVE_ORTHO_M / float(WAVE_CELL_W) * (wl / WAVE_LEN), "a0": 1.0, "a1": 1.0,
		"flat": true, "yaw": -atan2(dir.y, dir.x), "prio": -1, "t0": t0})
	## ④ 波头光(叠加): 从砸点出发, 到哪儿的时刻 = 结算排程同一个公式(BASIC_WAVE_SEC × 沿线距离 / 射程)
	var wave_sec: float = ChestSystem.BASIC_WAVE_SEC
	var ts: float = wave_sec * ChestSystem.BASIC_SLAM_FWD / reach
	var dur: float = maxf(0.02, wave_sec - ts)
	var ha: Vector3 = battle._world_pos(p0, 0.12)
	var hb: Vector3 = battle._world_pos(o2 + dir * reach, 0.12)
	_p(glow, ha, {"texel": 0.85, "vel": (hb - ha) / dur, "life": dur, "s0": 0.9, "s1": 1.2, "a0": 0.95, "a1": 0.55, "tint": C_GOLD,
		"add": true, "prio": 11, "t0": t0 + ts})
	_p(glow, ha, {"texel": 0.38, "vel": (hb - ha) / dur, "life": dur, "s0": 1.0, "s1": 1.0, "a0": 1.0, "a1": 0.8, "tint": C_HOT,
		"add": true, "prio": 12, "t0": t0 + ts})
	_p(glint, hb, {"texel": 1.0, "life": 0.12, "s0": 1.2, "s1": 0.5, "a0": 0.9, "a1": 0.0, "tint": C_HOT, "add": true, "prio": 12, "t0": t0 + wave_sec})
	## 波头身后贴地的热光(叠加, 平铺在地上): 波头经过一处亮一处、0.28 秒淡掉 ⇒ 裂光在游戏的小比例下也读得出一条亮道(参考第 11~13 帧裂缝身后透出的橙光)
	for j in range(TRAIL_N):
		var a2: float = ChestSystem.BASIC_SLAM_FWD + (reach - ChestSystem.BASIC_SLAM_FWD) * (float(j) + 0.5) / float(TRAIL_N)
		_p(glow, battle._world_pos(o2 + dir * a2, 0.04), {"texel": 1.05, "life": 0.32, "s0": 0.8, "s1": 1.25, "a0": 0.8, "a1": 0.0,
			"tint": C_GOLD, "add": true, "flat": true, "yaw": 0.0, "prio": 0, "t0": t0 + wave_sec * a2 / reach})
	## ⑤ 沿线三处金币从地里蹦出(参考第 11 帧沿线抛起的碎石), 波头扫到那一处才出; 两种序列轮流, 横向错开一点
	var side := Vector2(-dir.y, dir.x)
	for i in range(POP_AT.size()):
		var a: float = float(POP_AT[i]) * reach
		var at: Vector2 = o2 + dir * a + side * rng.randf_range(-14.0, 14.0)
		var tp: float = t0 + wave_sec * a / reach
		var base: int = 15 * (i % 2)
		_seq(po, at, 0.3, 10, 3, base, 15, 2.0, 128, tp, POP_K)
		_seq_gnd(pog, at, 10, 3, base, 15, 2.0, 128, tp, POP_K)


## 波头扫到一个敌人、伤害结算那一刻: 金币从它身上溅开 + 宝石星闪 + 金色亮芯。
func basic_hit(o: Dictionary) -> void:
	if battle._world == null:
		return
	var hi: Texture2D = tex(HIT_TEX)
	var glow: Texture2D = tex(GLOW_TEX)
	var glint: Texture2D = tex(GLINT_TEX)
	if hi == null or glow == null or glint == null:
		return
	var t0: float = battle._t
	var hh: float = float(o.get("height", 0.0))
	_seq(hi, o["pos"], 0.45, 7, 2, 0, 14, 2.4, 128, t0, HIT_K, hh)
	var p: Vector3 = battle._world_pos(o["pos"], 0.5 + hh)
	_p(glint, p, {"texel": 1.3, "life": 0.12, "s0": 1.2, "s1": 0.5, "a0": 1.0, "a1": 0.0, "tint": C_HOT, "add": true, "prio": 11, "t0": t0})
	_p(glow, p, {"texel": 1.1, "life": 0.2, "s0": 0.6, "s1": 1.2, "a0": 0.8, "a1": 0.0, "tint": C_GOLD, "add": true, "prio": 10, "t0": t0})


# ════════════════════════════════════════════════════════════════════════════
#  宝箱上的光(用户 11-20「举的宝箱砸下来的时候，那个宝箱上面可不可以加点特效？…地面上这部特效做的没问题」)
#  普攻动作 chest/attack.png 12 帧(美术朝左): 第 1 帧举过头顶 → 第 2 帧往前抡 → 第 3 帧着地(结算在第 5 帧, TurtleActions.HIT)。
#  状态的函数: sim 每步(ChestSystem._chest_treasure_tick 开头)看这只宝箱龟是不是正在播普攻、播到第几帧(带小数),
#  在那一刻宝箱的位置发光点 —— 前摇被控 / 打断、动作换掉了就自然停, 不会对着空气放完(不在起手时一次排好整段)。
#   ① 第 0.6 ~ 3 帧: 光团贴着宝箱、越抡越亮; 每 EMIT_SEC 留一颗短命光点 ⇒ 连成一道跟着宝箱走的金色拖尾; 偶尔掉金色星点
#   ② 越过第 3 帧(着地)那一刻: 宝箱上的光炸开(星闪 + 光晕 + 一圈往上溅的火星); 地面那套(basic_slam)照旧在结算那一刻
#  粒子全按游戏钟(_anim_fx: p0 + vel + life)⇒ 直播只发出生参数。状态记在本对象上(按立绘节点 id), 不往单位字典加键(单位字典进确定性摘要)。
# ════════════════════════════════════════════════════════════════════════════
const ATTACK_SHEET := "pets/animations/chest/attack.png"
## 每帧宝箱中心(像素, 140 方帧, 帧号从 0 数): 11-20 按铁箍的蓝灰色逐帧量(核对图 .out/chest_codex/attack_chest_track.png)
const CHEST_PX := [Vector2(78, 86), Vector2(47, 40), Vector2(29.5, 63.5), Vector2(29.5, 112.5), Vector2(30, 111.5), Vector2(30.5, 112),
	Vector2(28.5, 112), Vector2(27.5, 112), Vector2(41, 73.5), Vector2(97.5, 65), Vector2(85, 84), Vector2(78, 86)]
const GLOW_FROM := 0.6       # 从第几帧起亮(举起途中)
const LAND_K := 3.0          # 第几帧着地
const EMIT_SEC := 1.0 / 45.0
const TRAIL_DK := 0.15        # 拖尾每隔几分之一帧补一颗光点
var _st := {}                # 立绘节点 id → {"last": 上次留光点的游戏时刻, "landed": 这一下炸过没有, "k": 上一步的帧位置}


func tick_attack(u: Dictionary) -> void:
	var spr = u.get("sprite", null)
	if battle._world == null or not is_instance_valid(spr) or not (spr is Sprite3D):
		return
	var st: Sprite3D = spr
	var sid: int = st.get_instance_id()
	var sd: Dictionary = u.get("anim_sd", {})
	var tx = sd.get("tex", null)
	if str(u.get("anim_action", "")) != "attack" or not (tx is Texture2D) or not str((tx as Texture2D).resource_path).ends_with(ATTACK_SHEET) \
			or not bool(u.get("alive", false)) or st.texture == null:
		_st.erase(sid)
		return
	var k: float = float(u.get("anim_t", 0.0)) * float(sd.get("fps", 0.0))
	var s: Dictionary = _st.get(sid, {})
	if s.is_empty() or k < float(s.get("k", 0.0)) - 0.01:   # 新的一下(动作从头播)
		s = {"last": -99.0, "landed": false, "k": k}
		_st[sid] = s
	s["k"] = k
	var glow: Texture2D = tex(GLOW_TEX)
	var glint: Texture2D = tex(GLINT_TEX)
	if glow == null or glint == null:
		return
	var b: Basis = battle._vfx.cam_basis()
	var geo := {"org": st.global_position, "right": b.x.normalized(), "up": b.y.normalized(), "ps": st.pixel_size,
		"half": float(st.texture.get_width()) / float(maxi(1, st.hframes)) * 0.5,
		"feet": float((TurtleActions.NORM.get("chest", [74.0, 135.0, 74.0]) as Array)[1]), "flip": st.flip_h}
	var now: float = battle._t
	## ① 举起 → 抡下: 贴着宝箱的光团 + 拖尾。上次留点到这一步之间按帧位置每 TRAIL_DK 补一颗(抡下只有两帧约 0.17 秒, 只在 sim 步上留点连不成一道弧)
	if k >= GLOW_FROM and now - float(s["last"]) >= EMIT_SEC:
		var k0: float = maxf(GLOW_FROM, float(s.get("ek", GLOW_FROM - TRAIL_DK)) + TRAIL_DK)
		var k1: float = minf(k, LAND_K)
		var kk: float = k0
		while kk <= k1 + 0.0001:
			_glow_dot(glow, glint, kk, geo, now)
			s["ek"] = kk
			kk += TRAIL_DK
		s["last"] = now
	## ② 着地那一刻: 宝箱上的光炸开
	if k >= LAND_K and not bool(s["landed"]):
		s["landed"] = true
		var pl: Vector3 = _chest_world(LAND_K, geo)
		_p(glint, pl, {"texel": 1.6, "life": 0.13, "s0": 1.4, "s1": 0.6, "a0": 1.0, "a1": 0.0, "tint": C_HOT, "add": true, "prio": 14, "t0": now})
		_p(glow, pl, {"texel": 1.3, "life": 0.2, "s0": 0.6, "s1": 1.3, "a0": 0.85, "a1": 0.0, "tint": C_GOLD, "add": true, "prio": 13, "t0": now})
		for j in range(8):
			var a2: float = PI * (0.08 + 0.84 * float(j) / 7.0) + rng.randf_range(-0.12, 0.12)   # 上半圈
			var v2: Vector3 = ((geo["right"] as Vector3) * cos(a2) + (geo["up"] as Vector3) * sin(a2)) * rng.randf_range(2.4, 4.3)
			_p(glint, pl, {"texel": 0.46, "vel": v2, "grav": 7.0, "life": rng.randf_range(0.26, 0.4), "s0": 1.0, "s1": 0.35, "a0": 1.0, "a1": 0.0,
				"tint": C_HOT, "add": true, "prio": 14, "t0": now})


## 宝箱在第 kk 帧那一点留一颗光点: 金色光晕 + 白金亮芯(越接近着地越亮越大), 偶尔掉一颗金色星点。
## 大小 / 亮度按「宝箱本身一直看得见」收(11-20 第一版光晕 0.75~1.25 × 亮度 0.6~0.95, 着地前后叠成一团白光盖住宝箱 5~6 帧)。
func _glow_dot(glow: Texture2D, glint: Texture2D, kk: float, geo: Dictionary, now: float) -> void:
	var w: float = clampf((kk - GLOW_FROM) / (LAND_K - GLOW_FROM), 0.0, 1.0)
	var p: Vector3 = _chest_world(kk, geo)
	## 外圈光晕: 大而淡(宝箱像整个在发光), 亮度低 ⇒ 不把宝箱本身盖成一团白
	_p(glow, p, {"texel": 1.3 + 0.7 * w, "life": 0.16, "s0": 1.0, "s1": 0.7, "a0": 0.16 + 0.14 * w, "a1": 0.0,
		"tint": C_GOLD, "add": true, "prio": 12, "t0": now})
	_p(glow, p, {"texel": 0.7 + 0.4 * w, "life": 0.15 + 0.04 * w, "s0": 1.0, "s1": 0.45, "a0": 0.45 + 0.3 * w, "a1": 0.0,
		"tint": C_GOLD, "add": true, "prio": 13, "t0": now})
	_p(glow, p, {"texel": 0.26 + 0.12 * w, "life": 0.1, "s0": 1.0, "s1": 0.6, "a0": 0.85, "a1": 0.0, "tint": C_HOT, "add": true, "prio": 14, "t0": now})
	if rng.randf() < 0.25:
		var a: float = rng.randf_range(0.0, TAU)
		var v: Vector3 = ((geo["right"] as Vector3) * cos(a) + (geo["up"] as Vector3) * (0.6 + 0.4 * sin(a))) * rng.randf_range(0.6, 1.4)
		_p(glint, p, {"texel": 0.34, "vel": v, "grav": 5.0, "life": rng.randf_range(0.25, 0.4), "s0": 1.0, "s1": 0.3, "a0": 1.0, "a1": 0.0,
			"tint": C_HOT, "add": true, "prio": 14, "t0": now})


## 第 k 帧(可带小数: 帧间沿 Catmull-Rom 曲线插)宝箱中心的世界坐标。立绘是正对镜头的公告板, 脚底在单位位置(同 CandyVfx._head_world):
##   像素(x, y)→ 相机右方向 (x − 半宽)(朝右时取反) + 相机上方向 (脚底行 − y), 再乘每像素米数。
func _chest_world(k: float, g: Dictionary) -> Vector3:
	var n: int = CHEST_PX.size()
	var i: int = clampi(int(floor(k)), 0, n - 1)
	var f: float = clampf(k - float(i), 0.0, 1.0)
	var p0: Vector2 = CHEST_PX[maxi(0, i - 1)]
	var p1: Vector2 = CHEST_PX[i]
	var p2: Vector2 = CHEST_PX[mini(n - 1, i + 1)]
	var p3: Vector2 = CHEST_PX[mini(n - 1, i + 2)]
	var f2: float = f * f
	var f3: float = f2 * f
	var px: Vector2 = 0.5 * ((2.0 * p1) + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f3)
	var lx: float = (px.x - float(g["half"])) * (-1.0 if bool(g["flip"]) else 1.0)
	var ly: float = float(g["feet"]) - px.y
	return (g["org"] as Vector3) + (g["right"] as Vector3) * (lx * float(g["ps"])) + (g["up"] as Vector3) * (ly * float(g["ps"]))


## 一段 Blender 序列帧(立着的): 公告板, 每像素 = 渲染正交宽 / 每帧像素(米)。
## k = 放大倍数: 每像素米数 × k, 画面中心离地高度 h 也 × k(序列帧里地面在中心下方 h 处, 放大后同比远) ⇒ 落地点仍贴地;
##   lift = 目标本身离地(被击飞的敌人), 加在外面不跟着放大。
func _seq(t: Texture2D, at2d: Vector2, h: float, cols: int, rows: int, base: int, n: int, ortho_m: float, cell_px: int, t0: float,
		k: float = 1.0, lift: float = 0.0) -> void:
	_p(t, battle._world_pos(at2d, h * k + lift), {"hf": cols, "vf": rows, "fr": base, "n": n, "fps": SEQ_FPS, "life": float(n) / SEQ_FPS,
		"px_m": ortho_m / float(cell_px) * k, "a0": 1.0, "a1": 1.0, "prio": 8, "near": true, "t0": t0})


## 贴地那张: 平铺在地上(贴图上方 = 离镜头远的一侧, 与 Blender 正上方渲的画面同向 ⇒ 朝向 0), 开深度, 画在龟下面。
func _seq_gnd(t: Texture2D, at2d: Vector2, cols: int, rows: int, base: int, n: int, ortho_m: float, cell_px: int, t0: float, k: float = 1.0) -> void:
	_p(t, battle._world_pos(at2d, 0.03), {"hf": cols, "vf": rows, "fr": base, "n": n, "fps": SEQ_FPS, "life": float(n) / SEQ_FPS,
		"px_m": ortho_m / float(cell_px) * k, "a0": 1.0, "a1": 1.0, "flat": true, "yaw": 0.0, "prio": -1, "near": true, "t0": t0})


## 粒子材质: 贴图 × 顶点色(modulate 上色 / 变淡)。add = 叠加发光; flat = 贴地(不朝相机, 开深度测试, 画在龟下面);
## near = 最近点采样(金币序列帧保持像素清楚; 灰度光晕用线性)。按(贴图, 混合, 层级, 贴地, 采样)共用一份。
func _mat(t: Texture2D, add: bool, prio: int, flat: bool, near: bool) -> StandardMaterial3D:
	var key := "%s|%d|%d|%d|%d" % [t.resource_path, int(add), prio, int(flat), int(near)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = t
	m.vertex_color_use_as_albedo = true
	if not flat:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if near else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.no_depth_test = not flat
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = prio
	_mats[key] = m
	return m


## 一颗粒子。o: hf/vf(帧图格子) · fr(第几格) · n/fps(连放几帧) · texel(码/像素) · px_m(每像素米, 序列帧用) · vel/grav(米/秒) · life ·
##   s0/s1 · a0/a1 · tint · add · prio · t0 · flat/yaw(贴地 + 朝向) · near(最近点采样)。运动全是游戏钟的函数(battle_render._tick_anim_fx)。
func _p(t: Texture2D, p0: Vector3, o: Dictionary) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = t
	sp.hframes = int(o.get("hf", 1))
	sp.vframes = int(o.get("vf", 1))
	sp.frame = int(o.get("fr", 0))
	sp.pixel_size = float(o["px_m"]) if o.has("px_m") else float(o.get("texel", 2.0)) * battle.WS
	var flat: bool = bool(o.get("flat", false))
	if flat:
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sp.axis = Vector3.AXIS_Y
		sp.rotation = Vector3(0.0, float(o.get("yaw", 0.0)), 0.0)
	else:
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.no_depth_test = true
	sp.shaded = false
	sp.material_override = _mat(t, bool(o.get("add", false)), int(o.get("prio", 6)), flat, bool(o.get("near", false)))
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
	return sp
