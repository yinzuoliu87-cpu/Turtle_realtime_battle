class_name LineupPos
extends RefCounted
## 阵容站位(2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §2)。
##
## 用户 10-19「站位改为在背包里做好了」: 站位不再在对局里临时摆, 而是在背包里摆好、随阵容一起进快照。
##   原因(10-18 周日实战): 对局里摆的站位只在本机生效、不进快照 ⇒ 「本地因为站位赢了，服务器判输」。
##   ⇒ 站位是阵容格子(`dual_lineup[路][i]`)上的一个字段 `off` = [dx, dy],
##      相对【本方队形中心】(左方 = 场地中心 x - FORMATION_DX)的偏移, 以左方视角记; 右方镜像 x。
##   没有 `off`(旧存档 / 旧快照 / 机器人)⇒ 原来的固定队形(竖排, 间距 ROW_DY)。
## ★整数: 跨设备逐位一致(服务器裁判与手机重算要同一个数), 进快照前就取整, 不让 JSON 往返带出小数尾巴。
## ★这里只定「想站哪」; 真正落点在开打时再按那张地图的岛形 + 障碍夹一遍(`DualLaneFlow.clamp_place_side`)。

## 队形中心离场地中心多远(与 `dual_lane_flow._dl_build_lane_field` 的 ±420 同一个数)。
const FORMATION_DX := 420
## 默认队形的行距(与 `battle_spawn._spawn_lane_side` 同一个数)。
const ROW_DY := 154
## 可摆范围(偏移, 左方视角)。场地 1596×728、中心 (868,474): 我方半场 x ∈ [130, 748] ⇒ dx ∈ [-318, 300];
##   y ∈ [170, 778] ⇒ dy ∈ [-304, 304]。各留一点余量, 圆岛四角与障碍由开打时的夹取处理。
const DX_MIN := -300
const DX_MAX := 280
const DY_MIN := -290
const DY_MAX := 290


## 默认队形第 i 个(共 n 个)的偏移。
static func default_off(i: int, n: int) -> Vector2i:
	return Vector2i(0, int(round((float(i) - float(n - 1) / 2.0) * float(ROW_DY))))


## 一个阵容格子的偏移: 有 `off` 用它(钳进可摆范围), 没有用默认队形。
static func off_of(spec, i: int, n: int) -> Vector2i:
	if spec is Dictionary and (spec as Dictionary).get("off") is Array and ((spec as Dictionary)["off"] as Array).size() == 2:
		var a: Array = (spec as Dictionary)["off"]
		return clamp_off(Vector2i(int(a[0]), int(a[1])))
	return default_off(i, n)


static func clamp_off(o: Vector2i) -> Vector2i:
	return Vector2i(clampi(o.x, DX_MIN, DX_MAX), clampi(o.y, DY_MIN, DY_MAX))


## 偏移 → 场上坐标。`base` = 本方队形中心; 右方镜像 x。
static func to_field(base: Vector2, off: Vector2i, side: String) -> Vector2:
	var sx := 1.0 if side == "left" else -1.0
	return base + Vector2(float(off.x) * sx, float(off.y))


## 写进格子的形态(整数数组, JSON / var_to_bytes 往返都不变)。
static func pack(o: Vector2i) -> Array:
	var c := clamp_off(o)
	return [c.x, c.y]


## ── 机器人的站位(2026-10-19) ──
## 用户 10-04「不能让玩家知道是机器人」: 真人快照带站位之后, 机器人一个不带 = 一眼认得出
##   (门禁 verify_bot_snapshot_shape 逐层比键)。⇒ 机器人从几种常见队形里挑一种, 再加一点抖动, 像人摆的。
## ★用 ghost_id 的哈希做种子, **不吃** make_bot 的 rng —— 吃了会改变它后面所有随机(名字 / 号 / 装备)。
const BOT_FORMATIONS := [
	[Vector2i(0, -154), Vector2i(0, 0), Vector2i(0, 154)],          # 竖排(默认)
	[Vector2i(-60, -150), Vector2i(80, 0), Vector2i(-60, 150)],     # 楔形
	[Vector2i(-120, -120), Vector2i(40, 0), Vector2i(-120, 120)],   # 后压
	[Vector2i(0, -240), Vector2i(0, 0), Vector2i(0, 240)],          # 拉开
	[Vector2i(120, -140), Vector2i(160, 0), Vector2i(120, 140)],    # 前压
]
const BOT_JITTER := 24


## 第 i 个单位(该路按「统领在前、小将在后」排)的机器人站位。
static func bot_off(seed_str: String, lane: String, i: int) -> Vector2i:
	var h: int = hash("%s|%s" % [seed_str, lane])
	var f: Array = BOT_FORMATIONS[absi(h) % BOT_FORMATIONS.size()]
	var base: Vector2i = f[clampi(i, 0, f.size() - 1)]
	var hj: int = hash("%s|%s|%d" % [seed_str, lane, i])
	var jx: int = (absi(hj) % (BOT_JITTER * 2 + 1)) - BOT_JITTER
	var jy: int = (absi(hj / 97) % (BOT_JITTER * 2 + 1)) - BOT_JITTER
	return clamp_off(base + Vector2i(jx, jy))


## 给一份(机器人)快照补站位: 统领写 `leader_off`, 小将写各自的 `off`。已有的不动。
static func fill_bot_offsets(snap: Dictionary, seed_str: String) -> void:
	var la: Dictionary = snap.get("lane_assign", {}) if snap.get("lane_assign") is Dictionary else {}
	var mn: Dictionary = snap.get("minions", {}) if snap.get("minions") is Dictionary else {}
	var lo: Dictionary = snap.get("leader_off", {}) if snap.get("leader_off") is Dictionary else {}
	for lane in ["top", "bottom"]:
		var i := 0
		for pid in (la.get(lane, []) if la.get(lane) is Array else []):
			if not lo.has(str(pid)):
				lo[str(pid)] = pack(bot_off(seed_str, lane, i))
			i += 1
		for m in (mn.get(lane, []) if mn.get(lane) is Array else []):
			if m is Dictionary and not (m as Dictionary).has("off"):
				(m as Dictionary)["off"] = pack(bot_off(seed_str, lane, i))
			i += 1
	snap["leader_off"] = lo
