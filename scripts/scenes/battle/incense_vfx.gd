class_name IncenseVfx
extends RefCounted
## incense_vfx.gd — 093 香火石的演出层　【主会话独占】
##
## 三个入口, 全部**零素材**(程序化几何 + 现成的通用原语):
##   · `mark_carved(u, marks)`  刻成一道痕: 石碑金纹一闪 + 刻痕数飘字
##   · `empower_burst(u)`       主动就绪: 携带者脚下腾起三缕香火
##   · `empower_hit(u, tgt)`    强化普攻命中: 目标身上一圈金环
##
## ★为什么演出层与结算层分开(CLAUDE.md §3.5):
##   数值测试**不许依赖任何 tween 跑完** —— 无头 CI 下 `create_tween()` 推进不稳,
##   本地永远复现不出来(`verify_pirate_hook` 为此连红三次)。
##   所以 IncenseStoneSystem 里的伤害/刻痕**全部即时结算**, 这里只负责好看;
##   本文件的每个入口都能被单独调用(供门禁与 VFXPREVIEW 用), 不参与任何判定。
##
## ★香火的视觉母题: **金红双色 + 向上飘散**。与 092 毒蛾茧的紫绿下沉、
##   094 祖龟碑的灰蓝厚重区分开 —— 三件同为遗物, 同场时要一眼分得出是谁在响。

const GOLD := Color(1.0, 0.82, 0.42, 0.95)     # 香火金
const EMBER := Color(0.98, 0.44, 0.20, 0.85)   # 香火红

var battle


func _init(b) -> void:
	battle = b


## 刻成一道痕。marks = 刻完之后的总数(飘字要显示它)。
func mark_carved(u: Dictionary, marks: int) -> void:
	if not (u is Dictionary) or not u.get("alive", false):
		return
	var p: Vector2 = u.get("pos", Vector2.ZERO)
	# 金纹一闪: 由内向外的两道环, 第二道慢半拍 ⇒ 读起来像"刻进去"而不是"炸开"
	battle._skill_ring(p, GOLD, 34.0)
	battle._pending_shots.append({"delay": 0.10, "fn": func() -> void:
		battle._skill_ring(p, EMBER, 52.0), "src": u})
	# 刻痕数飘字。★满 300 时改文案 —— 到顶了却还在跳"+1"是最容易被当成 bug 的那种表现
	var txt := ("香火 %d" % marks) if marks < IncenseStoneSystem.MARK_CAP else "香火 满"
	battle._vfx._float_text(p + Vector2(0.0, -18.0), txt, GOLD, false, "buff", "")


## 主动就绪: 脚下腾起三缕香火(三个错开的小环, 高度依次抬高)。
func empower_burst(u: Dictionary) -> void:
	if not (u is Dictionary) or not u.get("alive", false):
		return
	var p: Vector2 = u.get("pos", Vector2.ZERO)
	for i in range(3):
		var dx: float = [-14.0, 0.0, 14.0][i]
		battle._pending_shots.append({"delay": 0.06 * i, "fn": func() -> void:
			battle._skill_ring(p + Vector2(dx, -6.0 * i), GOLD if i != 1 else EMBER, 16.0 + 4.0 * i),
			"src": u})


## 强化普攻命中: 目标身上一圈金环(比普通命中大一圈, 让"这一下是强化的"读得出来)。
func empower_hit(_u: Dictionary, tgt: Dictionary) -> void:
	if not (tgt is Dictionary) or not tgt.get("alive", false):
		return
	battle._skill_ring(tgt.get("pos", Vector2.ZERO), GOLD, 30.0)
