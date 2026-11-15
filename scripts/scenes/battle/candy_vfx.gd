extends RefCounted
## 糖果龟普攻【横扫大锤】命中 / 技能【糖果锤】砸地 —— 专属特效(2026-11-15 重做; 只管画面, 不读写对局状态, 不动 RULES_VER)。
## 用户 11-15「接下来主要针对一下糖果龟的这个特效去专门修一下，尤其这个就是它的普通攻击和糖果锤」。
## 第一版(脚本画的平面小图 × 引擎粒子)用户看了:「整个观感看上去给人就很假，给人就像一个图片贴在那儿，感觉不到任何…某种质量的存在…
##   你需要去用他们那些工具，然后去做一版」⇒ 第二版走特效师那条路: Blender 里建模 + 卡通分层着色 + 地面接影子 +
##   碎块物理抛出弹跳 + 体积糖云侵蚀溶解, 按游戏镜头俯角 51° 渲成序列帧(tools/assetgen/blender_candy_fx.py → build_candy_sheets.py);
##   引擎里只留叠加发光的亮芯 / 星闪(序列帧画不出叠加发光)。
## 参考(逐帧 + 配方, 外部商业游戏): 波比「咖啡甜心」皮肤 —— Q 锤击 docs/studies/20261115-糖果锤参考-波比咖啡甜心Q逐帧.md、
##   普攻 docs/studies/20261115b-横扫大锤参考-波比咖啡甜心普攻逐帧.md; 方案书 docs/plans/20261115c-糖果龟普攻与糖果锤特效.md。
## 序列帧是公告板(正对相机 = 与渲染角度一致); 帧推进 / 寿命全按游戏钟(battle_render._tick_anim_fx, 带 p0 + life ⇒ 直播只发出生参数 `@afx`)。
## 时机: 普攻 —— 调用点就是结算那一帧 = 动作第 4 帧锤头扫到目标(AttackHits); 糖果锤 —— 调用点 = 锤头砸到地(释放帧 5 + 0.38 秒 ≈ 动作第 10 帧)。

## 2.5D 分层(用户 11-15「修层次，画风不变」): 每段两张 —— 立着的(公告板, 画在龟前面: 飞起来的糖块 / 糖云 / 拖影)
##   + 贴地的 `-gnd`(正上方渲的, 平铺在地上、开深度、压在龟脚下: 尘浪 / 糖块影子)。原来尘浪和影子渲在立着的图里, 盖在站在里面的龟身上。
const SLAM_TEX := "res://assets/sprites/vfx/candy-slam.png"     # 27 帧 × 256, 9 × 3; 渲染正交宽 4.6 米, 画面中心离地 0.45 米
const SLAM_GND_TEX := "res://assets/sprites/vfx/candy-slam-gnd.png"   # 同排法; 正上方正交宽 5.0 米
const ERUPT_TEX := "res://assets/sprites/vfx/candy-erupt.png"   # 两种 × 21 帧 × 160, 7 × 6; 正交宽 2.6 米, 中心离地 0.35 米
const ERUPT_GND_TEX := "res://assets/sprites/vfx/candy-erupt-gnd.png" # 同排法; 正上方 3.0 米
const SWEEP_TEX := "res://assets/sprites/vfx/candy-sweep.png"   # 16 帧 × 192, 8 × 2; 正交宽 3.0 米, 中心离地 0.55 米; 挥向画面右
const SWEEP_GND_TEX := "res://assets/sprites/vfx/candy-sweep-gnd.png" # 同排法; 正上方 4.4 米
const CRACK_TEX := "res://assets/sprites/vfx/candy-crack.png"   # 128×96 俯视贴地; Aseprite 画(tools/assetgen/ase_candy_crack.lua), 锤头落点在 (40, 48)
const CRACK_PX_M := 0.036                                        # 每像素 0.036 米 ⇒ 坑口约 1.5 米、裂缝往前伸约 3 米(在 200 码判定区里)
const CRACK_LIFE := 1.6
const GLOW_TEX := "res://assets/sprites/vfx/candy-glow.png"
const STAR_TEX := "res://assets/sprites/vfx/candy-star.png"
const SWIRL_TEX := "res://assets/sprites/vfx/candy-swirl.png"   # 锤头能量漩涡 4 帧(paint_candy_fx.py)

