class_name CastSheets
extends RefCounted
## 外包 11 只以外的龟的技能释放动作 / 持续状态循环 —— 由 tools/assetgen/build_extra_casts.py 生成, **别手改**。
## 与 TurtleActions.CAST 同口径: [相对 assets/sprites/ 的路径, 帧率, 释放帧]; AttackRhythm.cast_entry 先查 TurtleActions 再查这里。
## 忍者 / 幽灵形象不动(用户点名), 只给没有身体动作的技能补段(方案书 20261105b §4.4)。

const CAST := {
	"ghost": {
		"ghostPhantom": ["pets/animations/ghost/cast_ghostPhantom.png", 12.0, 4],   # 7 帧 · ai
		"ghostStorm": ["pets/animations/ghost/cast_ghostStorm.png", 12.0, 4],   # 7 帧 · ai
	},
	"ninja": {
		"ninjaBomb": ["pets/animations/ninja/cast_ninjaBomb.png", 12.0, 4],   # 7 帧 · ai
		"ninjaShuriken": ["pets/animations/ninja/throw.png", 12.0, 3],   # 5 帧 · sheet
	},
}
## 持续状态循环 [状态名, 路径, 帧率](状态期间替代待机)
const STATE := {
	"ghost": [["ghostPhase", "pets/animations/ghost/state_ghostPhase.png", 8.0]],
}
