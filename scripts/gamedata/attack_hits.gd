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
	"pets/animations/ninja/slash.png": 3,       # 7 帧(11-11 第八版, 用户挑 12 / 13 / 18 / 19 / 15 / 22 / 5 号, 「命中针还是用…第十九针」; build_ninja_slash.py)
	"pets/animations/elite/attack.png": 5,      # 12 格(11-11 深渊精英: 站 / 举过头 ×3 / 斜前上 / ★劈到前下 / 收)
	"pets/animations/melee/attack.png": 5,      # 12 帧(11-05 重做 9 帧 → 11-08 重排: 蓄力补一拍、收回每帧两拍)
	"pets/animations/ranged/attack.png": 5,     # 12 格(11-11 海螺炮手: 站 / 前压 ×4 / ★后坐 / 收)
	"pets/animations/reserve/attack.png": 5,    # 12 帧(11-08: AI 补抬手 3 帧 / 收回 5 帧)
	"pets/animations/wraith/attack.png": 2,     # 5 帧
	"vfx/eq096-axe-wood-attack.png": 2,         # 8 帧(斧头兜底表; 按形态的表走 AxeArt._act_rows, 没登记的按 40% 算)
}


## 每帧停多久(拍数; 没登记 = 每帧 1 拍, 匀速)。帧率的单位是「拍 / 秒」: AttackRhythm.begin 用「命中帧之前的拍数 / 前摇秒数」⇒
## 结算那一刻正好进命中帧(与匀速时同一个保证); 命中后的帧照同一拍长往下播, 拍数大 = 停得久。只管画面, 不动结算。
## 忍者(11-11 用户「只要把每一帧慢点播放就可以了，播放这个时间你处理好每一帧的时间」「把一二的这个持续时间稍微拉长一点」):
##   命中前 3 帧分前摇(0.35 秒是结算定的), 第 1、2 帧停久、第 3 帧短; 命中及之后放慢(攻击间隔 1.55 秒)。
##   用户 11-11「把第五帧、第六帧的时间都减少，减少到零点一二秒」「第四帧缩短到零点零九秒」「第一帧增加到零点二零秒」
##   (前 3 帧合起来就是前摇 0.35 秒, 第 1 帧加长 ⇒ 第 2、3 帧按原比例缩短)。
##   前摇 0.35 秒时每帧: 0.20 / 0.087 / 0.063 | ★0.09 / 0.12 / 0.12 / 0.233 秒(整段约 0.91 秒)。
const FRAME_W := {
	"pets/animations/ninja/slash.png": [1.714, 0.745, 0.541, 0.77, 1.03, 1.03, 2.0],
}


## 前 n 帧一共多少拍(w 空 = 匀速, 每帧 1 拍)
static func beats_before(w: Array, n: int) -> float:
	if w.is_empty():
		return float(n)
	var s := 0.0
	for i in range(mini(n, w.size())):
		s += float(w[i])
	return s


## 动作播了 t 秒 → 当前帧下标(按 sd 的 fps 与 frame_w; 播过末帧返回帧数 = 播完)。所有「int(anim_t × fps)」都走这里。
static func frame_of(sd: Dictionary, t: float) -> int:
	var beats: float = t * float(sd.get("fps", 0.0))
	var w: Array = sd.get("frame_w", [])
	if w.is_empty():
		return int(beats)
	var acc := 0.0
	for i in range(w.size()):
		acc += float(w[i])
		if beats < acc:
			return i
	return w.size()


## path = 相对 assets/sprites/ 的帧条路径(与 ACTION_ATTACK 的值同口径); frames = 帧数(登记缺失时按 40% 估)
static func hit_frame(path: String, frames: int) -> int:
	if BY_PATH.has(path):
		return int(BY_PATH[path])
	if TurtleActions.HIT.has(path):
		return int(TurtleActions.HIT[path])
	return clampi(int(round(float(frames) * 0.4)), 1, maxi(1, frames - 1))


static func is_registered(path: String) -> bool:
	return BY_PATH.has(path) or TurtleActions.HIT.has(path)