## 糖果锤动作 cast_candyHammer(30 帧, 每帧 196 像素方帧, 美术朝左)每帧锤头中心(像素, 帧号从 0 数)。
##   11-15 逐帧量(薄荷红 + 奶白连通块的中心, 核对图 .out/candy/hammer_track.png); 第 10 帧(砸地)那块连着画进帧里的拖影, 手修到锤头本体。
##   0~3 举锤 · 4~7 锤在身后低处(蓄力; 第 5 帧 = 释放帧, 技能此刻生效) · 8 举过头顶 · 9 劈到前上方 · ★10 砸地 · 11~23 压在地上 · 24~29 收回
const HEAD_PX := [Vector2(125, 126), Vector2(104, 107), Vector2(56, 84), Vector2(110, 94), Vector2(133, 164.5),
	Vector2(133, 164.5), Vector2(133, 164.5), Vector2(133, 164.5), Vector2(110, 94), Vector2(48, 86),
	Vector2(28.5, 170), Vector2(28.5, 170.5), Vector2(28.5, 170.5), Vector2(28.5, 170.5), Vector2(28.5, 170.5),
	Vector2(28.5, 170.5), Vector2(28.5, 170.5), Vector2(28.5, 170.5), Vector2(28.5, 170.5), Vector2(28.5, 170.5),
	Vector2(28.5, 170.5), Vector2(30, 170), Vector2(30, 170), Vector2(30, 170), Vector2(39, 163),
	Vector2(39, 163), Vector2(34, 146), Vector2(49, 93), Vector2(97, 86), Vector2(125, 126)]
const ENERGY_PINK := Color(1.0, 0.42, 0.62)
const ENERGY_HOT := Color(1.0, 0.9, 0.95)
const SEQ_FPS := 30.0

## 量出来的(2026-11-15, 动作帧 1 像素 = 0.80 码): 糖果锤落点帧(cast 第 10 帧)锤头中心在龟身前 72 像素 ≈ 58 码、离地 16 像素 ≈ 0.3 米
const HEAD_FWD := 58.0
const HEAD_H := 0.3
## 普攻命中点离地高度(米): 锤头扫到目标身体中段
const SWEEP_H := 0.45

const C_PINK := Color(1.0, 0.72, 0.80)
const C_JAM := Color(1.0, 0.42, 0.55)

var battle
var rng := RandomNumberGenerator.new()   # 纯演出随机(不碰 sim 的随机流)
var _texs := {}
var _mats := {}


func _init(b) -> void:
	battle = b
	rng.seed = 151115


func tex(path: String) -> Texture2D:
	if not _texs.has(path):
		_texs[path] = load(path)
	return _texs[path]


## 一段 Blender 序列帧: 公告板, 每像素 = 渲染正交宽 / 每帧像素(米)。
func _seq(t: Texture2D, at2d: Vector2, h: float, cols: int, rows: int, base: int, n: int, ortho_m: float, cell_px: int, t0: float, flip: bool = false) -> void:
	_p(t, battle._world_pos(at2d, h), {"hf": cols, "vf": rows, "fr": base, "n": n, "fps": SEQ_FPS, "life": float(n) / SEQ_FPS,
		"px_m": ortho_m / float(cell_px), "a0": 1.0, "a1": 1.0, "prio": 8, "flip": flip, "t0": t0})


## 贴地那张: 平铺在地上(贴图上方 = 离镜头远的一侧, 与 Blender 正上方渲的画面同向 ⇒ 朝向 0), 开深度, 画在龟下面。
func _seq_gnd(t: Texture2D, at2d: Vector2, cols: int, rows: int, base: int, n: int, ortho_m: float, cell_px: int, t0: float, flip: bool = false) -> void:
	_p(t, battle._world_pos(at2d, 0.03), {"hf": cols, "vf": rows, "fr": base, "n": n, "fps": SEQ_FPS, "life": float(n) / SEQ_FPS,
		"px_m": ortho_m / float(cell_px), "a0": 1.0, "a1": 1.0, "flat": true, "yaw": 0.0, "prio": -1, "flip": flip, "t0": t0})


