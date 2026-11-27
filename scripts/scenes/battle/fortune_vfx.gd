extends "res://scripts/scenes/battle/candy_vfx.gd"
## fortune_vfx.gd —— 财神龟专属特效(2026-11-27 重做; 方案书 docs/plans/20261126d-财神龟重做.md「特效重做」, 分段表在那里)。
## 用户 11-27「所有角色的动画都是没问题的，要改的只有特效」「普攻打中这个刀光肯定是要改的…一二三四都需要改」。
## 只管画面: 不读写对局状态(唯一例外: 普攻命中时把目标的 `_spark_t` 往后推一点, 挡掉通用星芒火花 —— battle_vfx._hit_spark 读它, 纯演出)。
## 继承糖果龟演出层拿粒子工具(_p / _mat / tex / rng): 粒子运动全是游戏钟的函数(battle_render._tick_anim_fx), 直播录得到。
## 素材(全部 Aseprite 后台脚本逐像素画, CLAUDE.md §10 第 7 条②; 源脚本与 .aseprite 在 tools/assetgen/ase/):
##   fortune-strike-slash 金色新月剑光 6×64 · fortune-strike-star 命中金星 4×24 · fortune-coin-spin 翻转铜钱 8×16 ·
##   fortune-dice-roll 翻滚骰子 6×24 · fortune-beam 剑尖光柱 8×(16×128); 金盾罩 = 网格 + assets/shaders/fortune_shield.gdshader;
##   光晕 candy-glow(白色圆斑, 底层小元素共用, §10 第 5 条)。
const F_SLASH := "res://assets/sprites/vfx/fortune-strike-slash.png"
const F_STAR := "res://assets/sprites/vfx/fortune-strike-star.png"
const F_COIN := "res://assets/sprites/vfx/fortune-coin-spin.png"
const F_DICE := "res://assets/sprites/vfx/fortune-dice-roll.png"
const F_BEAM := "res://assets/sprites/vfx/fortune-beam.png"
const F_GLOW := "res://assets/sprites/vfx/candy-glow.png"
const SHIELD_SHADER: Shader = preload("res://assets/shaders/fortune_shield.gdshader")
const SHIELD_SP := ["t", "grow", "fade", "hit"]
const GOLD := Color(1.0, 0.82, 0.32)
const COIN_M := 0.38          # 铜钱直径(米) —— 跟壳上嵌的金币差不多
const POUCH_H := 0.62         # 腰间钱袋离地(米)
const DOME_R := 0.85          # 金盾罩半径 / 高(米): 罩住 1.33 米高的身体
const DOME_H := 1.55
var _domes: Array = []        # {u, node, t0, life}


func _init(b) -> void:
	super(b)
	rng.seed = 261127


func _coin(p0: Vector3, vel: Vector3, life: float, t0: float, a1: float = 0.2, grav: float = 10.0) -> void:
	_p(tex(F_COIN), p0, {"hf": 8, "n": 8, "fps": 20.0, "life": life, "px_m": COIN_M / 16.0, "vel": vel, "grav": grav,
		"near": true, "prio": 10, "a0": 1.0, "a1": a1, "t0": t0})


func _glow(p0: Vector3, size_m: float, life: float, t0: float, s1: float = 1.4, a0: float = 0.8, vel: Vector3 = Vector3.ZERO) -> void:
	_p(tex(F_GLOW), p0, {"px_m": size_m / 32.0, "life": life, "s0": 0.5, "s1": s1, "a0": a0, "a1": 0.0, "tint": GOLD,
		"add": true, "prio": 7, "vel": vel, "t0": t0})


# ════════════════ ① 普攻·金剑命中: 金色新月剑光 + 命中金星 + 迸出 3 枚铜钱 ════════════════
func strike(u: Dictionary, tgt: Dictionary) -> void:
	if battle._world == null:
		return
	var dir: float = 1.0 if float(tgt["pos"].x) >= float(u["pos"].x) else -1.0
	var hh: float = float(tgt.get("height", 0.0))
	var at: Vector2 = tgt["pos"]
	var t0: float = battle._t
	tgt["_spark_t"] = battle._t + 0.08   # 有专属命中特效: 挡掉通用星芒(纯演出键)
	_p(tex(F_SLASH), battle._world_pos(at - Vector2(dir * 12.0, 0.0), 0.75 + hh), {"hf": 6, "n": 6, "fps": 20.0, "life": 0.3,
		"px_m": 2.0 / 64.0, "flip": dir < 0.0, "near": true, "prio": 9, "a0": 1.0, "a1": 0.7, "t0": t0})
	_p(tex(F_STAR), battle._world_pos(at, 0.6 + hh), {"hf": 4, "n": 4, "fps": 16.0, "life": 0.25, "px_m": 0.8 / 24.0,
		"near": true, "prio": 11, "a0": 1.0, "a1": 1.0, "t0": t0 + 0.03})
	for i in range(3):
		_coin(battle._world_pos(at, 0.6 + hh), Vector3(dir * (0.7 + 0.45 * float(i)), 2.3 + 0.35 * float(i % 2), (float(i) - 1.0) * 0.5),
			0.5, t0 + 0.04 + 0.02 * float(i))


