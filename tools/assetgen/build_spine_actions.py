# -*- coding: utf-8 -*-
"""tools/assetgen/build_spine_actions.py — 外包 11 只龟的动作帧(普攻 / 受击 / 阵亡), 在画师原骨骼上写关键帧再渲成像素序列帧(2026-11-05)。

方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.3(用户 11-05「不请原画师…在这个像素序列帧上面进行创作…趴着的也可以去…做这个攻击等等」)。
做法: 画师的待机动画原样拷一份, 只把**身体骨骼**(main / neck / head / shell / tail / 四条腿的 IK 目标骨)的时间轴换成动作关键帧;
  画师的特效时间轴(闪电 / 火焰 / 壳光 / 星星…)照留, 动作里特效照样在动。部件全是画师那一批, 风格天然一致。
  关键帧按 15fps「逐帧定姿」写(每帧一个关键帧 = 手工逐帧摆姿势), 求值器 spine_eval.py(已与 Spine 官方运行库逐帧对账)渲。
  腿有 IK: 身体前冲 / 下沉时脚钉在地上、腿自己弯 —— 画师装的骨, 我们只动目标。
动作:
  attack_melee  近战(小龟 / 竹叶 / 彩虹 / 财神 / 石头): 后缩蓄力 3 帧 → 第 4 帧前冲咬中 → 收回(游戏在前摇开始就播, 命中帧对上伤害结算)
  attack_ranged 远程(闪电 / 凤凰 / 天使 / 寒冰 / 熔岩): 缩颈蓄力 → 探头喷射 + 身体后坐 → 回正
  hurt          受击: 被打退 + 压扁 + 仰头 + 眯眼(画师的眨眼部件) → 回正
  death         阵亡: 有 spine_src/<龟>/ai_death/ 的用 PixelLab 生成帧(趴倒 + 头贴地 + 闭眼, 锁原调色板, 见 ai_death_frames);
                没有的(龟壳)走骨骼: 刚体倒下(转 root, 不拧网格), 末帧定住(时长 ≥ 游戏阵亡淡出)
  ★头 / 脖子转角 ≤ HEAD_MAX(6°): 画师的头是加权网格, 转大了脸会被拧歪(用户 11-05「这个头低下来很诡异」)
  龟壳(纯逐帧, 只有 main / shell / efx 三根骨, 整只是 efx 上一个逐帧插槽)单独一套: 前撞 / 震退 / 后倾压扁 + 整体调暗。
帧格: 方帧 S×S(游戏 _resolve_action 只认方帧), 待机格子(200×176)摆在帧里同一位置: 水平居中、脚底行 = FEET;
  第 0 帧 = 待机第 0 帧同姿势 ⇒ 游戏用 ANIM_NORM 一行 [本体高, 脚底行, 本体高] 归一, 动作与待机同一个像素尺寸、同一条脚底线。
输出: assets/sprites/pets/animations/<龟id>/{attack,hurt,death}.png + tools/assetgen/spine_src/action_manifest.json。确定性: 重跑逐字节相同。
用法: python tools/assetgen/build_spine_actions.py [--only 龟id,…] [--preview 输出.png]
"""
import copy
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import spine_eval as S  # noqa: E402
import build_spine_idle as I  # noqa: E402

OUT_DIR = os.path.join(ROOT, "assets", "sprites", "pets", "animations")
MANIFEST = os.path.join(I.SRC, "action_manifest.json")
IDLE_MANIFEST = os.path.join(I.SRC, "idle_manifest.json")
FPS = 15
S_FRAME = 272        # 方帧边长(阵亡仰面翻倒过冲那帧, 闪电龟特效星星要 272)
FEET = 260           # 待机格子底边在方帧里的行(不含) —— 下面留 12 像素余量
RANGED = {"lightning", "phoenix", "angel", "ice", "lava"}   # turtle_stats.gd: 远程(熔岩射程 400 也按远程出手)

## ── 关键帧(逐帧值; 第 0 帧必须是 0 / 1 = 待机姿势) ──
#   平移单位 = 原画像素; 旋转 = 度(正 = 逆时针; 龟朝左, neck 正转 = 头往前往下); 缩放 = 倍数。
#   腿: arm* = 两条前腿, leg* = 两条后腿; *l = 近侧, *r = 远侧。IK 目标 = arml3/handl2 · armr3/handr2 · legl2/footl2 · legr3/footr2。
FRONT_IK = ["arml3", "handl2", "armr3", "handr2"]
HIND_IK = ["legl2", "footl2", "legr3", "footr2"]