# ════════════════════════════════════════════════════════════════════════════
#  普攻【横扫大锤】命中(参考普攻第 2~6 帧: 闪光 → 圆罩 + 烟顺挥动方向飘 + 碎屑崩出)
# ════════════════════════════════════════════════════════════════════════════
func sweep_hit(tgt: Dictionary, dir: Vector2) -> void:
	if battle._world == null:
		return
	var sw: Texture2D = tex(SWEEP_TEX)
	var swg: Texture2D = tex(SWEEP_GND_TEX)
	var glow: Texture2D = tex(GLOW_TEX)
	var star: Texture2D = tex(STAR_TEX)
	if sw == null or swg == null or glow == null or star == null:
		return                            # 缺图就不画, 不拿别的图顶替
	var t0: float = battle._t
	var at: Vector2 = tgt["pos"] - dir * 8.0
	var hh: float = float(tgt.get("height", 0.0))
	## ① Blender 序列帧: 月牙拖影从尾往头化掉 + 7 块糖块顺挥动方向崩出、落地弹跳 + 糖云(挥向左时水平翻转)
	_seq(sw, at, 0.55 + hh, 8, 2, 0, 16, 3.0, 192, t0, dir.x < 0.0)
	_seq_gnd(swg, at, 8, 2, 0, 16, 4.4, 192, t0, dir.x < 0.0)
	## ② 命中那一下的亮(叠加发光, 序列帧画不出): 星闪 0.1 秒 + 粉白光晕 0.22 秒
	var p: Vector3 = battle._world_pos(at, SWEEP_H + hh)
	_p(star, p, {"texel": 1.5, "life": 0.1, "s0": 1.2, "s1": 0.6, "a0": 1.0, "a1": 0.0, "tint": Color(1.0, 0.96, 0.92), "add": true, "prio": 11, "t0": t0})
	_p(glow, p, {"texel": 2.2, "life": 0.22, "s0": 0.6, "s1": 1.25, "a0": 0.85, "a1": 0.0, "tint": C_PINK, "add": true, "prio": 10, "t0": t0})


# ════════════════════════════════════════════════════════════════════════════
#  技能【糖果锤】砸地(参考 Q 第 7~11 帧; 我们的技能是一下结算, 没有 1 秒后的二段引爆)
#  pos2d = 糖果龟脚下, dir = 砸出去的方向(单位向量)。
# ════════════════════════════════════════════════════════════════════════════
func slam(pos2d: Vector2, dir: Vector2) -> void:
	if battle._world == null:
		return
	var sl: Texture2D = tex(SLAM_TEX)
	var slg: Texture2D = tex(SLAM_GND_TEX)
	var er: Texture2D = tex(ERUPT_TEX)
	var erg: Texture2D = tex(ERUPT_GND_TEX)
	var crack: Texture2D = tex(CRACK_TEX)
	var glow: Texture2D = tex(GLOW_TEX)
	var star: Texture2D = tex(STAR_TEX)
	if sl == null or slg == null or er == null or erg == null or crack == null or glow == null or star == null:
		return
	var t0: float = battle._t
	var head2d: Vector2 = pos2d + dir * HEAD_FWD
	var hp: Vector3 = battle._world_pos(head2d, HEAD_H)
	## ① 锤头落点亮芯(叠加): 星闪 0.12 秒 + 0.07 秒后一团果酱色暖光(参考第 7 帧白黄亮芯 → 第 9~10 帧橙团); 白粉亮光由锤头能量(hammer_energy ③)出, 这里不重复
	_p(star, hp + Vector3(0.0, 0.3, 0.0), {"texel": 2.2, "life": 0.12, "s0": 1.3, "s1": 0.6, "a0": 1.0, "a1": 0.0, "tint": Color(1.0, 0.96, 0.92),
		"add": true, "prio": 12, "t0": t0})
	_p(glow, hp + Vector3(0.0, 0.4, 0.0), {"texel": 2.8, "life": 0.3, "s0": 0.8, "s1": 1.3, "a0": 0.75, "a1": 0.0, "tint": C_JAM,
		"add": true, "prio": 10, "t0": t0 + 0.07})
	## ② 地面裂痕(贴地, 画在龟脚下面; 沿砸出去的方向转; 1.6 秒淡掉): 锤头落点在图上 (40, 48), 图中心 (64, 48) ⇒ 中心往前挪 24 像素
	var cc2d: Vector2 = head2d + dir * (24.0 * CRACK_PX_M / battle.WS)
	_p(crack, battle._world_pos(cc2d, 0.02), {"px_m": CRACK_PX_M, "life": CRACK_LIFE, "s0": 0.9, "s1": 1.0, "a0": 1.0, "a1": 0.0,
		"flat": true, "yaw": -atan2(dir.y, dir.x), "prio": -1, "near": true, "t0": t0})
	## ③ Blender 序列帧(锤头处): 14 块糖块崩飞落地弹跳 + 奶油糖云往上鼓 + 一整圈贴地尘浪往外推
	_seq(sl, head2d, 0.45, 9, 3, 0, 27, 4.6, 256, t0)
	_seq_gnd(slg, head2d, 9, 3, 0, 27, 5.0, 256, t0)
	## ④ 判定区里另外两处同一刻从地里迸出糖块(结算同一刻, 不沿线依次 —— 11-14 用户「三个敌人被同时击飞？怎么可能」那一类);
	##   两种序列各用一次, 不是同一张图摆两遍
	var rng_len: float = CandySystem.HAMMER_RANGE
	var e1: Vector2 = pos2d + dir * (rng_len * 0.6)
	var e2: Vector2 = pos2d + dir * (rng_len * 0.92)
	_seq(er, e1, 0.35, 7, 6, 0, 21, 2.6, 160, t0)
	_seq_gnd(erg, e1, 7, 6, 0, 21, 3.0, 160, t0)
	_seq(er, e2, 0.35, 7, 6, 21, 21, 2.6, 160, t0)
	_seq_gnd(erg, e2, 7, 6, 21, 21, 3.0, 160, t0)


