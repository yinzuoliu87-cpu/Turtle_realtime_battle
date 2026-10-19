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
## ★这里只定「想站哪」; 真正落点在开打时再按那张地图的岛形 + 障碍夹一遍(`DualLaneFlow._dl_clamp_place`)。

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