# ════════════════ ② 骰子: 头顶骰子翻滚落定 → N 枚铜钱喷泉撒下 → 身后暖金光点往上飘(回血) ════════════════
func dice(u: Dictionary, n_gold: int) -> void:
	if battle._world == null:
		return
	var t0: float = battle._t
	var hh: float = float(u.get("height", 0.0))
	var head: Vector3 = battle._world_pos(u["pos"], 1.95 + hh)
	_p(tex(F_DICE), head, {"hf": 6, "n": 6, "fps": 20.0, "life": 0.85, "px_m": 0.62 / 24.0, "vel": Vector3(0.0, 0.5, 0.0),
		"near": true, "prio": 11, "a0": 1.0, "a1": 0.0, "t0": t0})
	for i in range(n_gold):
		var a: float = TAU * float(i) / float(maxi(1, n_gold)) + 0.4
		_coin(head, Vector3(cos(a) * 1.3, 1.6 + 0.25 * float(i % 3), sin(a) * 0.7), 0.75, t0 + 0.12 + 0.03 * float(i), 0.3, 9.0)
	for i in range(8):   # 回血: 身后一圈小光点往上飘(细小半透明, 不盖身体)
		var a2: float = TAU * float(i) / 8.0
		var p: Vector3 = battle._world_pos(u["pos"] + Vector2(cos(a2) * 22.0, -8.0 + sin(a2) * 6.0), 0.25 + 0.12 * float(i % 3) + hh)
		_glow(p, 0.22, 0.8, t0 + 0.1 + 0.05 * float(i), 0.4, 0.75, Vector3(0.0, 1.3, 0.0))


# ════════════════ ③ 梭哈: 四周铜钱往身上聚(押上全部)→ 金盾罩 / 金盾: 金盾罩 ════════════════
func allin_charge(u: Dictionary, coins: int) -> void:
	if battle._world == null:
		return
	var t0: float = battle._t
	var n: int = clampi(coins, 1, 12)
	var pouch: Vector3 = battle._world_pos(u["pos"], POUCH_H)
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var p0: Vector3 = battle._world_pos(u["pos"] + Vector2(cos(a) * 70.0, sin(a) * 30.0), 0.5 + 0.5 * float(i % 3))
		var dur: float = 0.5 - 0.02 * float(i % 4)
		_coin(p0, (pouch - p0) / dur, dur, t0 + 0.02 * float(i), 1.0, 0.0)
	gold_dome(u, ALLIN_DOME_SEC)


const ALLIN_DOME_SEC := 6.0   # = FortuneSystem.ALLIN_SHIELD_SEC(梭哈首发金盾); 盾先破就先碎


func gold_dome(u: Dictionary, sec: float) -> void:
	if battle._world == null:
		return
	for d in _domes:   # 同一人身上已有罩: 续时间, 不叠两层
		if is_same(d["u"], u):
			d["life"] = maxf(float(d["life"]), battle._t - float(d["t0"]) + sec)
			return
	var mi := Cent3dVfx.node(battle._world, Cent3dVfx.gen_dome(DOME_R, DOME_H, 40, 10), SHIELD_SHADER, SHIELD_SP, {"grow": 0.0}, 8)
	mi.position = battle._world_pos(u["pos"], 0.0)
	_domes.append({"u": u, "node": mi, "t0": battle._t, "life": sec, "sh": float(u.get("shield", 0.0))})
	_glow(battle._world_pos(u["pos"], 0.8), 1.6, 0.3, battle._t, 1.6, 0.7)


## 每帧(battle_render._tick_fortune): 罩子跟人 / 撑开 / 挨打亮一下 / 盾没了或到期碎成铜钱
func tick() -> void:
	var keep: Array = []
	for d in _domes:
		var u: Dictionary = d["u"]
		var mi = d["node"]
		if mi == null or not is_instance_valid(mi):
			continue
		var el: float = battle._t - float(d["t0"])
		var sh: float = float(u.get("shield", 0.0))
		if not u.get("alive", false) or el >= float(d["life"]) or sh <= 0.5:
			_dome_break(u, mi)
			continue
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		(mi as MeshInstance3D).position = battle._world_pos(u["pos"], 0.0)
		var g: float = clampf(el / 0.22, 0.0, 1.0)
		m.set_shader_parameter("t", el)
		m.set_shader_parameter("grow", 1.0 - (1.0 - g) * (1.0 - g))
		var hit: float = float(d.get("hit", 0.0))
		if sh < float(d["sh"]) - 0.5:
			hit = 1.0                    # 盾被打掉一截: 整个罩亮一下
		d["hit"] = maxf(0.0, hit - 0.12)
		m.set_shader_parameter("hit", float(d["hit"]))
		d["sh"] = sh
		keep.append(d)
	_domes = keep