# ════════════════════════════════════════════════════════════════════════════
#  糖果锤【锤头能量】(用户 11-15「你能不能给锤子做个特效？就是它这样子劈下去，它锤子能不能加什么那种特效发光啥？
#   这一股能量砸下去呢？单看这个锤子太太没有感觉了呀」)
#  技能生效那一刻(= 释放帧 5)按锤头逐帧轨迹一次排好: 蓄力聚能(第 5~8 帧, 光晕变大 + 漩涡转 + 光点往锤头吸)→
#  劈下拖出能量光轨(第 7.6~10 帧, 帧间沿曲线插, 每个光点到点才亮、随后变淡 ⇒ 连成一道跟着锤头的光)→ 砸地那一刻锤头能量炸开、
#  火花四溅 → 砸完锤头余光褪到第 12 帧(之后动作可被打断收锤, 不再画)。全是出生参数驱动的粒子(按游戏钟, 直播可重放)。
#  返回建出的节点: 蓄力中被控、这一锤作废时由调用方删掉(CandySystem._sk_candy_hammer)。
#  只给糖果龟自己(释放动作里锤子在帧上); 龟壳复制的飘锤没有这段动作, 不画。
# ════════════════════════════════════════════════════════════════════════════
func hammer_energy(u: Dictionary) -> Array:
	var out: Array = []
	var spr = u.get("sprite", null)
	if battle._world == null or not is_instance_valid(spr) or not (spr is Sprite3D):
		return out
	var ent: Array = AttackRhythm.cast_entry(battle, u, "candyHammer")
	if ent.is_empty():
		return out
	var glow: Texture2D = tex(GLOW_TEX)
	var star: Texture2D = tex(STAR_TEX)
	var swirl: Texture2D = tex(SWIRL_TEX)
	var st: Sprite3D = spr
	if glow == null or star == null or swirl == null or st.texture == null:
		return out
	var rel: int = int(ent[2]) if ent.size() > 2 else 5
	var fps: float = clampf(float(rel) / battle.CAST_WINDUP, AttackRhythm.FPS_MIN, AttackRhythm.FPS_MAX)   # 与 AttackRhythm.cast_begin 同一个算法
	var b: Basis = battle._vfx.cam_basis()
	var geo := {"org": st.global_position, "right": b.x.normalized(), "up": b.y.normalized(), "ps": st.pixel_size,
		"half": float(st.texture.get_width()) / float(maxi(1, st.hframes)) * 0.5,
		"feet": float((TurtleActions.NORM.get("candy", [79.0, 193.0, 79.0]) as Array)[1]), "flip": st.flip_h}
	var now: float = battle._t
	var k_slam: float = float(rel) + CandySystem.HAMMER_SWING_SEC * fps   # 砸地结算那一刻落在第几帧(≈10.6)
	var right: Vector3 = geo["right"]
	var up: Vector3 = geo["up"]
	## ① 蓄力聚能(第 5 ~ 8 帧, 锤在身后低处)
	var pc: Vector3 = _head_world(6.0, geo)
	var dur: float = _frame_t(8.0, now, rel, fps) - now
	out.append(_p(glow, pc, {"texel": 1.5, "life": dur + 0.04, "s0": 0.45, "s1": 1.3, "a0": 0.7, "a1": 1.0, "tint": ENERGY_PINK, "add": true, "prio": 13, "t0": now}))
	out.append(_p(glow, pc, {"texel": 0.6, "life": dur + 0.04, "s0": 0.5, "s1": 1.2, "a0": 0.8, "a1": 1.0, "tint": ENERGY_HOT, "add": true, "prio": 14, "t0": now}))
	out.append(_p(swirl, pc, {"hf": 4, "n": 4, "fps": 4.0 / maxf(0.05, dur), "texel": 1.15, "life": dur + 0.04, "s0": 0.55, "s1": 1.15,
		"a0": 0.65, "a1": 1.0, "tint": ENERGY_HOT, "add": true, "prio": 14, "t0": now}))
	for j in range(8):
		var a: float = TAU * float(j) / 8.0 + rng.randf_range(-0.3, 0.3)
		var off: Vector3 = (right * cos(a) + up * sin(a)) * rng.randf_range(0.35, 0.6)
		var d: float = rng.randf_range(0.6, 1.0) * dur
		out.append(_p(star, pc + off, {"texel": 0.32, "vel": -off / d, "life": d, "s0": 0.7, "s1": 1.1, "a0": 0.35, "a1": 1.0,
			"tint": ENERGY_HOT, "add": true, "prio": 14, "t0": now + (dur - d)}))
	## ② 劈下的能量光轨(第 7.6 ~ 10 帧; 越往下越亮越粗)
	var k: float = 7.6
	while k <= 10.001:
		var w: float = clampf((k - 7.6) / 2.4, 0.0, 1.0)
		var ph: Vector3 = _head_world(k, geo)
		var tk: float = _frame_t(k, now, rel, fps)
		out.append(_p(glow, ph, {"texel": 0.85 + 0.55 * w, "life": 0.17 + 0.07 * w, "s0": 1.0, "s1": 0.5, "a0": 0.5 + 0.45 * w, "a1": 0.0,
			"tint": ENERGY_PINK, "add": true, "prio": 13, "t0": tk}))
		out.append(_p(glow, ph, {"texel": 0.4 + 0.2 * w, "life": 0.11, "s0": 1.0, "s1": 0.6, "a0": 0.95, "a1": 0.0,
			"tint": ENERGY_HOT, "add": true, "prio": 14, "t0": tk}))
		k += 0.2
	for kk in [8.0, 9.0, 10.0]:
		out.append(_p(swirl, _head_world(kk, geo), {"hf": 4, "fr": int(kk) % 4, "n": 1, "texel": 0.85, "life": 1.0 / fps, "s0": 1.0, "s1": 1.1,
			"a0": 1.0, "a1": 0.6, "tint": ENERGY_HOT, "add": true, "prio": 14, "t0": _frame_t(kk, now, rel, fps)}))
	## ③ 砸地那一刻锤头能量炸开 + 火花四溅(在镜头平面里往外 + 往上, 带重力)
	var t_slam: float = _frame_t(k_slam, now, rel, fps)
	var p10: Vector3 = _head_world(10.0, geo)
	out.append(_p(glow, p10, {"texel": 1.5, "life": 0.2, "s0": 0.6, "s1": 1.35, "a0": 1.0, "a1": 0.0, "tint": ENERGY_HOT, "add": true, "prio": 14, "t0": t_slam}))
	out.append(_p(glow, p10, {"texel": 2.2, "life": 0.32, "s0": 0.7, "s1": 1.3, "a0": 0.8, "a1": 0.0, "tint": ENERGY_PINK, "add": true, "prio": 13, "t0": t_slam}))
	for j in range(10):
		var a2: float = PI * (0.05 + 0.9 * float(j) / 9.0) + rng.randf_range(-0.12, 0.12)   # 上半圈
		var v: Vector3 = (right * cos(a2) + up * sin(a2)) * rng.randf_range(2.2, 4.0)
		out.append(_p(star, p10, {"texel": 0.36, "vel": v, "grav": 7.0, "life": rng.randf_range(0.28, 0.42), "s0": 1.0, "s1": 0.4,
			"a0": 1.0, "a1": 0.0, "tint": ENERGY_HOT, "add": true, "prio": 14, "t0": t_slam}))
	## ④ 砸完锤头余光(到第 12 帧, 之后动作可被打断)
	var t_end: float = _frame_t(12.0, now, rel, fps)
	out.append(_p(glow, _head_world(11.0, geo), {"texel": 1.1, "life": maxf(0.1, t_end - t_slam) + 0.15, "s0": 1.0, "s1": 0.7, "a0": 0.8, "a1": 0.0,
		"tint": ENERGY_PINK, "add": true, "prio": 13, "t0": t_slam}))
	return out


