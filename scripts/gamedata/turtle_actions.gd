class_name TurtleActions
extends RefCounted
## 外包 11 只龟的动作帧表(普攻 / 受击 / 阵亡) —— 由 tools/assetgen/build_spine_actions.py 生成, **别手改**(改关键帧后重跑脚本)。
## 方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.3: 在画师 Spine 原骨骼上写关键帧, 求值器(已与官方运行库逐帧对账)渲成像素序列帧。
## 帧表值 = [相对 assets/sprites/ 的路径, 每秒帧率], 与主场景 ACTION_ATTACK 同口径; 主场景表里没有的龟才查这里(battle_vfx._play_action)。
## 方帧 272×272(_resolve_action 只认方帧); 第 0 帧 = 待机第 0 帧同姿势、同一像素尺寸。

const ATTACK := {
	"angel": ["pets/animations/angel/attack.png", 15.0],   # 8 帧
	"bamboo": ["pets/animations/bamboo/attack.png", 15.0],   # 8 帧
	"basic": ["pets/animations/basic/attack.png", 15.0],   # 8 帧
	"fortune": ["pets/animations/fortune/attack.png", 15.0],   # 8 帧
	"ice": ["pets/animations/ice/attack.png", 15.0],   # 8 帧
	"lava": ["pets/animations/lava/attack.png", 15.0],   # 8 帧
	"lightning": ["pets/animations/lightning/attack.png", 15.0],   # 8 帧
	"phoenix": ["pets/animations/phoenix/attack.png", 15.0],   # 8 帧
	"rainbow": ["pets/animations/rainbow/attack.png", 15.0],   # 8 帧
	"shell": ["pets/animations/shell/attack.png", 15.0],   # 8 帧
	"stone": ["pets/animations/stone/attack.png", 15.0],   # 8 帧
}
const HURT := {
	"angel": ["pets/animations/angel/hurt.png", 15.0],   # 6 帧
	"bamboo": ["pets/animations/bamboo/hurt.png", 15.0],   # 6 帧
	"basic": ["pets/animations/basic/hurt.png", 15.0],   # 6 帧
	"fortune": ["pets/animations/fortune/hurt.png", 15.0],   # 6 帧
	"ice": ["pets/animations/ice/hurt.png", 15.0],   # 6 帧
	"lava": ["pets/animations/lava/hurt.png", 15.0],   # 6 帧
	"lightning": ["pets/animations/lightning/hurt.png", 15.0],   # 6 帧
	"phoenix": ["pets/animations/phoenix/hurt.png", 15.0],   # 6 帧
	"rainbow": ["pets/animations/rainbow/hurt.png", 15.0],   # 6 帧
	"shell": ["pets/animations/shell/hurt.png", 15.0],   # 6 帧
	"stone": ["pets/animations/stone/hurt.png", 15.0],   # 6 帧
}
const DEATH := {
	"angel": ["pets/animations/angel/death.png", 15.0],   # 15 帧
	"bamboo": ["pets/animations/bamboo/death.png", 15.0],   # 15 帧
	"basic": ["pets/animations/basic/death.png", 15.0],   # 15 帧
	"fortune": ["pets/animations/fortune/death.png", 15.0],   # 15 帧
	"ice": ["pets/animations/ice/death.png", 15.0],   # 15 帧
	"lava": ["pets/animations/lava/death.png", 15.0],   # 15 帧
	"lightning": ["pets/animations/lightning/death.png", 15.0],   # 15 帧
	"phoenix": ["pets/animations/phoenix/death.png", 15.0],   # 15 帧
	"rainbow": ["pets/animations/rainbow/death.png", 15.0],   # 15 帧
	"shell": ["pets/animations/shell/death.png", 15.0],   # 15 帧
	"stone": ["pets/animations/stone/death.png", 15.0],   # 15 帧
}
## 归一 [动作图本体高, 脚底行, 待机本体高] —— 与主场景 ANIM_NORM 同口径(elite_system._elite_fix_norm 读)。
##   两个本体高相等(动作与待机同一个像素尺寸); 脚底行 = 待机格子底边在方帧里的行(动作一播不上下跳)。
const NORM := {
	"angel": [160.0, 260.0, 160.0],
	"bamboo": [165.0, 260.0, 165.0],
	"basic": [141.0, 260.0, 141.0],
	"fortune": [149.0, 260.0, 149.0],
	"ice": [158.0, 260.0, 158.0],
	"lava": [162.0, 260.0, 162.0],
	"lightning": [157.0, 260.0, 157.0],
	"phoenix": [167.0, 260.0, 167.0],
	"rainbow": [156.0, 260.0, 156.0],
	"shell": [143.0, 260.0, 143.0],
	"stone": [151.0, 260.0, 151.0],
}


static func by_kind(kind: String) -> Dictionary:
	match kind:
		"attack": return ATTACK
		"hurt": return HURT
		"death": return DEATH
	return {}
