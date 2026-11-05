class_name TurtleActions
extends RefCounted
## 外包 11 只龟的动作帧表(普攻 / 受击 / 阵亡 / 技能释放) —— 由 tools/assetgen/build_spine_actions.py 生成, **别手改**(改关键帧后重跑脚本)。
## 方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.3: 在画师 Spine 原骨骼上写关键帧, 求值器(已与官方运行库逐帧对账)渲成像素序列帧。
## 帧表值 = [相对 assets/sprites/ 的路径, 每秒帧率], 与主场景 ACTION_ATTACK 同口径; 主场景表里没有的龟才查这里(battle_vfx._play_action)。
## 方帧 272×272(_resolve_action 只认方帧); 第 0 帧 = 待机第 0 帧同姿势、同一像素尺寸。

const ATTACK := {
	"angel": ["pets/animations/angel/attack.png", 15.0],   # 10 帧
	"bamboo": ["pets/animations/bamboo/attack.png", 15.0],   # 10 帧
	"basic": ["pets/animations/basic/attack.png", 15.0],   # 10 帧
	"bubble": ["pets/animations/bubble/attack.png", 15.0],   # 9 帧
	"candy": ["pets/animations/candy/attack.png", 15.0],   # 9 帧
	"chest": ["pets/animations/chest/attack.png", 15.0],   # 9 帧
	"crystal": ["pets/animations/crystal/attack.png", 15.0],   # 9 帧
	"cyber": ["pets/animations/cyber/attack.png", 15.0],   # 9 帧
	"diamond": ["pets/animations/diamond/attack.png", 15.0],   # 9 帧
	"dice": ["pets/animations/dice/attack.png", 15.0],   # 9 帧
	"fortune": ["pets/animations/fortune/attack.png", 15.0],   # 10 帧
	"gambler": ["pets/animations/gambler/attack.png", 15.0],   # 9 帧
	"headless": ["pets/animations/headless/attack.png", 15.0],   # 9 帧
	"hiding": ["pets/animations/hiding/attack.png", 15.0],   # 9 帧
	"hunter": ["pets/animations/hunter/attack.png", 15.0],   # 9 帧
	"ice": ["pets/animations/ice/attack.png", 15.0],   # 10 帧
	"lava": ["pets/animations/lava/attack.png", 15.0],   # 10 帧
	"lava_volcano": ["pets/animations/lava_volcano/attack.png", 15.0],   # 9 帧
	"lightning": ["pets/animations/lightning/attack.png", 15.0],   # 10 帧
	"line": ["pets/animations/line/attack.png", 15.0],   # 9 帧
	"phoenix": ["pets/animations/phoenix/attack.png", 15.0],   # 10 帧
	"pirate": ["pets/animations/pirate/attack.png", 15.0],   # 9 帧
	"rainbow": ["pets/animations/rainbow/attack.png", 15.0],   # 10 帧
	"shell": ["pets/animations/shell/attack.png", 15.0],   # 10 帧
	"space": ["pets/animations/space/attack.png", 15.0],   # 9 帧
	"stone": ["pets/animations/stone/attack.png", 15.0],   # 10 帧
}
const HURT := {
	"angel": ["pets/animations/angel/hurt.png", 15.0],   # 6 帧
	"bamboo": ["pets/animations/bamboo/hurt.png", 15.0],   # 6 帧
	"basic": ["pets/animations/basic/hurt.png", 15.0],   # 6 帧
	"bubble": ["pets/animations/bubble/hurt.png", 15.0],   # 5 帧
	"candy": ["pets/animations/candy/hurt.png", 15.0],   # 5 帧
	"chest": ["pets/animations/chest/hurt.png", 15.0],   # 5 帧
	"crystal": ["pets/animations/crystal/hurt.png", 15.0],   # 5 帧
	"cyber": ["pets/animations/cyber/hurt.png", 15.0],   # 5 帧
	"diamond": ["pets/animations/diamond/hurt.png", 15.0],   # 5 帧
	"dice": ["pets/animations/dice/hurt.png", 15.0],   # 5 帧
	"fortune": ["pets/animations/fortune/hurt.png", 15.0],   # 6 帧
	"gambler": ["pets/animations/gambler/hurt.png", 15.0],   # 5 帧
	"headless": ["pets/animations/headless/hurt.png", 15.0],   # 5 帧
	"hiding": ["pets/animations/hiding/hurt.png", 15.0],   # 5 帧
	"hunter": ["pets/animations/hunter/hurt.png", 15.0],   # 5 帧
	"ice": ["pets/animations/ice/hurt.png", 15.0],   # 6 帧
	"lava": ["pets/animations/lava/hurt.png", 15.0],   # 6 帧
	"lava_volcano": ["pets/animations/lava_volcano/hurt.png", 15.0],   # 5 帧
	"lightning": ["pets/animations/lightning/hurt.png", 15.0],   # 6 帧
	"line": ["pets/animations/line/hurt.png", 15.0],   # 5 帧
	"phoenix": ["pets/animations/phoenix/hurt.png", 15.0],   # 6 帧
	"pirate": ["pets/animations/pirate/hurt.png", 15.0],   # 5 帧
	"rainbow": ["pets/animations/rainbow/hurt.png", 15.0],   # 6 帧
	"shell": ["pets/animations/shell/hurt.png", 15.0],   # 6 帧
	"space": ["pets/animations/space/hurt.png", 15.0],   # 5 帧
	"stone": ["pets/animations/stone/hurt.png", 15.0],   # 6 帧
}
const DEATH := {
	"angel": ["pets/animations/angel/death.png", 15.0],   # 15 帧
	"bamboo": ["pets/animations/bamboo/death.png", 15.0],   # 15 帧
	"basic": ["pets/animations/basic/death.png", 15.0],   # 15 帧
	"bubble": ["pets/animations/bubble/death.png", 15.0],   # 15 帧
	"candy": ["pets/animations/candy/death.png", 15.0],   # 15 帧
	"chest": ["pets/animations/chest/death.png", 15.0],   # 15 帧
	"crystal": ["pets/animations/crystal/death.png", 15.0],   # 15 帧
	"cyber": ["pets/animations/cyber/death.png", 15.0],   # 15 帧
	"diamond": ["pets/animations/diamond/death.png", 15.0],   # 15 帧
	"dice": ["pets/animations/dice/death.png", 15.0],   # 15 帧
	"fortune": ["pets/animations/fortune/death.png", 15.0],   # 15 帧
	"gambler": ["pets/animations/gambler/death.png", 15.0],   # 15 帧
	"headless": ["pets/animations/headless/death.png", 15.0],   # 15 帧
	"hiding": ["pets/animations/hiding/death.png", 15.0],   # 15 帧
	"hunter": ["pets/animations/hunter/death.png", 15.0],   # 15 帧
	"ice": ["pets/animations/ice/death.png", 15.0],   # 15 帧
	"lava": ["pets/animations/lava/death.png", 15.0],   # 15 帧
	"lava_volcano": ["pets/animations/lava_volcano/death.png", 15.0],   # 15 帧
	"lightning": ["pets/animations/lightning/death.png", 15.0],   # 15 帧
	"line": ["pets/animations/line/death.png", 15.0],   # 15 帧
	"phoenix": ["pets/animations/phoenix/death.png", 15.0],   # 15 帧
	"pirate": ["pets/animations/pirate/death.png", 15.0],   # 15 帧
	"rainbow": ["pets/animations/rainbow/death.png", 15.0],   # 15 帧
	"shell": ["pets/animations/shell/death.png", 15.0],   # 15 帧
	"space": ["pets/animations/space/death.png", 15.0],   # 15 帧
	"stone": ["pets/animations/stone/death.png", 15.0],   # 15 帧
}
## 走路循环(骨骼对角步态; battle_render._update_run_anim 读; 龟壳没有腿不做)
const RUN := {
	"angel": ["pets/animations/angel/run.png", 12.0],   # 8 帧
	"bamboo": ["pets/animations/bamboo/run.png", 12.0],   # 8 帧
	"basic": ["pets/animations/basic/run.png", 12.0],   # 8 帧
	"bubble": ["pets/animations/bubble/run.png", 12.0],   # 7 帧
	"candy": ["pets/animations/candy/run.png", 12.0],   # 9 帧
	"chest": ["pets/animations/chest/run.png", 12.0],   # 7 帧
	"crystal": ["pets/animations/crystal/run.png", 12.0],   # 7 帧
	"cyber": ["pets/animations/cyber/run.png", 12.0],   # 7 帧
	"diamond": ["pets/animations/diamond/run.png", 12.0],   # 7 帧
	"dice": ["pets/animations/dice/run.png", 12.0],   # 7 帧
	"fortune": ["pets/animations/fortune/run.png", 12.0],   # 8 帧
	"gambler": ["pets/animations/gambler/run.png", 12.0],   # 7 帧
	"headless": ["pets/animations/headless/run.png", 12.0],   # 7 帧
	"hiding": ["pets/animations/hiding/run.png", 12.0],   # 7 帧
	"hunter": ["pets/animations/hunter/run.png", 12.0],   # 7 帧
	"ice": ["pets/animations/ice/run.png", 12.0],   # 8 帧
	"lava": ["pets/animations/lava/run.png", 12.0],   # 8 帧
	"lightning": ["pets/animations/lightning/run.png", 12.0],   # 8 帧
	"line": ["pets/animations/line/run.png", 12.0],   # 7 帧
	"phoenix": ["pets/animations/phoenix/run.png", 12.0],   # 8 帧
	"pirate": ["pets/animations/pirate/run.png", 12.0],   # 7 帧
	"rainbow": ["pets/animations/rainbow/run.png", 12.0],   # 8 帧
	"space": ["pets/animations/space/run.png", 12.0],   # 7 帧
	"stone": ["pets/animations/stone/run.png", 12.0],   # 8 帧
}
## 普攻命中帧(按路径; AttackHits.hit_frame 读): 前摇 1~3 帧 → 第 4 帧命中 → 后摇。
const HIT := {
	"pets/animations/angel/attack.png": 4,
	"pets/animations/bamboo/attack.png": 4,
	"pets/animations/basic/attack.png": 4,
	"pets/animations/bubble/attack.png": 4,
	"pets/animations/candy/attack.png": 4,
	"pets/animations/chest/attack.png": 4,
	"pets/animations/crystal/attack.png": 4,
	"pets/animations/cyber/attack.png": 4,
	"pets/animations/diamond/attack.png": 4,
	"pets/animations/dice/attack.png": 4,
	"pets/animations/fortune/attack.png": 4,
	"pets/animations/gambler/attack.png": 4,
	"pets/animations/headless/attack.png": 4,
	"pets/animations/hiding/attack.png": 4,
	"pets/animations/hunter/attack.png": 4,
	"pets/animations/ice/attack.png": 4,
	"pets/animations/lava/attack.png": 4,
	"pets/animations/lava_volcano/attack.png": 5,
	"pets/animations/lightning/attack.png": 4,
	"pets/animations/line/attack.png": 4,
	"pets/animations/phoenix/attack.png": 4,
	"pets/animations/pirate/attack.png": 4,
	"pets/animations/rainbow/attack.png": 4,
	"pets/animations/shell/attack.png": 4,
	"pets/animations/space/attack.png": 4,
	"pets/animations/stone/attack.png": 4,
}
## 技能释放动作 [路径, 帧率, 释放帧](AttackRhythm.cast_begin 读: 技能前摇开始就播, 释放帧对上 _cast_skill 生效)。来源: 骨骼模板 / PixelLab。
## 持续状态循环 [[状态名, 路径, 帧率], ...](AttackRhythm.apply_state_idle 读; 熔岩火山形态等)
const STATE := {
	"diamond": [["diamondRoll", "pets/animations/diamond/state_diamondRoll.png", 15.0]],
	"hiding": [["hidingShrink", "pets/animations/hiding/state_hidingShrink.png", 6.0]],
	"lava_volcano": [["volcano", "pets/animations/lava_volcano/idle.png", 10.0]],
}
## 形态切换段 [路径, 帧率](AttackRhythm.play_form 读; 熔岩变身 / 变回, 变回 = 变身倒放)
const FORM := {
	"angel": {"revive": ["pets/animations/angel/revive.png", 15.0]},
	"lava": {"revert": ["pets/animations/lava/revert.png", 15.0], "transform": ["pets/animations/lava/transform.png", 15.0]},
	"phoenix": {"revive": ["pets/animations/phoenix/revive.png", 15.0]},
	"shell": {"awaken": ["pets/animations/shell/awaken.png", 15.0]},
}
const CAST := {
	"angel": {
		"angelAscend": ["pets/animations/angel/cast_angelAscend.png", 15.0, 3],   # 7 帧 · pixellab
		"angelBless": ["pets/animations/angel/cast_angelBless.png", 15.0, 4],   # 8 帧 · skel
		"angelEquality": ["pets/animations/angel/cast_angelEquality.png", 15.0, 6],   # 9 帧 · pixellab
	},
	"bamboo": {
		"bambooHeal": ["pets/animations/bamboo/cast_bambooHeal.png", 15.0, 4],   # 8 帧 · skel
		"bambooSmack": ["pets/animations/bamboo/cast_bambooSmack.png", 15.0, 4],   # 7 帧 · pixellab
		"bambooSpikes": ["pets/animations/bamboo/cast_bambooSpikes.png", 15.0, 3],   # 8 帧 · skel
	},
	"basic": {
		"basicBarrage": ["pets/animations/basic/cast_basicBarrage.png", 15.0, 4],   # 9 帧 · pixellab
		"basicChiWave": ["pets/animations/basic/cast_basicChiWave.png", 15.0, 3],   # 9 帧 · pixellab
		"basicSlam": ["pets/animations/basic/cast_basicSlam.png", 15.0, 4],   # 9 帧 · pixellab
	},
	"bubble": {
		"bubbleBind": ["pets/animations/bubble/cast_bubbleBind.png", 15.0, 2],   # 7 帧 · pixellab
		"bubbleBurst": ["pets/animations/bubble/cast_bubbleBurst.png", 15.0, 4],   # 7 帧 · pixellab
		"bubbleShield": ["pets/animations/bubble/cast_bubbleShield.png", 15.0, 5],   # 7 帧 · pixellab
	},
	"candy": {
		"candyBarrage": ["pets/animations/candy/cast_candyBarrage.png", 15.0, 3],   # 7 帧 · pixellab
		"candyBomb": ["pets/animations/candy/cast_candyBomb.png", 15.0, 4],   # 7 帧 · pixellab
		"candyHammer": ["pets/animations/candy/cast_candyHammer.png", 15.0, 6],   # 9 帧 · pixellab
	},
	"chest": {
		"chestCannon": ["pets/animations/chest/cast_chestCannon.png", 15.0, 6],   # 9 帧 · pixellab
		"chestCount": ["pets/animations/chest/cast_chestCount.png", 15.0, 2],   # 7 帧 · pixellab
		"chestStorm": ["pets/animations/chest/cast_chestStorm.png", 15.0, 3],   # 7 帧 · pixellab
	},
	"crystal": {
		"crystalBall": ["pets/animations/crystal/cast_crystalBall.png", 15.0, 2],   # 7 帧 · pixellab
		"crystalBarrier": ["pets/animations/crystal/cast_crystalBarrier.png", 15.0, 5],   # 7 帧 · pixellab
		"crystalBurst": ["pets/animations/crystal/cast_crystalBurst.png", 15.0, 2],   # 7 帧 · pixellab
	},
	"cyber": {
		"cyberBeam": ["pets/animations/cyber/cast_cyberBeam.png", 15.0, 5],   # 9 帧 · pixellab
		"cyberHijack": ["pets/animations/cyber/cast_cyberHijack.png", 15.0, 2],   # 7 帧 · pixellab
		"cyberSmartAI": ["pets/animations/cyber/cast_cyberSmartAI.png", 15.0, 4],   # 7 帧 · pixellab
	},
	"diamond": {
		"diamondFortify": ["pets/animations/diamond/cast_diamondFortify.png", 15.0, 4],   # 7 帧 · pixellab
		"diamondPowerball": ["pets/animations/diamond/cast_diamondPowerball.png", 15.0, 7],   # 8 帧 · pixellab
		"diamondSmash": ["pets/animations/diamond/cast_diamondSmash.png", 15.0, 4],   # 7 帧 · pixellab
	},
	"dice": {
		"diceAllIn": ["pets/animations/dice/cast_diceAllIn.png", 15.0, 4],   # 7 帧 · pixellab
		"diceFate": ["pets/animations/dice/cast_diceFate.png", 15.0, 4],   # 8 帧 · pixellab
		"diceFlashStrike": ["pets/animations/dice/cast_diceFlashStrike.png", 15.0, 2],   # 6 帧 · pixellab
	},
	"fortune": {
		"fortuneAllIn": ["pets/animations/fortune/cast_fortuneAllIn.png", 15.0, 4],   # 9 帧 · pixellab
		"fortuneBuyEquip": ["pets/animations/fortune/cast_fortuneBuyEquip.png", 15.0, 4],   # 8 帧 · skel
		"fortuneDice": ["pets/animations/fortune/cast_fortuneDice.png", 15.0, 3],   # 7 帧 · pixellab
	},
	"gambler": {
		"gamblerBet": ["pets/animations/gambler/cast_gamblerBet.png", 15.0, 4],   # 7 帧 · pixellab
		"gamblerDraw": ["pets/animations/gambler/cast_gamblerDraw.png", 15.0, 6],   # 7 帧 · pixellab
		"gamblerFateWheel": ["pets/animations/gambler/cast_gamblerFateWheel.png", 15.0, 5],   # 7 帧 · pixellab
	},
	"headless": {
		"headlessFear": ["pets/animations/headless/cast_headlessFear.png", 15.0, 4],   # 10 帧 · pixellab
		"headlessSoulStrike": ["pets/animations/headless/cast_headlessSoulStrike.png", 15.0, 4],   # 7 帧 · pixellab
		"headlessTendrils": ["pets/animations/headless/cast_headlessTendrils.png", 15.0, 4],   # 7 帧 · pixellab
	},
	"hiding": {
		"hidingBuffSummon": ["pets/animations/hiding/cast_hidingBuffSummon.png", 15.0, 3],   # 7 帧 · pixellab
		"hidingDefend": ["pets/animations/hiding/cast_hidingDefend.png", 15.0, 2],   # 7 帧 · pixellab
		"hidingShrink": ["pets/animations/hiding/cast_hidingShrink.png", 15.0, 2],   # 7 帧 · pixellab
	},
	"hunter": {
		"hunterBarrage": ["pets/animations/hunter/cast_hunterBarrage.png", 15.0, 2],   # 7 帧 · pixellab
		"hunterShot": ["pets/animations/hunter/cast_hunterShot.png", 15.0, 6],   # 9 帧 · pixellab
		"hunterStealth": ["pets/animations/hunter/cast_hunterStealth.png", 15.0, 4],   # 7 帧 · pixellab
	},
	"ice": {
		"commonTeamShield": ["pets/animations/ice/cast_commonTeamShield.png", 15.0, 4],   # 8 帧 · skel
		"iceFreeze": ["pets/animations/ice/cast_iceFreeze.png", 15.0, 2],   # 7 帧 · pixellab
		"iceFrost": ["pets/animations/ice/cast_iceFrost.png", 15.0, 3],   # 8 帧 · skel
	},
	"lava": {
		"lavaErupt": ["pets/animations/lava/cast_lavaErupt.png", 15.0, 3],   # 7 帧 · pixellab
		"lavaQuake": ["pets/animations/lava/cast_lavaQuake.png", 15.0, 3],   # 8 帧 · skel
		"lavaSurge": ["pets/animations/lava/cast_lavaSurge.png", 15.0, 3],   # 7 帧 · pixellab
	},
	"lava_volcano": {
		"lavaErupt": ["pets/animations/lava_volcano/cast_lavaErupt.png", 15.0, 6],   # 7 帧 · pixellab
		"lavaQuake": ["pets/animations/lava_volcano/cast_lavaQuake.png", 15.0, 3],   # 7 帧 · pixellab
		"lavaSurge": ["pets/animations/lava_volcano/cast_lavaSurge.png", 15.0, 3],   # 7 帧 · pixellab
	},
	"lightning": {
		"lightningBarrage": ["pets/animations/lightning/cast_lightningBarrage.png", 15.0, 4],   # 8 帧 · skel
		"lightningShield": ["pets/animations/lightning/cast_lightningShield.png", 15.0, 4],   # 8 帧 · skel
		"lightningSurgeBuff": ["pets/animations/lightning/cast_lightningSurgeBuff.png", 15.0, 4],   # 8 帧 · skel
	},
	"line": {
		"lineFinish": ["pets/animations/line/cast_lineFinish.png", 15.0, 4],   # 7 帧 · pixellab
		"lineInkBomb": ["pets/animations/line/cast_lineInkBomb.png", 15.0, 6],   # 7 帧 · pixellab
		"lineLink": ["pets/animations/line/cast_lineLink.png", 15.0, 4],   # 7 帧 · pixellab
	},
	"phoenix": {
		"phoenixEnhancedRebirth": ["pets/animations/phoenix/cast_phoenixEnhancedRebirth.png", 15.0, 4],   # 8 帧 · skel
		"phoenixScald": ["pets/animations/phoenix/cast_phoenixScald.png", 15.0, 3],   # 7 帧 · pixellab
		"phoenixShield": ["pets/animations/phoenix/cast_phoenixShield.png", 15.0, 4],   # 8 帧 · skel
	},
	"pirate": {
		"pirateCannonBarrage": ["pets/animations/pirate/cast_pirateCannonBarrage.png", 15.0, 4],   # 7 帧 · pixellab
		"pirateRum": ["pets/animations/pirate/cast_pirateRum.png", 15.0, 4],   # 7 帧 · pixellab
		"pirateShipPassive": ["pets/animations/pirate/cast_pirateShipPassive.png", 15.0, 4],   # 7 帧 · pixellab
	},
	"rainbow": {
		"rainbowReflect": ["pets/animations/rainbow/cast_rainbowReflect.png", 15.0, 4],   # 8 帧 · skel
		"rainbowStorm": ["pets/animations/rainbow/cast_rainbowStorm.png", 15.0, 3],   # 9 帧 · pixellab
		"shield": ["pets/animations/rainbow/cast_shield.png", 15.0, 4],   # 8 帧 · skel
	},
	"shell": {
		"shellAbsorb": ["pets/animations/shell/cast_shellAbsorb.png", 15.0, 3],   # 8 帧 · skel
		"shellCopy": ["pets/animations/shell/cast_shellCopy.png", 15.0, 4],   # 8 帧 · skel
		"shellShadow": ["pets/animations/shell/cast_shellShadow.png", 15.0, 4],   # 8 帧 · skel
	},
	"space": {
		"starGravityWarp": ["pets/animations/space/cast_starGravityWarp.png", 15.0, 4],   # 7 帧 · pixellab
		"starWave": ["pets/animations/space/cast_starWave.png", 15.0, 5],   # 7 帧 · pixellab
		"starWormhole": ["pets/animations/space/cast_starWormhole.png", 15.0, 5],   # 9 帧 · pixellab
	},
	"stone": {
		"rockShockwave": ["pets/animations/stone/cast_rockShockwave.png", 15.0, 4],   # 8 帧 · skel
		"stoneRockShield": ["pets/animations/stone/cast_stoneRockShield.png", 15.0, 4],   # 8 帧 · skel
		"stoneTaunt": ["pets/animations/stone/cast_stoneTaunt.png", 15.0, 4],   # 8 帧 · skel
	},
}
## 归一 [动作图本体高, 脚底行, 待机本体高] —— 与主场景 ANIM_NORM 同口径(elite_system._elite_fix_norm 读)。
##   两个本体高相等(动作与待机同一个像素尺寸); 脚底行 = 待机格子底边在方帧里的行(动作一播不上下跳)。
const NORM := {
	"angel": [160.0, 260.0, 160.0],
	"bamboo": [165.0, 260.0, 165.0],
	"basic": [139.0, 260.0, 139.0],
	"bubble": [164.0, 260.0, 164.0],
	"candy": [164.0, 260.0, 164.0],
	"chest": [135.0, 260.0, 135.0],
	"crystal": [164.0, 260.0, 164.0],
	"cyber": [112.0, 260.0, 112.0],
	"diamond": [158.0, 260.0, 158.0],
	"dice": [165.0, 260.0, 165.0],
	"fortune": [149.0, 260.0, 149.0],
	"gambler": [165.0, 260.0, 165.0],
	"headless": [108.0, 260.0, 108.0],
	"hiding": [108.0, 260.0, 108.0],
	"hunter": [163.0, 260.0, 163.0],
	"ice": [158.0, 260.0, 158.0],
	"lava": [162.0, 260.0, 162.0],
	"lava_volcano": [189.0, 260.0, 189.0],
	"lightning": [157.0, 260.0, 157.0],
	"line": [148.0, 260.0, 148.0],
	"phoenix": [167.0, 260.0, 167.0],
	"pirate": [127.0, 260.0, 127.0],
	"rainbow": [156.0, 260.0, 156.0],
	"shell": [143.0, 260.0, 143.0],
	"space": [165.0, 260.0, 165.0],
	"stone": [151.0, 260.0, 151.0],
}


static func by_kind(kind: String) -> Dictionary:
	match kind:
		"attack": return ATTACK
		"hurt": return HURT
		"death": return DEATH
	return {}