## 释放动作第 k 帧(可带小数)开始显示的游戏时刻: 技能生效这一刻(now)正好进释放帧 rel, 之后按 cast_begin 的帧率往下播。
func _frame_t(k: float, now: float, rel: int, fps: float) -> float:
	return now + (k - float(rel)) / fps


## 锤头在第 k 帧(可带小数: 帧间沿 Catmull-Rom 曲线插)的世界坐标。立绘是正对镜头的公告板, 脚底在单位位置:
##   像素(x, y)→ 相机右方向 (x − 半宽)(朝右时取反) + 相机上方向 (脚底行 − y), 再乘每像素米数。
func _head_world(k: float, g: Dictionary) -> Vector3:
	var n: int = HEAD_PX.size()
	var i: int = clampi(int(floor(k)), 0, n - 1)
	var f: float = clampf(k - float(i), 0.0, 1.0)
	var p0: Vector2 = HEAD_PX[maxi(0, i - 1)]
	var p1: Vector2 = HEAD_PX[i]
	var p2: Vector2 = HEAD_PX[mini(n - 1, i + 1)]
	var p3: Vector2 = HEAD_PX[mini(n - 1, i + 2)]
	var f2: float = f * f
	var f3: float = f2 * f
	var px: Vector2 = 0.5 * ((2.0 * p1) + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f3)
	var lx: float = (px.x - float(g["half"])) * (-1.0 if bool(g["flip"]) else 1.0)
	var ly: float = float(g["feet"]) - px.y
	return (g["org"] as Vector3) + (g["right"] as Vector3) * (lx * float(g["ps"])) + (g["up"] as Vector3) * (ly * float(g["ps"]))


