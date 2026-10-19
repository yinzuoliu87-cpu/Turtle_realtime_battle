class_name SimAutopilot
extends RefCounted
## autopilot.gd — 模拟号自动驾驶的**开关**(`SIM_AUTOPILOT`)。
##
## ★2026-10-19 起它在战斗里一件事都不用干了:
##   原来唯一的动作是「进了摆位屏, 停 60 帧, 替玩家按那颗『开始战斗』」。
##   用户 10-19「我想在背包里实现站位修改，这样在对局内将不再有拖动站位环节」⇒ 对局里没有摆位屏,
##   开场演出完直接开打(`dual_lane_flow._dl_enter_place`), 没有任何按钮要人按 ⇒ 那段驾驶整个删了。
##   「不带开关时对局停在摆位屏等人点」那条门禁(旧 verify_autopilot)也一起换成了
##   `tests/verify_no_place_stage.gd`: 不管开不开开关, 对局都自己开打。
## ★留下的只有开关本身: 周日决赛日的自动驾驶(`autopilot_finals.gd` / `SimFinalsPilot`)与
##   `sim_driver.gd` 还靠它判「这是不是模拟窗口」。

const ENV := "SIM_AUTOPILOT"


static func enabled() -> bool:
	## 空白串 = 停用(与 `TURTLE_SUPABASE=" "` 同一个约定) ⇒ 门禁能跑"正常流程"那一半。
	return OS.get_environment(ENV).strip_edges() != ""
