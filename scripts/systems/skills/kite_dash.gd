class_name KiteDash
extends RefCounted
## 远程单位冲刺 / 翻滚的落点(2026-11-15)。猎人龟【翻滚】与赛博龟【智能AI】(主动 + 被动躲避)共用。
##
## 用户 11-15:「猎人龟有个技能…闪避…赛博龟有个技能叫智能 AI，他们这个位移你都是一个劲的往后退…感觉不是很合理」
##   「如果你碰到一个那种远程的，别人朝你跑，那不应该就追上去吗？就这个智能 AI 的话，你确定是 OK 吗？」
##   「走位的话你按你思路做吧。」
## 原来: 翻滚三种情况都背离敌人直线滚 250 码(猎人射程 400, 敌人在 300 码一滚就到 550 ⇒ 出射程走回来再退);
##   智能AI 在身边 200 码取 16 点只按「离最近敌人越远越好」打分 ⇒ 每次都往后冲, 冲到墙边才侧移。
## 规则(照 LoL 远程英雄打法: 打近战边打边退, 打远程站自己射程边缘对打, 目标出射程就追):
##   ① 以「离当前目标 IDEAL × 射程」为准: 太近斜着拉开、太远朝它冲(追上去)、刚好侧移换角度
##   ② 只有近战贴身(THREAT_R 码内)才算威胁, 加「离它远」项; 远程靠近不躲
##   ③ 冲完目标仍在射程内(IN_RANGE 余量), 否则重罚; 离墙远; 同样好的两边左右交替, 不总往一边
##   ④ retreat(猎人残血): 往己方最近一名队友的身后(背向敌人质心那一侧)撤, 这时不要求目标在射程内
## 纯函数: 只读单位与场地, 返回落点; 不碰 RNG(左右交替用单位身上的计数) ⇒ 确定性。

const IDEAL := 0.8            # 理想距离 = 0.8 × 自己的有效射程(猎人 400 → 320 码, 赛博 450 → 360 码)
const IN_RANGE := 0.95        # 冲完目标须在 0.95 × 射程以内
const THREAT_R := 200.0       # 近战敌人进这个距离才算贴身威胁
const THREAT_CAP := 320.0     # 「离威胁远」最多算到这么远(再远不加分, 否则又变成一味后退)
const N_DIRS := 16
const W_RANGE := 1.0          # 偏离理想距离每码扣 1 分
const W_OUT := 4.0            # 冲出射程每码再扣 4 分 + OUT_BASE
const OUT_BASE := 200.0
const W_THREAT := 1.2
const W_SIDE := 40.0          # 侧移偏好(本次这一边)
const W_WALL := 0.5           # 离墙每码加 0.5 分(封顶 WALL_CAP)
const WALL_CAP := 160.0
const BEHIND := 90.0          # 残血撤到队友身后多远


## u: 冲刺者 · dist: 冲多远 · opts: {target(默认最近敌人), retreat(bool)}
static func pick(battle, u: Dictionary, dist: float, opts: Dictionary = {}) -> Vector2:
	var me: Vector2 = u["pos"]
	var tgt = opts.get("target", null)
	if tgt == null:
		tgt = battle._targeting._nearest_enemy(u)
	if tgt == null:
		return me
	var rng: float = float(battle._eff_range(u))
	var ideal: float = rng * IDEAL
	var tp: Vector2 = tgt["pos"]
	## ② 近战贴身威胁
	var threat = null
	var td: float = THREAT_R
	var cen := Vector2.ZERO
	var cn := 0
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false):
			continue
		cen += o["pos"]
		cn += 1
		if o.get("melee", false):
			var dd: float = DetMath.dist(me, o["pos"])
			if dd < td:
				td = dd
				threat = o
	if cn > 0:
		cen /= float(cn)
	## ④ 残血撤退锚点: 最近一名队友身后(背向敌人质心)
	var retreat: bool = bool(opts.get("retreat", false))
	var anchor = null
	if retreat and cn > 0:
		var ad: float = INF
		for a in battle._targeting._allies_of(u, false):
			if not a.get("alive", false) or a.get("is_trainer", false) or a.get("_isEgg", false):
				continue
			var d2: float = DetMath.dist(me, a["pos"])
			if d2 < ad:
				ad = d2
				anchor = a
	var behind := Vector2.ZERO
	if anchor != null:
		var away: Vector2 = (anchor["pos"] as Vector2) - cen
		behind = (anchor["pos"] as Vector2) + (DetMath.norm(away) if DetMath.vlen(away) > 0.1 else Vector2.ZERO) * BEHIND
	## ③ 左右交替: 每次冲刺换一边作为「侧移偏好」的那一边
	var n_side: int = int(u.get("_kite_side", 0))
	u["_kite_side"] = n_side + 1
	var side: float = 1.0 if n_side % 2 == 0 else -1.0
	var to_t: Vector2 = tp - me
	to_t = DetMath.norm(to_t) if DetMath.vlen(to_t) > 0.1 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-to_t.y, to_t.x) * side
	var ar: Rect2 = battle.ARENA
	var best: Vector2 = me
	var best_s: float = -INF
	for i in range(N_DIRS):
		var ang: float = TAU * float(i) / float(N_DIRS)
		var dv := Vector2(DetMath.dcos(ang), DetMath.dsin(ang))
		var c: Vector2 = ArenaShape.clamp_in(me + dv * dist, ar, 50, 40)
		var mv: Vector2 = c - me
		var dt: float = DetMath.dist(c, tp)
		var s: float = 0.0
		if anchor != null:
			s -= DetMath.dist(c, behind) * 2.0               # ④ 残血: 越接近队友身后越好
		else:
			s -= absf(dt - ideal) * W_RANGE                  # ① 理想距离
			if dt > rng * IN_RANGE:
				s -= OUT_BASE + (dt - rng * IN_RANGE) * W_OUT   # ③ 冲出射程重罚
		if threat != null:
			s += minf(DetMath.dist(c, threat["pos"]), THREAT_CAP) * W_THREAT   # ② 只躲近战
		if DetMath.vlen(mv) > 1.0:
			s += DetMath.dot(DetMath.norm(mv), perp) * W_SIDE   # ③ 侧移偏好(交替边)
		var dw: float = minf(minf(c.x - ar.position.x, ar.end.x - c.x), minf(c.y - ar.position.y, ar.end.y - c.y))
		s += minf(dw, WALL_CAP) * W_WALL                     # ③ 离墙远
		s += DetMath.vlen(mv) * 0.05                         # 同分时选真走得动的(被墙夹住的方向几乎不动)
		if s > best_s:
			best_s = s
			best = c
	return best


## 智能AI 被动躲避的触发: 只有近战敌人贴身(within 码)才算 —— 远程靠近不躲(用户 11-15「碰到远程的…不应该就追上去吗」)
static func melee_within(battle, u: Dictionary, within: float) -> bool:
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false) and o.get("melee", false) and DetMath.dist(u["pos"], o["pos"]) < within:
			return true
	return false