## 糖果锤打中的每个敌人身上: 一团果酱色暖光(参考第 9~11 帧被砸的单位身上那团暖光)
func slam_hit(o: Dictionary) -> void:
	if battle._world == null:
		return
	var glow: Texture2D = tex(GLOW_TEX)
	if glow == null:
		return
	var p: Vector3 = battle._world_pos(o["pos"], 0.7 + float(o.get("height", 0.0)))
	_p(glow, p, {"texel": 2.8, "life": 0.26, "s0": 0.7, "s1": 1.25, "a0": 0.9, "a1": 0.0, "tint": C_JAM, "add": true, "prio": 10, "t0": battle._t})


## 粒子材质: 贴图 × 顶点色(modulate 上色 / 变淡)。add = 叠加发光; flat = 贴地(不朝相机, 开深度测试, 画在龟下面);
## near = 最近点采样(彩色小件保持像素清楚; 灰度光晕 / 烟用线性)。按(贴图, 混合, 层级, 贴地, 采样)共用一份。
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


## 一颗粒子。o: hf/vf(帧图格子) · fr(第几格) · n/fps(连放几帧) · texel(码/像素) · vel/grav(米/秒) · life · s0/s1 · a0/a1 ·
##   tint · add · prio · t0 · flat/yaw(贴地 + 朝向) · near(最近点采样) · px_m(每像素米, 序列帧用) · flip(水平翻转)。运动全是游戏钟的函数(battle_render._tick_anim_fx)。
func _p(t: Texture2D, p0: Vector3, o: Dictionary) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = t
	sp.hframes = int(o.get("hf", 1))
	sp.vframes = int(o.get("vf", 1))
	sp.frame = int(o.get("fr", 0))
	sp.pixel_size = float(o["px_m"]) if o.has("px_m") else float(o.get("texel", 2.0)) * battle.WS
	sp.flip_h = bool(o.get("flip", false))
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
