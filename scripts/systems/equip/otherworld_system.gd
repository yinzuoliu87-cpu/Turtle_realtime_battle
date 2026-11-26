class_name OtherworldSystem
extends RefCounted
## otherworld_system.gd —— 136 千面【里世界】(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md §3)
##
## 用户 11-25 夜 / 11-26:「开打第 8 秒随机拽取对面一个人进入一个新里世界…偷取属性」「决斗改为十二秒…从场上消失到另外一个里世界…
##   地图上需要有个按钮，可以调整观众的视角，从主地图切换到里世界」「同时拥有多个千面要拽人的时候，我们只开一个里世界…所有被牵连到的人都会到里世界来」
##   「里世界里面…只存在一方的队伍，另一方被打死完了之后，他们就会回到这个主世界」「偷的属性…在你进入里世界的时候开偷，然后一直持续到这个战场结束」
##
## 做法: 进里世界的单位挂 `_ow = true`, 搬到主岛外的一块独立场地(OW_CENTER); 主世界与里世界互不可见、互不可选、互不挨打
## (`separated(a, b)` —— 选目标 / 范围伤害的入口都过它)。
const OW_AT := 8.0
const OW_SEC := 12.0
const OW_STEAL := [0.03, 0.05, 0.10]


## a 与 b 一个在里世界、一个在主世界 ⇒ 互相看不见
static func separated(a, b) -> bool:
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	return bool((a as Dictionary).get("_ow", false)) != bool((b as Dictionary).get("_ow", false))