## ★头 / 脖子转角上限 HEAD_MAX = 6°: 画师这套骨是给待机小幅摆动装的(脖子最大 3.1°、头 0.8°), 头与脖子是加权网格,
##   第一版脖子转 24° / 头 22° ⇒ 脸和脖子被拧歪、壳口的深色轮廓露出来(用户 11-05「这个头低下来很诡异啊」)。
##   ⇒ 动作主要靠**整块**的身体平移 / 压扁 / 眯眼(不拧网格); 头只在 2 倍待机幅度内点一下。门禁按 HEAD_MAX 扫关键帧。
HEAD_MAX = 6.0
## ★普攻三段(用户 11-05「盖伦…先是举起来这个剑，然后砍到一半…敌方身上出现命中特效…继续挥剑…直到收手」):
##   0 待机 → 1~3 蓄力(往后缩、抬头、前脚提起)→ 4 命中(前冲到底)→ 5 定住 → 6~9 收回。命中帧 = ATTACK_HIT。
##   游戏在**前摇一开始**就播这条, 帧率 = 命中帧 / 前摇秒数(前摇 = 攻击间隔 × 30%, 随攻速缩短)⇒ 伤害结算那一刻正好显示命中帧
##   (AttackRhythm.begin)。攻速越快整段越短(用户「你攻速越快，他这个整个前摇后摇命中都会短一点点」)。
ATTACK_HIT = 4
ATTACK_MELEE = {
	"frames": 10,
	"main.translate": [(0, 0), (2, 0), (4, 0), (6, 0), (-15, 1), (-16, 1), (-11, 0), (-6, 0), (-2, 0), (0, 0)],
	"main.scale": [(1, 1), (1.01, 0.98), (1.03, 0.96), (1.04, 0.94), (1.06, 0.98), (1.03, 1.0), (1.01, 1.0), (1, 1), (1, 1), (1, 1)],
	"neck.rotate": [0, -2, -4, -5, 6, 6, 4, 2, 1, 0],
	"head.rotate": [0, -1, -2, -3, 4, 4, 2, 1, 0, 0],
	"shell.rotate": [0, 1, 2, 2, -3, -3, -2, -1, 0, 0],
	"tail.rotate": [0, 2, 4, 6, -6, -5, -3, -1, 0, 0],
	"front.translate": [(0, 0), (0, 1), (0, 2), (0, 2), (-9, 0), (-9, 0), (-6, 0), (-3, 0), (-1, 0), (0, 0)],
	"hind.translate": [(0, 0), (0, 0), (0, 0), (0, 0), (-4, 0), (-5, 0), (-3, 0), (-1, 0), (0, 0), (0, 0)],
}
ATTACK_RANGED = {
	"frames": 10,
	"main.translate": [(0, 0), (1, 0), (2, 0), (3, 0), (-4, 1), (5, 0), (3, 0), (1, 0), (0, 0), (0, 0)],
	"main.scale": [(1, 1), (0.99, 0.98), (0.99, 0.97), (0.98, 0.95), (1.03, 1.03), (1.02, 0.98), (1.0, 1.0), (1, 1), (1, 1), (1, 1)],
	"neck.rotate": [0, -2, -4, -5, 6, 3, 0, -1, 0, 0],
	"head.rotate": [0, -1, -2, -3, -4, -2, 0, 0, 0, 0],
	"shell.rotate": [0, 1, 1, 2, -2, 2, 1, 0, 0, 0],
	"tail.rotate": [0, 2, 4, 6, -4, 4, 1, 0, 0, 0],
}
HURT = {
	"frames": 6,
	"main.translate": [(0, 0), (8, 1), (6, 0), (3, 0), (1, 0), (0, 0)],
	"main.scale": [(1, 1), (1.05, 0.9), (1.02, 0.96), (1.0, 1.0), (1, 1), (1, 1)],
	"neck.rotate": [0, -6, -4, -2, -1, 0],
	"head.rotate": [0, -4, -2, -1, 0, 0],
	"shell.rotate": [0, 4, 2, 1, 0, 0],
	"tail.rotate": [0, 6, 3, 1, 0, 0],
	"eyes": [0, 1, 1, 1, 0, 0],
}
## 阵亡 = 刚体仰面翻倒: 转 root(main 与四条腿 IK 目标的共同父骨) ⇒ 整只一起转, 不拧任何网格。
##   往尾巴那侧(+x)翻过去, 落地略过冲再回正, 四条腿朝天蹬两下停住; 眼睛全程闭着。
##   每帧往上抬多少由 flip_lift() 按第 0 帧的真实像素现算: 让最低点始终贴地(仰面时壳顶着地)。
DEATH = {
	"frames": 15,
	"root.rotate": [0, -8, -30, -70, -118, -160, -186, -177, -181, -180, -180, -180, -180, -180, -180],
	"root.drift": [0, 3, 6, 9, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12],
	"front.translate": [(0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, -4), (0, 0), (0, -4), (0, 0), (0, -2), (0, 0), (0, 0)],
	"hind.translate": [(0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, -4), (0, 0), (0, -4), (0, 0), (0, -2), (0, 0)],
	"eyes": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
}
## 龟壳: 骨只有 main / shell / efx; 唯一的插槽 guikefaguang_00000(整只壳 + 紫焰, 逐帧序列)
SHELL_ATTACK = {
	"frames": 10,
	"main.translate": [(0, 0), (2, 0), (4, 0), (6, 0), (-16, 2), (-17, 1), (-12, 0), (-6, 0), (-2, 0), (0, 0)],
	"shell.rotate": [0, 3, 6, 8, -14, -12, -7, -3, -1, 0],
	"main.scale": [(1, 1), (1.01, 0.98), (1.02, 0.96), (1.02, 0.95), (1.04, 1.0), (1.02, 1.0), (1, 1), (1, 1), (1, 1), (1, 1)],
}
SHELL_HURT = {
	"frames": 6,
	"main.translate": [(0, 0), (8, 0), (6, 0), (3, 0), (1, 0), (0, 0)],
	"shell.rotate": [0, 10, 6, 3, 1, 0],
	"main.scale": [(1, 1), (1.05, 0.9), (1.02, 0.96), (1, 1), (1, 1), (1, 1)],
}
SHELL_DEATH = {
	## 龟壳整只就是 efx 骨上的一个逐帧插槽(没有单独的「光」可熄) ⇒ 阵亡 = 一震 → 往后倾 + 压扁 + 整体调暗(读作熄火), 末帧定住
	"frames": 15,
	## 倾斜转 root + 每帧自动抬回地面(flip_lift; 龟壳没有腿, 壳底就是着地面: 往下平移或绕壳底的骨转都会压进地里, 11-05 探针低 5–6 像素)
	"root.rotate": [0, 6, 4, 8, 12, 14, 13, 14, 14, 14, 14, 14, 14, 14, 14],
	"root.drift": [0, 6, 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
	"main.scale": [(1, 1), (1.05, 0.9), (1.03, 0.94), (1.04, 0.9), (1.06, 0.86), (1.07, 0.84), (1.06, 0.86), (1.07, 0.84), (1.07, 0.84), (1.07, 0.84), (1.07, 0.84), (1.07, 0.84), (1.07, 0.84), (1.07, 0.84), (1.07, 0.84)],
	"tint": [1, 1, 0.9, 0.8, 0.7, 0.62, 0.58, 0.55, 0.55, 0.55, 0.55, 0.55, 0.55, 0.55, 0.55],
}


def _check_head_caps() -> None:
	for nm, sp in (("ATTACK_MELEE", ATTACK_MELEE), ("ATTACK_RANGED", ATTACK_RANGED), ("HURT", HURT), ("DEATH", DEATH)):
		for ch in ("neck.rotate", "head.rotate"):
			if ch in sp and max(abs(float(v)) for v in sp[ch]) > HEAD_MAX:
				raise SystemExit("%s.%s 转角超过 HEAD_MAX %.0f°(画师头部网格会被拧歪)" % (nm, ch, HEAD_MAX))


## ── 技能释放动作(方案书 20261105b §2.4 / §4.1 / §4.1b; PixelLab 额度规矩见 memory project-pixellab-budget-1105) ──
## 小幅动作(抬身 / 蹲稳 / 跺地 / 振奋 / 前倾)走骨骼模板, 不花额度; 新姿势(吐 / 甩 / 抱摔 / 冲 / 掷)走 AI(spine_src/<龟>/ai_cast/<技能类型>/)。
## 同一只龟的三个技能**不用同一个模板**(项目规矩「同一只龟的技能和普攻也不共用素材」; 构建时自检)。8 帧, 释放帧 = 动作最大那帧。
CAST_REAR = {   # 抬身: 整只往后仰(头侧抬起), 胸口挺出 —— 护盾 / 回复 / 祝福类「抬身发光」
	"frames": 8,
	"root.rotate": [0, -4, -9, -14, -16, -12, -5, 0],
	"main.scale": [(1, 1), (0.98, 1.02), (0.97, 1.05), (0.96, 1.07), (0.96, 1.07), (0.98, 1.04), (0.99, 1.01), (1, 1)],
	"neck.rotate": [0, -1, -2, -3, -3, -2, -1, 0],
	"eyes": [0, 0, 0, 0, 0, 0, 0, 0],
}
CAST_BRACE = {   # 蹲稳: 压低身子、四脚撑开、壳一抖 —— 护甲 / 减伤 / 硬抗类
	"frames": 8,
	"main.scale": [(1, 1), (1.03, 0.95), (1.07, 0.89), (1.1, 0.84), (1.1, 0.84), (1.06, 0.91), (1.02, 0.97), (1, 1)],
	"shell.rotate": [0, 2, -3, 5, -5, 3, -1, 0],
	"front.translate": [(0, 0), (-1, 0), (-2, 0), (-3, 0), (-3, 0), (-2, 0), (-1, 0), (0, 0)],
	"hind.translate": [(0, 0), (1, 0), (2, 0), (3, 0), (3, 0), (2, 0), (1, 0), (0, 0)],
}
CAST_STOMP = {   # 跺地: 前脚抬起再砸下 —— 地面 / 范围类
	"frames": 8,
	"root.rotate": [0, -3, -6, -8, 2, 0, 0, 0],
	"front.translate": [(0, 0), (0, 5), (0, 9), (0, 12), (0, 0), (0, 0), (0, 0), (0, 0)],
	"main.scale": [(1, 1), (1, 1), (0.99, 1.03), (0.98, 1.05), (1.1, 0.86), (1.04, 0.95), (1.01, 0.99), (1, 1)],
}
CAST_SHAKE = {   # 振奋: 全身一抖一鼓 —— 自身强化 / 充能类
	"frames": 8,
	"main.translate": [(0, 0), (-3, 0), (3, 0), (-3, 0), (0, 2), (0, 1), (0, 0), (0, 0)],
	"main.scale": [(1, 1), (1.03, 0.97), (0.97, 1.03), (1.04, 0.96), (1.08, 1.08), (1.04, 1.04), (1.01, 1.01), (1, 1)],
	"tail.rotate": [0, 6, -6, 6, 0, 0, 0, 0],
}
CAST_LEAN = {   # 前倾: 身子往前一探、头点向目标 —— 指令 / 遥控类(在目标处生效)
	"frames": 8,
	"main.translate": [(0, 0), (2, 0), (3, 0), (-6, 0), (-7, 0), (-4, 0), (-1, 0), (0, 0)],
	"neck.rotate": [0, -2, -3, 4, 5, 3, 1, 0],
	"head.rotate": [0, -1, -2, 3, 4, 2, 1, 0],
	"shell.rotate": [0, 1, 2, -6, -7, -4, -1, 0],
}
## 龟 → 技能类型 → 骨骼模板(其余技能走 AI, 见 CAST_AI)
CAST_SKEL = {
	"stone": {"stoneRockShield": CAST_REAR, "rockShockwave": CAST_BRACE, "stoneTaunt": CAST_STOMP},
	"bamboo": {"bambooHeal": CAST_REAR, "bambooSpikes": CAST_STOMP},
	"angel": {"angelBless": CAST_REAR},
	"ice": {"iceFrost": CAST_STOMP, "commonTeamShield": CAST_REAR},
	"fortune": {"fortuneBuyEquip": CAST_SHAKE},
	"rainbow": {"shield": CAST_REAR, "rainbowReflect": CAST_SHAKE},
	"lightning": {"lightningSurgeBuff": CAST_SHAKE, "lightningBarrage": CAST_REAR, "lightningShield": CAST_BRACE},
	"phoenix": {"phoenixShield": CAST_BRACE, "phoenixEnhancedRebirth": CAST_REAR},
	"lava": {"lavaQuake": CAST_STOMP},
	"shell": {"shellCopy": CAST_SHAKE, "shellAbsorb": CAST_LEAN, "shellShadow": CAST_BRACE},
}
## AI 段的动作描述(PixelLab animate_image, 首帧 = 待机原帧, 8 帧, 种子 1105; 原始帧落 spine_src/<龟>/ai_cast/<技能类型>/)
CAST_AI = {
	"basic": {
		"basicBarrage": "rapid energy blasts: the turtle braces, then snaps its head forward three times in quick succession spitting small blue energy waves to the left, then settles back. Side view facing left, camera does not move.",
		"basicChiWave": "charged energy beam: the turtle pulls its head back and gathers glowing blue energy at its mouth, then thrusts its head forward and fires a big energy wave straight to the left, recoils slightly, then returns to its stance. Side view facing left, camera does not move.",
		"basicSlam": "grab and throw: the turtle rears up on its hind legs, lunges forward, then heaves its whole body up and over backward in a powerful slam motion, landing back on all fours. Side view facing left, camera does not move.",
	},
	"bamboo": {"bambooSmack": "vine whip: the turtle swings its head back, then whips a long green bamboo vine forward to the left from its mouth, then yanks it back toward itself. Side view facing left, camera does not move."},
	"angel": {
		"angelEquality": "holy slashes: the turtle flaps its small wings, rears up, and slashes its head down to the left twice in quick strokes leaving bright golden light, then lands back on all fours. Side view facing left, camera does not move.",
		"angelAscend": "ascension: the turtle spreads its small wings wide and rises a little off the ground in a burst of golden light, hovers, then settles back down. Side view facing left, camera does not move.",
	},
	"ice": {"iceFreeze": "ice breath: the turtle inhales, then breathes a short burst of icy frost forward to the left from its mouth, then closes its mouth. Side view facing left, camera does not move."},
	"fortune": {
		"fortuneDice": "dice toss: the turtle flicks its head up and tosses a small white die into the air in front of it to the left, then watches it. Side view facing left, camera does not move.",
		"fortuneAllIn": "coin barrage: the turtle crouches and charges up, then rapidly spits a stream of gold coins forward to the left, then sits back. Side view facing left, camera does not move.",
	},
	"rainbow": {"rainbowStorm": "prism storm: the turtle spins in place once while rainbow-colored light swirls around its shell, then stops facing left. Side view, camera does not move."},
	"phoenix": {"phoenixScald": "fireball: the turtle rears its head back, then spits a blazing fireball forward to the left, then recoils slightly and settles. Side view facing left, camera does not move."},
	"lava": {
		"lavaSurge": "magma roar: the turtle crouches, then raises its head and roars while magma bubbles up through the cracks in its shell, then settles. Side view facing left, camera does not move.",
		"lavaErupt": "magma dash: the turtle crouches and dashes forward to the left in a burst of fiery speed, then skids to a stop. Side view facing left, camera does not move.",
	},
}


def _check_cast_variety() -> None:
	"""同一只龟的技能不共用一个骨骼模板(项目规矩); 头 / 脖子转角 ≤ HEAD_MAX。"""
	for tid, m in CAST_SKEL.items():
		ids = [id(v) for v in m.values()]
		if len(ids) != len(set(ids)):
			raise SystemExit("%s 有两个技能用了同一个骨骼模板(技能不共用素材)" % tid)
	for nm, sp in (("CAST_REAR", CAST_REAR), ("CAST_BRACE", CAST_BRACE), ("CAST_STOMP", CAST_STOMP), ("CAST_SHAKE", CAST_SHAKE), ("CAST_LEAN", CAST_LEAN)):
		for ch in ("neck.rotate", "head.rotate"):
			if ch in sp and max(abs(float(v)) for v in sp[ch]) > HEAD_MAX:
				raise SystemExit("%s.%s 转角超过 HEAD_MAX" % (nm, ch))


## ── 走路循环(骨骼; 不花额度): 对角步态 —— 近侧前腿与远侧后腿同相、另一对差半个周期;
##   着地时脚往后划(龟朝左, 往后 = +x), 抬起时往前摆、离地 WALK_LIFT; 身体随步轻微起伏。8 帧循环, 首尾相接。
WALK_STRIDE = 9.0    # 屏幕上龟约 45 像素高(缩放约 0.3), 5 像素步幅缩下来看不见(11-05 预览)
WALK_LIFT = 6.0


def _walk_leg(phase: float, n: int) -> list:
	import math
	out = []
	for k in range(n):
		t = (k / float(n) + phase) % 1.0
		if t < 0.5:
			x = -WALK_STRIDE + 2 * WALK_STRIDE * (t / 0.5)
			y = 0.0
		else:
			u_ = (t - 0.5) / 0.5
			x = WALK_STRIDE - 2 * WALK_STRIDE * u_
			y = WALK_LIFT * math.sin(math.pi * u_)
		out.append((round(x, 2), round(y, 2)))
	return out


def walk_spec() -> dict:
	import math
	n = 8
	sp = {"frames": n, "loop": True}
	for bones, ph in ((("arml3", "handl2", "legr3", "footr2"), 0.0), (("armr3", "handr2", "legl2", "footl2"), 0.5)):
		for bn in bones:
			sp[bn + ".translate"] = _walk_leg(ph, n)
	sp["main.translate"] = [(0.0, round(1.0 * abs(math.sin(2 * math.pi * k / n)), 2)) for k in range(n)]
	sp["shell.rotate"] = [round(1.0 * math.sin(2 * math.pi * k / n), 2) for k in range(n)]
	return sp


## ── 复活段 / 觉醒(被动里改变身体的那几个; 方案书 20261105b §4.1) ──
## 复活 = 阵亡末帧 + AI 8 帧(animate_image 首帧钉阵亡末帧、末帧钉待机原帧; spine_src/<龟>/ai_revive/)+ 待机原帧, 首尾与前后动作对得上。
## REVIVE_HOLD: 复活前保持趴着多少帧 —— 凤凰涅槃是 2.5 秒三拍演出(phoenix_system.NIRVANA_SHOW_SEC), 站起要落在最后「展翼」那刻;
##   天使「一帧复活」直接播。
REVIVE_SHOW_SEC = {"phoenix": 2.5}
SHELL_AWAKEN = {   # 龟壳气场觉醒(登场后两次): 一缩一鼓一抖, 末帧回原样
	"frames": 10,
	"main.scale": [(1, 1), (1.03, 0.95), (1.05, 0.92), (0.96, 1.08), (1.1, 1.1), (1.08, 1.08), (1.05, 1.05), (1.03, 1.03), (1.01, 1.01), (1, 1)],
	"main.translate": [(0, 0), (0, 0), (0, 0), (0, 0), (-2, 0), (2, 0), (-2, 0), (1, 0), (0, 0), (0, 0)],
	"shell.rotate": [0, 0, 0, 0, 3, -3, 2, -1, 0, 0],
}


def specs_for(tid: str) -> dict:
	if tid == "shell":
		return {"attack": SHELL_ATTACK, "hurt": SHELL_HURT, "death": SHELL_DEATH}
	return {"attack": ATTACK_RANGED if tid in RANGED else ATTACK_MELEE, "hurt": HURT, "death": DEATH, "run": walk_spec()}


## 待机时间轴各通道: 字段与缺省值(取 t=0 的值当动作的底)
CH_FIELDS = {
	"rotate": (["value"], [0.0]), "translate": (["x", "y"], [0.0, 0.0]), "translatex": (["value"], [0.0]), "translatey": (["value"], [0.0]),
	"scale": (["x", "y"], [1.0, 1.0]), "scalex": (["value"], [1.0]), "scaley": (["value"], [1.0]),
	"shear": (["x", "y"], [0.0, 0.0]), "shearx": (["value"], [0.0]), "sheary": (["value"], [0.0]),
}


def build_anim(sk, spec: dict) -> dict:
	"""画师待机动画拷一份, 身体骨骼的时间轴换成 spec 的逐帧关键帧 —— **相对待机第 0 帧**:
	被换的骨每个通道先取待机在 t=0 的值当底(旋转 / 平移相加, 缩放相乘), 动作没写的通道冻结在那个值。
	(11-05 门禁 verify_spine_actions 抓到: 原来直接从 setup 姿势算, 而画师待机 t=0 时头转 0.8°、前腿 IK 目标偏 0.8 像素…
	 ⇒ 动作第 0 帧与待机差 10–50% 像素, 一播就闪一下。)"""
	an = copy.deepcopy(sk.data["animations"]["animation"])
	idle_tl = sk.data["animations"]["animation"].get("bones", {})
	bones_tl = an.setdefault("bones", {})
	names = {b["name"] for b in sk.bones}
	tail = "tail" if "tail" in names else ("tail1" if "tail1" in names else None)

	def base(bone: str, kind: str) -> list:
		f, dflt = CH_FIELDS[kind]
		keys = idle_tl.get(bone, {}).get(kind)
		return S.sample(keys, 0.0, f, dflt) if keys else list(dflt)

	touched = set()
	for ch, vals in spec.items():
		if ch in ("frames", "loop") or ch in ("eyes", "tint", "root.drift"):
			continue
		who, kind = ch.split(".")
		targets = {"front": FRONT_IK, "hind": HIND_IK, "tail": [tail] if tail else []}.get(who, [who])
		for bn in targets:
			if bn not in names:
				continue
			if bn not in touched:
				## 这根骨待机里的呼吸 / 摆动换掉: 每个通道先冻结在待机 t=0 的值
				frozen = {}
				for k in idle_tl.get(bn, {}):
					if k not in CH_FIELDS:
						raise NotImplementedError("骨 %s 的待机时间轴 %s" % (bn, k))
					f, _d = CH_FIELDS[k]
					v0 = base(bn, k)
					frozen[k] = [dict({"time": 0.0}, **{ff: float(vv) for ff, vv in zip(f, v0)})]
				bones_tl[bn] = frozen
				touched.add(bn)
			if kind == "rotate":
				r0 = base(bn, "rotate")[0]
				bones_tl[bn]["rotate"] = [{"time": k / float(FPS), "value": r0 + float(v)} for k, v in enumerate(vals)]
			elif kind == "translate":
				x0, y0 = base(bn, "translate")
				bones_tl[bn]["translate"] = [{"time": k / float(FPS), "x": x0 + float(v[0]), "y": y0 + float(v[1])} for k, v in enumerate(vals)]
			elif kind == "scale":
				x0, y0 = base(bn, "scale")
				bones_tl[bn]["scale"] = [{"time": k / float(FPS), "x": x0 * float(v[0]), "y": y0 * float(v[1])} for k, v in enumerate(vals)]
	slots_tl = an.setdefault("slots", {})
	if "eyes" in spec:
		## 闭眼 = 画师的眨眼部件(winkl / winkr)常亮; 待机里那段眨眼时间轴换掉
		for s in sk.slots:
			if not s["name"].startswith("wink"):
				continue
			att = next(iter(sk.skin.get(s["name"], {}).keys()), None)
			if att is None:
				continue
			slots_tl[s["name"]] = {
				"attachment": [{"time": 0.0, "name": att}],
				"rgba": [{"time": k / float(FPS), "color": "ffffff%02x" % int(round(255 * float(v))), "curve": "stepped"} for k, v in enumerate(spec["eyes"])],
			}
	if "tint" in spec:
		## 整体调暗: 每个插槽的颜色 RGB 乘 tint(透明度不动), 逐帧阶梯
		for s in sk.slots:
			slots_tl.setdefault(s["name"], {})
			slots_tl[s["name"]].pop("rgba", None)
			slots_tl[s["name"]]["rgba"] = [{"time": k / float(FPS), "color": "%02x%02x%02xff" % ((int(round(255 * float(v))),) * 3), "curve": "stepped"}
				for k, v in enumerate(spec["tint"])]
	return an


GROUND_TOL = 3      # 阵亡塌下时最低点最多低于脚底线几像素(下巴 / 肚皮贴地, 不穿地; 身体一低前脚单骨 IK 带 compress 会让脚尖扎下 3 像素 —— 凤凰龟探针, 那是骨骼本身, 不算穿地)
def flip_lift(sk, origin: tuple, spec: dict) -> list:
	"""刚体翻倒每帧的 root 平移: x = 内容水平中心留在原处 + 往尾巴那侧漂移; y = 把这一角度下的最低点抬回地面(第 0 帧的最低点)。
	**每帧按这一帧自己的像素算**(先不转 root 渲一次): 画师的特效(闪电 / 星星)逐帧冒出来, 翻过来后原本在壳上方的特效跑到下面
	—— 11-05 只按第 0 帧算时, 闪电龟过冲那帧低于地面 12 像素。"""
	angles = spec["root.rotate"]
	drift = spec.get("root.drift", [0] * len(angles))
	flat = {k: v for k, v in spec.items() if not k.startswith("root.")}
	sk.data["animations"]["__flat"] = build_anim(sk, flat)
	out = []
	ground = cx0 = None
	for k, (th, dx) in enumerate(zip(angles, drift)):
		pm = S.render(sk, "__flat", k / float(FPS), (I.CANVAS, I.CANVAS), origin)
		ys, xs = np.where(pm[..., 3] >= 0.5)
		wx = origin[0] + xs + 0.5
		wy = origin[1] + (I.CANVAS - (ys + 0.5))
		if ground is None:
			ground = float(wy.min())
			cx0 = (float(wx.min()) + float(wx.max())) * 0.5
		r = np.radians(float(th))
		rx = np.cos(r) * wx - np.sin(r) * wy
		ry = np.sin(r) * wx + np.cos(r) * wy
		cx = (float(rx.min()) + float(rx.max())) * 0.5
		out.append((cx0 - cx + float(dx), ground - float(ry.min())))
	del sk.data["animations"]["__flat"]
	return out


def render_action(d: str, tid: str, spec: dict, idle: dict, strict: bool = True) -> list:
	nn = d.split("_")[0][len("turtle"):]
	sk = S.load(os.path.join(I.SRC, d, "turtle%s.json" % nn))
	sx, sy, sw, sh = [float(sk.sk.get(k, 0)) for k in ("x", "y", "width", "height")]
	origin = (sx + sw / 2 - I.CANVAS / 2, sy + sh / 2 - I.CANVAS / 2)
	if "root.rotate" in spec:
		spec = dict(spec)
		spec["root.translate"] = flip_lift(sk, origin, spec)
	sk.data["animations"]["__act"] = build_anim(sk, spec)
	x0, y0 = idle["crop0"]
	dx, dy = idle["place"]
	ox = (S_FRAME - idle["frameW"]) // 2
	oy = FEET - idle["frameH"]
	frames = []
	for k in range(int(spec["frames"])):
		pm = S.render(sk, "__act", k / float(FPS), (I.CANVAS, I.CANVAS), origin)
		a = pm[..., 3:4]
		rgb = np.where(a > 1e-6, pm[..., :3] / np.maximum(a, 1e-6), 0.0)
		opaque = a[..., 0] >= 0.5
		img = np.zeros((I.CANVAS, I.CANVAS, 4), dtype=np.uint8)
		img[..., :3] = (np.clip(rgb, 0, 1) * 255.0 + 0.5).astype(np.uint8)
		img[..., 3] = np.where(opaque, 255, 0).astype(np.uint8)
		img[~opaque, :3] = 0
		## 画布 (px, py) → 帧 (px - x0 + dx + ox, py - y0 + dy + oy)
		fr = np.zeros((S_FRAME, S_FRAME, 4), dtype=np.uint8)
		sx0 = x0 - dx - ox
		sy0 = y0 - dy - oy
		ys0, xs0 = max(0, sy0), max(0, sx0)
		ys1, xs1 = min(I.CANVAS, sy0 + S_FRAME), min(I.CANVAS, sx0 + S_FRAME)
		fr[ys0 - sy0: ys1 - sy0, xs0 - sx0: xs1 - sx0] = img[ys0:ys1, xs0:xs1]
		lost = int((img[..., 3] > 0).sum()) - int((fr[..., 3] > 0).sum())
		if lost > 0 and strict:
			raise SystemExit("%s 第 %d 帧有 %d 个像素出了 %d 方帧 —— 加大 S_FRAME / 调 FEET" % (tid, k, lost, S_FRAME))
		frames.append(fr)
	return frames


AI_FRAMES = 8          # PixelLab animate_image 8 帧(200×176 一格约 5 次生成)
IDLE_SHEET = os.path.join(ROOT, "assets", "sprites", "pets", "spine", "%s_idle.png")


def _palette_lock(img: np.ndarray, pal: np.ndarray) -> np.ndarray:
	"""每个不透明像素吸附到 pal(原画用过的颜色)里 RGB 最近的那个; 透明度二值。
	先对 AI 帧的**颜色种类**(约一百种)求最近色再映射回像素 —— 逐像素对整张调色板算会卡死
	(凤凰龟待机火焰渐变用了 15 万种颜色, 11-05 第一版跑了 7 分钟没出来)。"""
	out = np.zeros_like(img)
	m = img[..., 3] >= 128
	uniq, inv = np.unique(img[m][:, :3], axis=0, return_inverse=True)
	u32 = uniq.astype(np.int32)
	p32 = pal.astype(np.int32)
	best = np.zeros(len(u32), dtype=np.int64)
	bd = np.full(len(u32), 1 << 30, dtype=np.int64)
	for i0 in range(0, len(p32), 4096):
		chunk = p32[i0:i0 + 4096]
		d = ((u32[:, None, :] - chunk[None, :, :]) ** 2).sum(axis=2)
		j = d.argmin(axis=1)
		dj = d[np.arange(len(u32)), j]
		better = dj < bd
		bd[better] = dj[better]
		best[better] = j[better] + i0
	out[m, :3] = pal[best][inv.reshape(-1)]
	out[m, 3] = 255
	return out


def ai_frames(d: str, tid: str, idle: dict, sub: str, hold_to: int = 0) -> list:
	"""第 0 帧 = 待机原帧 + spine_src/<龟>/<sub>/ai_1..8.png(锁回这只龟待机 50 帧用过的颜色); hold_to > 0 时末帧定住补到这么多帧。"""
	sheet = np.asarray(Image.open(IDLE_SHEET % tid).convert("RGBA"))
	fw, fh = idle["frameW"], idle["frameH"]
	pal = np.unique(sheet[sheet[..., 3] > 0][:, :3], axis=0)
	ox = (S_FRAME - fw) // 2
	oy = FEET - fh

	def place(cell: np.ndarray) -> np.ndarray:
		fr = np.zeros((S_FRAME, S_FRAME, 4), dtype=np.uint8)
		fr[oy:oy + fh, ox:ox + fw] = cell
		return fr
	frames = [place(sheet[:fh, :fw])]
	n_ai = len([f for f in os.listdir(os.path.join(I.SRC, d, sub)) if f.startswith("ai_") and f.endswith(".png")])   # 6 或 8 帧(单动作 6 帧省额度)
	for n in range(1, n_ai + 1):
		ai = np.asarray(Image.open(os.path.join(I.SRC, d, sub, "ai_%d.png" % n)).convert("RGBA"))
		if ai.shape[:2] != (fh, fw):
			raise SystemExit("%s %s AI 第 %d 帧尺寸 %s ≠ 待机格子 %d×%d" % (tid, sub, n, ai.shape[:2], fw, fh))
		frames.append(place(_palette_lock(ai, pal)))
	while len(frames) < hold_to:
		frames.append(frames[-1].copy())
	return frames


def peak_frame(frames: list) -> int:
	"""释放帧 = 与第 0 帧不同像素最多的那一帧(动作最大的瞬间); 至少第 1 帧。"""
	f0 = frames[0]
	diffs = [int(np.any(f != f0, axis=-1).sum()) for f in frames]
	return max(1, int(np.argmax(diffs)))


def ai_death_frames(d: str, tid: str, idle: dict) -> list:
	"""阵亡 = 第 0 帧待机原帧 + PixelLab 8 帧(锁回这只龟待机 50 帧用过的颜色)+ 末帧定住到 15 帧。
	用户 11-05 看了骨骼版「这个头低下来很诡异」并问「为什么不直接…AI…生成」⇒ 同一只小龟两版对照(.out/art/ai/compare_death.png):
	AI 版「腿一软趴下、头贴地、闭眼」读得出死了, 花纹 / 金币 / 体型都保住; 骨骼弯头会拧坏脸, 刚体翻倒偏滑稽且旋转有锯齿 ⇒ 阵亡用 AI。
	AI 原始帧在 spine_src/<龟>/ai_death/(fetch_pixellab_frames.py 下的, 素材源); 颜色 95% 偏离原调色板 ⇒ 这里锁回。"""
	sheet = np.asarray(Image.open(IDLE_SHEET % tid).convert("RGBA"))
	fw, fh = idle["frameW"], idle["frameH"]
	pal = np.unique(sheet[sheet[..., 3] > 0][:, :3], axis=0)
	ox = (S_FRAME - fw) // 2
	oy = FEET - fh

	def place(cell: np.ndarray) -> np.ndarray:
		fr = np.zeros((S_FRAME, S_FRAME, 4), dtype=np.uint8)
		fr[oy:oy + fh, ox:ox + fw] = cell
		return fr
	frames = [place(sheet[:fh, :fw])]
	for n in range(1, AI_FRAMES + 1):
		ai = np.asarray(Image.open(os.path.join(I.SRC, d, "ai_death", "ai_%d.png" % n)).convert("RGBA"))
		if ai.shape[:2] != (fh, fw):
			raise SystemExit("%s AI 第 %d 帧尺寸 %s ≠ 待机格子 %d×%d" % (tid, n, ai.shape[:2], fw, fh))
		frames.append(place(_palette_lock(ai, pal)))
	while len(frames) < int(DEATH["frames"]):
		frames.append(frames[-1].copy())
	return frames


## ── 熔岩龟火山形态(方案书 20261105b §4.3b) ──
## 定稿: spine_src/turtle04_lava/volcano/keyframe.png(PixelLab Pro Flash 以待机原帧为底改图, 208×192 画布 ⇒ 游戏里同像素尺度显得大一圈);
## 各段: volcano/<段>/ai_N.png(animate_image 首帧 = 定稿; 变身段首帧 = 普通形态原帧放进同画布、末帧钉定稿)。
## 摆放: 208×192 格在方帧里 ox = (S-208)/2、底边 = FEET; 普通形态原帧在 208×192 画布的 (4,16) ⇒ 与普通形态动作帧逐像素同位。
VOLC_DIR = os.path.join(I.SRC, "turtle04_lava", "volcano")
VOLC_W, VOLC_H = 208, 192
VOLC_N0 = (4, 16)   # 普通形态原帧在火山画布里的位置(tools: .out/art/ai/lava_f0_208.png 同口径)


def build_volcano(idle_lava: dict, preview_rows: list, write: bool) -> dict:
	key = np.asarray(Image.open(os.path.join(VOLC_DIR, "keyframe.png")).convert("RGBA"))
	sheet = np.asarray(Image.open(IDLE_SHEET % "lava").convert("RGBA"))
	pal = np.unique(np.concatenate([sheet[sheet[..., 3] > 0][:, :3], key[key[..., 3] > 0][:, :3]]), axis=0)
	ox = (S_FRAME - VOLC_W) // 2
	oy = FEET - VOLC_H

	def place(cell: np.ndarray) -> np.ndarray:
		fr = np.zeros((S_FRAME, S_FRAME, 4), dtype=np.uint8)
		fr[oy:oy + VOLC_H, ox:ox + VOLC_W] = cell
		return fr

	def seg(name: str) -> list:
		d = os.path.join(VOLC_DIR, name)
		n = len([f for f in os.listdir(d) if f.startswith("ai_") and f.endswith(".png")])
		return [place(_palette_lock(np.asarray(Image.open(os.path.join(d, "ai_%d.png" % k)).convert("RGBA")), pal)) for k in range(1, n + 1)]
	k0 = place(_palette_lock(key, pal))
	n0 = np.zeros((VOLC_H, VOLC_W, 4), dtype=np.uint8)
	fw, fh = idle_lava["frameW"], idle_lava["frameH"]
	n0[VOLC_N0[1]:VOLC_N0[1] + fh, VOLC_N0[0]:VOLC_N0[0] + fw] = sheet[:fh, :fw]
	normal0 = place(n0)
	out = {}
	acts = {
		"idle": [k0] + seg("idle")[4:],   # AI 待机的前 4 帧整只发白过曝(「裂缝一明一暗」被做成白闪), 循环里一半时间在闪 ⇒ 只取后 4 帧接定稿(11-05 预览)
		"attack": [k0] + seg("attack"),
		"hurt": [k0] + seg("hurt"),
		"death": [k0] + seg("death"),
	}
	while len(acts["death"]) < int(DEATH["frames"]):
		acts["death"].append(acts["death"][-1].copy())
	casts = {}
	for st in ("lavaQuake", "lavaSurge", "lavaErupt"):
		if os.path.isdir(os.path.join(VOLC_DIR, "cast_" + st)):
			casts[st] = [k0] + seg("cast_" + st)
	tr = [normal0] + seg("transform") + [k0]   # 末帧 = 定稿(变身完正好接火山待机)
	forms = {"transform": tr, "revert": tr[::-1]}   # 变回 = 变身倒放(不另花生成次数)
	bx0, by0, bx1, by1 = _bbox(k0)
	lefts = [(_bbox(f)[0] if (f[..., 3] > 0).any() else 999) for f in acts["attack"]]
	ext = [lefts[0] - x for x in lefts]
	hit = next(i for i, e in enumerate(ext) if e >= 0.85 * max(ext)) if max(ext) > 0 else ATTACK_HIT
	ent = {"frame": S_FRAME, "fps": FPS, "body0": by1 - by0, "feet_row": by1, "hit": hit,
		"attack": len(acts["attack"]), "hurt": len(acts["hurt"]), "death": len(acts["death"]),
		"states": [["volcano", "pets/animations/lava_volcano/idle.png", 10.0]], "casts": {}}
	od = os.path.join(OUT_DIR, "lava_volcano")
	os.makedirs(od, exist_ok=True)
	for nm, frames in list(acts.items()) + [("cast_" + st, f) for st, f in casts.items()]:
		preview_rows.append(("lava_volcano", nm, frames))
		if write:
			Image.fromarray(np.concatenate(frames, axis=1), "RGBA").save(os.path.join(od, "%s.png" % nm), optimize=False)
	for st, frames in casts.items():
		ent["casts"][st] = [len(frames), peak_frame(frames), "pixellab"]
	fl = {}
	for nm, frames in forms.items():
		preview_rows.append(("lava", nm, frames))
		if write:
			Image.fromarray(np.concatenate(frames, axis=1), "RGBA").save(os.path.join(OUT_DIR, "lava", "%s.png" % nm), optimize=False)
		fl[nm] = len(frames)
	print("lava_volcano 待机 %d · 普攻 %d(命中 %d)· 受击 %d · 阵亡 %d · 技能 %s · 变身 / 变回 %d 帧" % (
		len(acts["idle"]), len(acts["attack"]), hit, len(acts["hurt"]), len(acts["death"]), sorted(casts), len(tr)))
	out["lava_volcano"] = ent
	out["lava_forms"] = fl
	return out


def _bbox(fr: np.ndarray) -> tuple:
	m = fr[..., 3] > 0
	ys = np.where(m.any(axis=1))[0]
	xs = np.where(m.any(axis=0))[0]
	return int(xs[0]), int(ys[0]), int(xs[-1]) + 1, int(ys[-1]) + 1


GD_OUT = os.path.join(ROOT, "scripts", "gamedata", "turtle_actions.gd")


def write_gd(man: dict) -> None:
	"""游戏侧动作表(生成): 三张帧表 + 归一表, 与主场景 ACTION_* / ANIM_NORM 同口径。LF 行尾、键排序 ⇒ 重跑逐字节相同。"""
	ids = sorted(man)
	L = ["class_name TurtleActions",
		"extends RefCounted",
		"## 外包 11 只龟的动作帧表(普攻 / 受击 / 阵亡 / 技能释放) —— 由 tools/assetgen/build_spine_actions.py 生成, **别手改**(改关键帧后重跑脚本)。",
		"## 方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.3: 在画师 Spine 原骨骼上写关键帧, 求值器(已与官方运行库逐帧对账)渲成像素序列帧。",
		"## 帧表值 = [相对 assets/sprites/ 的路径, 每秒帧率], 与主场景 ACTION_ATTACK 同口径; 主场景表里没有的龟才查这里(battle_vfx._play_action)。",
		"## 方帧 %d×%d(_resolve_action 只认方帧); 第 0 帧 = 待机第 0 帧同姿势、同一像素尺寸。" % (S_FRAME, S_FRAME),
		"",
	]
	for const, act in (("ATTACK", "attack"), ("HURT", "hurt"), ("DEATH", "death")):
		L.append("const %s := {" % const)
		for t in ids:
			L.append("\t\"%s\": [\"pets/animations/%s/%s.png\", %.1f],   # %d 帧" % (t, t, act, float(FPS), int(man[t][act])))
		L.append("}")
	L.append("## 走路循环(骨骼对角步态; battle_render._update_run_anim 读; 龟壳没有腿不做)")
	L.append("const RUN := {")
	for t in ids:
		if "run" in man[t]:
			L.append("	\"%s\": [\"pets/animations/%s/run.png\", 12.0],   # %d 帧" % (t, t, int(man[t]["run"])))
	L.append("}")
	L.append("## 普攻命中帧(按路径; AttackHits.hit_frame 读): 前摇 1~%d 帧 → 第 %d 帧命中 → 后摇。" % (ATTACK_HIT - 1, ATTACK_HIT))
	L.append("const HIT := {")
	for t in ids:
		L.append("\t\"pets/animations/%s/attack.png\": %d," % (t, int(man[t].get("hit", ATTACK_HIT))))
	L.append("}")
	L.append("## 技能释放动作 [路径, 帧率, 释放帧](AttackRhythm.cast_begin 读: 技能前摇开始就播, 释放帧对上 _cast_skill 生效)。来源: 骨骼模板 / PixelLab。")
	L.append("## 持续状态循环 [[状态名, 路径, 帧率], ...](AttackRhythm.apply_state_idle 读; 熔岩火山形态等)")
	L.append("const STATE := {")
	for t in ids:
		stt = man[t].get("states", [])
		if stt:
			L.append("	\"%s\": [%s]," % (t, ", ".join("[\"%s\", \"%s\", %.1f]" % (a, b_, float(c)) for a, b_, c in stt)))
	L.append("}")
	L.append("## 形态切换段 [路径, 帧率](AttackRhythm.play_form 读; 熔岩变身 / 变回, 变回 = 变身倒放)")
	L.append("const FORM := {")
	for t in ids:
		fm = man[t].get("forms", {})
		if fm:
			L.append("\t\"%s\": {%s}," % (t, ", ".join("\"%s\": [\"pets/animations/%s/%s.png\", %.1f]" % (nm, t, nm, float(FPS)) for nm in sorted(fm))))
	L.append("}")
	L.append("const CAST := {")
	for t in ids:
		cs = man[t].get("casts", {})
		if not cs:
			continue
		L.append("\t\"%s\": {" % t)
		for st in sorted(cs):
			n, rel, src = cs[st]
			L.append("\t\t\"%s\": [\"pets/animations/%s/cast_%s.png\", %.1f, %d],   # %d 帧 · %s" % (st, t, st, float(FPS), int(rel), int(n), src))
		L.append("\t},")
	L.append("}")
	L.append("## 归一 [动作图本体高, 脚底行, 待机本体高] —— 与主场景 ANIM_NORM 同口径(elite_system._elite_fix_norm 读)。")
	L.append("##   两个本体高相等(动作与待机同一个像素尺寸); 脚底行 = 待机格子底边在方帧里的行(动作一播不上下跳)。")
	L.append("const NORM := {")
	for t in ids:
		L.append("\t\"%s\": [%.1f, %.1f, %.1f]," % (t, float(man[t]["body0"]), float(FEET), float(man[t]["body0"])))
	L.append("}")
	L.append("")
	L.append("")
	L.append("static func by_kind(kind: String) -> Dictionary:")
	L.append("\tmatch kind:")
	L.append("\t\t\"attack\": return ATTACK")
	L.append("\t\t\"hurt\": return HURT")
	L.append("\t\t\"death\": return DEATH")
	L.append("\treturn {}")
	open(GD_OUT, "wb").write(("\n".join(L) + "\n").encode("utf-8"))
	print("写出", os.path.relpath(GD_OUT, ROOT))


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	only = None
	if "--only" in sys.argv:
		only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
	preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
	if "--gd-only" in sys.argv:   # 只重写 TurtleActions(外包 11 只清单 + 从头做的龟清单), 不重渲(新做一只龟后用)
		pm = os.path.join(HERE, "pet_src", "pet_manifest.json")
		write_gd(dict(json.load(open(MANIFEST, encoding="utf-8")), **json.load(open(pm, encoding="utf-8"))))
		return 0
	_check_head_caps()
	_check_cast_variety()
	idle_man = json.load(open(IDLE_MANIFEST, encoding="utf-8"))
	man = json.load(open(MANIFEST, encoding="utf-8")) if os.path.exists(MANIFEST) else {}
	rows = []
	for d in I._dirs():
		tid = d.split("_", 1)[1]
		if only and tid not in only:
			continue
		idle = idle_man[tid]
		ent = {"frame": S_FRAME, "fps": FPS, "idle_body": int(idle["content"][1])}
		for act, spec in specs_for(tid).items():
			if act == "death" and os.path.isdir(os.path.join(I.SRC, d, "ai_death")):
				frames = ai_death_frames(d, tid, idle)
				ent["death_src"] = "pixellab"
				death_frames = frames
			else:
				frames = render_action(d, tid, spec, idle)
			if act == "death":
				death_frames = frames
			if act == "death" and max(_bbox(f)[3] for f in frames) > FEET + GROUND_TOL:
				raise SystemExit("%s 阵亡穿地: 最低点 %d > 脚底线 %d + %d" % (tid, max(_bbox(f)[3] for f in frames), FEET, GROUND_TOL))
			bx0, by0, bx1, by1 = _bbox(frames[0])
			ent["feet_row"] = by1
			ent["body0"] = by1 - by0
			ent[act] = len(frames)
			rows.append((tid, act, frames))
			if preview is None:
				sheet = np.concatenate(frames, axis=1)
				od = os.path.join(OUT_DIR, tid)
				os.makedirs(od, exist_ok=True)
				Image.fromarray(sheet, "RGBA").save(os.path.join(od, "%s.png" % act), optimize=False)
			print("%-10s %-7s %2d 帧 · 第0帧本体高 %d 脚底行 %d(待机本体高 %d)" % (tid, act, len(frames), by1 - by0, by1, idle["content"][1]))
		forms = {}
		if os.path.isdir(os.path.join(I.SRC, d, "ai_revive")):
			ai = ai_frames(d, tid, idle, "ai_revive")
			rise = [death_frames[-1]] + ai[1:] + [ai[0]]
			hold = max(0, int(round(REVIVE_SHOW_SEC.get(tid, 0.0) * FPS)) - len(rise))
			forms["revive"] = [death_frames[-1].copy() for _ in range(hold)] + rise
		if tid == "shell":
			forms["awaken"] = render_action(d, tid, SHELL_AWAKEN, idle)
		if forms:
			ent["forms"] = {}
			for nm, frames in forms.items():
				ent["forms"][nm] = len(frames)
				rows.append((tid, nm, frames))
				if preview is None:
					Image.fromarray(np.concatenate(frames, axis=1), "RGBA").save(os.path.join(OUT_DIR, tid, "%s.png" % nm), optimize=False)
				print("%-10s %-7s %2d 帧(形态 / 被动段)" % (tid, nm, len(frames)))
		casts = {}
		for stype, spec in CAST_SKEL.get(tid, {}).items():
			casts[stype] = ("skel", render_action(d, tid, spec, idle))
		cdir = os.path.join(I.SRC, d, "ai_cast")
		if os.path.isdir(cdir):
			for stype in sorted(os.listdir(cdir)):
				casts[stype] = ("pixellab", ai_frames(d, tid, idle, os.path.join("ai_cast", stype)))
		ent["casts"] = {}
		for stype, (src, frames) in sorted(casts.items()):
			rel = peak_frame(frames)
			ent["casts"][stype] = [len(frames), rel, src]
			rows.append((tid, "cast_" + stype, frames))
			if preview is None:
				od = os.path.join(OUT_DIR, tid)
				os.makedirs(od, exist_ok=True)
				Image.fromarray(np.concatenate(frames, axis=1), "RGBA").save(os.path.join(od, "cast_%s.png" % stype), optimize=False)
			print("%-10s cast_%-22s %2d 帧 · 释放帧 %d · %s" % (tid, stype, len(frames), rel, src))
		man[tid] = ent
	if (only is None or "lava" in only) and os.path.exists(os.path.join(VOLC_DIR, "keyframe.png")):
		vo = build_volcano(idle_man["lava"], rows, preview is None)
		man["lava_volcano"] = vo["lava_volcano"]
		if "lava" in man:
			man["lava"]["forms"] = vo["lava_forms"]
	if preview:
		cell = S_FRAME // 2
		maxn = max(len(f) for _, _, f in rows)
		sheet = Image.new("RGBA", (cell * maxn, cell * len(rows)), (60, 60, 70, 255))
		for r, (tid, act, frames) in enumerate(rows):
			for c, fr in enumerate(frames):
				im = Image.fromarray(fr, "RGBA").resize((cell, cell), Image.NEAREST)
				sheet.alpha_composite(im, (c * cell, r * cell))
		sheet.save(preview)
		print("预览 →", preview)
	else:
		json.dump(man, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
		if only is None:
			## 外包 11 只以外、从头做的龟(build_pet_actions.py 的清单)并进同一张生成表 —— 查表 / 门禁对它们一律生效
			pm = os.path.join(HERE, "pet_src", "pet_manifest.json")
			write_gd(dict(man, **(json.load(open(pm, encoding="utf-8")) if os.path.exists(pm) else {})))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