func _dome_break(u: Dictionary, mi) -> void:
	var c: Vector2 = u["pos"]
	var t0: float = battle._t
	for i in range(12):   # 罩面碎成铜钱往四周掉
		var a: float = TAU * float(i) / 12.0
		var p0: Vector3 = battle._world_pos(c + Vector2(cos(a) * 40.0, sin(a) * 18.0), 0.6 + 0.35 * float(i % 3))
		_coin(p0, Vector3(cos(a) * 1.1, 1.2 + 0.3 * float(i % 2), sin(a) * 0.6), 0.6, t0 + 0.015 * float(i), 0.0, 9.0)
	_free_node(mi)


func _free_node(n) -> void:
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()


# ════════════════ ④ 招财进宝: 剑尖冲天光柱 → 抽到的装备图标(升星 = 金星)从天上落进身上 → 金环 + 零星铜钱 ════════════════
func buy(u: Dictionary, iid: String, stars: int) -> void:
	if battle._world == null:
		return
	var t0: float = battle._t
	var hh: float = float(u.get("height", 0.0))
	var dir: float = -1.0 if bool(u.get("face_right", true)) == false else 1.0
	var tip: Vector2 = u["pos"] + Vector2(dir * 10.0, 0.0)
	var bt: Texture2D = tex(F_BEAM)
	if bt != null:
		var b := _p(bt, battle._world_pos(tip, 1.55 + 2.0 + hh), {"hf": 8, "n": 8, "fps": 16.0, "life": 0.5, "px_m": 4.0 / 128.0,
			"near": true, "prio": 9, "a0": 1.0, "a1": 0.6, "t0": t0})
		b.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var top: Vector3 = battle._world_pos(u["pos"], 3.6 + hh)
	var land: Vector3 = battle._world_pos(u["pos"], 0.9 + hh)
	var fall: float = 0.6
	if iid != "":
		var row: Dictionary = DataRegistry.phase2_equipment_by_id.get(iid, {})
		var ip: String = "res://assets/sprites/" + str(row.get("img", ""))
		if ResourceLoader.exists(ip):
			var it: Texture2D = tex(ip)
			_glow(top, 1.1, fall, t0 + 0.12, 1.0, 0.65, (land - top) / fall)
			_p(it, top, {"px_m": 1.1 / float(maxi(1, it.get_height())), "life": fall, "vel": (land - top) / fall,
				"near": true, "prio": 11, "a0": 1.0, "a1": 1.0, "t0": t0 + 0.12})
	else:
		for i in range(maxi(1, stars)):   # 升星: 落下对应个数的金星
			var off := Vector3((float(i) - float(stars - 1) * 0.5) * 0.45, 0.0, 0.0)
			_p(tex(F_STAR), top + off, {"hf": 4, "n": 1, "fps": 1.0, "life": fall, "px_m": 1.1 / 24.0, "vel": (land - top) / fall,
				"near": true, "prio": 11, "a0": 1.0, "a1": 1.0, "t0": t0 + 0.12 + 0.05 * float(i)})
	var tl: float = t0 + 0.12 + fall
	_glow(land, 1.4, 0.35, tl, 1.6, 0.7)   # 落进身上那一下
	_p(tex(F_STAR), land, {"hf": 4, "n": 4, "fps": 14.0, "life": 0.3, "px_m": 1.2 / 24.0, "near": true, "prio": 12, "a0": 1.0, "a1": 1.0, "t0": tl})
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		_coin(land, Vector3(cos(a) * 1.2, 1.8, sin(a) * 0.6), 0.55, tl + 0.02 * float(i), 0.2, 9.0)


# ════════════════ ⑤ 聚宝盆: 脚边地面蹦出 N 枚铜钱弹进腰间钱袋, 钱袋闪一下 ════════════════
func pouch(u: Dictionary, n: int) -> void:
	if battle._world == null:
		return
	var t0: float = battle._t
	var hh: float = float(u.get("height", 0.0))
	var pc: Vector3 = battle._world_pos(u["pos"], POUCH_H + hh)
	var g: float = 12.0
	for i in range(clampi(n, 1, 9)):
		var a: float = TAU * float(i) / float(maxi(1, n)) + 0.3
		var p0: Vector3 = battle._world_pos(u["pos"] + Vector2(cos(a) * 34.0, 6.0 + sin(a) * 12.0), 0.05 + hh)
		var dur: float = 0.36
		var d: Vector3 = pc - p0
		var v := Vector3(d.x / dur, (d.y + 0.5 * g * dur * dur) / dur, d.z / dur)   # 抛物线正好落进钱袋
		_coin(p0, v, dur, t0 + 0.035 * float(i), 1.0, g)
	_glow(pc, 0.55, 0.25, t0 + 0.36 + 0.035 * float(n), 1.3, 0.85)
