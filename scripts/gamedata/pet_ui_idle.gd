class_name PetUiIdle
extends RefCounted
## 界面立绘(选龟卡 / 选龟详情 / 图鉴 / 统领卡 / 冠军页)的逐帧待机表补丁 —— 只给 pets.json 没登记 sprite{} 的龟补。
## 用户 2026-11-09:「变脸龟没有待机动画吗」—— 28 只里只有变脸龟没登记逐帧待机图, 这些界面只能退回整张缩放「呼吸」,
##   看上去像不动; 战斗里它其实有两套 8 帧待机(TwoHeadArt, 每秒 7 帧)。
## 帧表由 tools/assetgen/build_two_head_ui_idle.py 从战斗那两套裁成立绘那一格(第 0 帧不透明部分 = 原静态立绘)。
## ★战斗不读这里: 战斗出生立绘 / 换形态 / 门禁 verify_two_head_form_art 都钉在 pets.json 的 img(静态图)上。
## 按 img 认(不是按龟 id): 图鉴近战形态页把 img 换成近战静态图(form_variants.portrait_pet), 这里接着换成近战那套待机。

const BY_IMG := {
	"pets/two_head.png": "pets/animations/two_head/ui_ranged_idle.png",
	"pets/two_head_melee.png": "pets/animations/two_head/ui_melee_idle.png",
}
## 与战斗 TwoHeadArt.CLIPS 的 *_idle 同一个节奏: 8 帧, 每秒 7 帧(界面 fps 公式 = 帧数 × 1000 / duration)
const SPRITE := {"frames": 8, "frameW": 80, "frameH": 81, "duration": 1143}


## 界面要用的那份宠物字典: 没补丁就原样返回同一个字典; 有补丁返回一份换了 img / sprite 的副本(不改 DataRegistry)。
static func of(pet: Dictionary) -> Dictionary:
	var img := str(pet.get("img", ""))
	if not BY_IMG.has(img) or pet.get("sprite", null) is Dictionary:
		return pet
	var path: String = BY_IMG[img]
	if not ResourceLoader.exists("res://assets/sprites/" + path):
		return pet
	var d: Dictionary = pet.duplicate()
	d["img"] = path
	d["sprite"] = SPRITE.duplicate()
	return d
