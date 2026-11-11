class_name AttackHits
extends RefCounted
## 普攻帧条的「命中帧」—— 普攻三段: 前摇(举起)→ 命中(伤害 + 命中特效 + 对方受击同一帧)→ 后摇(收手)。
## 用户 2026-11-05:「英雄在平 A 的时候，应该是有一个攻击前摇，然后命中，然后攻击后摇…比方说盖伦…先是举起来这个剑，
##   然后砍到一半…敌方身上出现命中特效…继续挥剑…直到收手…近战小将…站位待机动画，然后突然戳一下…又回到待机动画」。
## 根因(11-05 查): sim 本来就有前摇(状态 "windup", 攻击间隔 × ATK_WINDUP_PCT, 随攻速缩短), 但普攻帧条是在前摇**结束**
##   (= 伤害结算)才从第 0 帧开播 ⇒ 前摇期间站着不动、结算时「突然戳一下」、命中特效落在动作第一帧。
## 现在: AttackRhythm.begin 在前摇**开始**就播, 帧率 = 命中帧 / 前摇秒数 ⇒ 结算那一刻正好显示命中帧。
## 这里登记手量的帧条: 命中帧 = 本体往前(美术朝左)伸得最远的那一帧(11-05 逐帧量 alpha 包围盒左缘)。
## 外包 11 只的命中帧在 TurtleActions.HIT(build_spine_actions.py 生成)。门禁 verify_attack_rhythm 要求每张普攻帧条都登记了。
## 11-08 起小将与幽灵按 11-07 的节奏重排(站姿 → 蓄力 2 → 挥动 2 ~ 3 → 命中 → 停 2 → 收回 4; 用户 11-08「攻击前摇，攻击后摇，
##   然后中间就是就慢一点」), 生成脚本 tools/assetgen/build_attack_rhythm.py 打印命中帧, 抄到这里。
const BY_PATH := {
	"pets/animations/ghost/attack.png": 5,      # 12 帧(11-08 重排: 命中后定住 2 拍、收回 4 拍)
	"pets/animations/ninja/slash.png": 4,       # 9 帧(11-11 第六版, 用户定: 第 5 针命中、前 4 后 4; build_ninja_slash.py)
	"pets/animations/elite/attack.png": 5,      # 12 格(11-11 深渊精英: 站 / 举过头 ×3 / 斜前上 / ★劈到前下 / 收)
	"pets/animations/melee/attack.png": 5,      # 12 帧(11-05 重做 9 帧 → 11-08 重排: 蓄力补一拍、收回每帧两拍)
	"pets/animations/ranged/attack.png": 5,     # 12 格(11-11 海螺炮手: 站 / 前压 ×4 / ★后坐 / 收)
	"pets/animations/reserve/attack.png": 5,    # 12 帧(11-08: AI 补抬手 3 帧 / 收回 5 帧)
	"pets/animations/wraith/attack.png": 2,     # 5 帧
	"vfx/eq096-axe-wood-attack.png": 2,         # 8 帧(斧头兜底表; 按形态的表走 AxeArt._act_rows, 没登记的按 40% 算)
}


## path = 相对 assets/sprites/ 的帧条路径(与 ACTION_ATTACK 的值同口径); frames = 帧数(登记缺失时按 40% 估)
static func hit_frame(path: String, frames: int) -> int:
	if BY_PATH.has(path):
		return int(BY_PATH[path])
	if TurtleActions.HIT.has(path):
		return int(TurtleActions.HIT[path])
	return clampi(int(round(float(frames) * 0.4)), 1, maxi(1, frames - 1))


static func is_registered(path: String) -> bool:
	return BY_PATH.has(path) or TurtleActions.HIT.has(path)
