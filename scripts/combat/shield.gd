class_name ShieldMath
extends RefCounted
## 护盾吸收 (SIM · 无节点 · 可 headless 单测) —— combat/ 模块之一。
## 两条伤害路径(_apply_damage / _apply_damage_from)共用同一份 —— 原本各写一份(§3.3 地雷:
## "改伤害逻辑必须两条都改", 漏一处就只在某类伤害下出诡异行为)。收口到这里 → 改盾逻辑只改一处。
##
## 用 class_name(不是主场景的 static 方法): static 挂在场景脚本上、测试经 preload 常量调用时,
## CI 全新签出会在【解析期】报 "Static function not found"(本地因 .godot 缓存已编译而侥幸通过)。
## class_name 全局类在 import 扫描期注册 → CI 可靠解析(与 DamageMath 同族)。

## 普通盾 + aura 储能盾 都吸【全类型】伤害。扣减 u 的盾值(字典按引用), 返回穿盾后剩余伤害。
## 墨迹穿盾(_ink_true)由调用方在盾后单独加, 不进本函数。
static func absorb(u: Dictionary, d: float) -> float:
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	if d > 0.0 and float(u.get("_auraShieldVal", 0.0)) > 0.0:
		var ab2 := minf(float(u["_auraShieldVal"]), d)
		u["_auraShieldVal"] = float(u["_auraShieldVal"]) - ab2
		d -= ab2
	return d
