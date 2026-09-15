class_name AxeArt
extends RefCounted
## 096 小木斧九个形态的【悬空 3D 斧头】帧表登记 (2026-09-15)
##
## ★由来: 用户 2026-09-15「我觉得斧头召唤物这个形象做的太差了，你能不能用blender搞一把3D的就那种在空中的斧头，
##   应该要九把吧，因为9种形态，然后他们移动，idel，攻击，有什么被动的话你就让斧头挥动起来，做多种攻击运动，
##   然后也做好挥舞特效，就是像刀光那样吧，斩击特效」。
##   旧立绘是【一个穿潜水盔甲、手里拿斧头的人形】(PixelLab), 九个形态共用一套 —— 不是"一把斧头"。
##
## ★素材: tools/blender_axe_summon.py 渲 → tools/pixelize_sheet.py(调色板 axe_<形态>) →
##   assets/sprites/vfx/eq096-axe-<形态>-<动作>.png, 横排 8 帧 × 112 格, 刀光与挥动同帧烘在里面。
##
## ★尺寸: 九把斧是同一个正交镜头渲的 ⇒ 每个贴图像素代表的世界尺寸一样。
##   引擎通用规则「pixel_size = 身高 / 帧高」默认本体填满整帧, 而这套为了挥砍在四周留了画布
##   (80 格时砸/劈/插地的刃出格被切, 放到 112) ⇒ 套通用规则斧头只剩 0.7 m, 又回到「只有龟一半高」。
##   ⇒ 待机、走路、普攻、招式一律用 TEXEL_M: 待机斧高 45 像素 × TEXEL_M = 龟身高中位 1.40 m。
## ★贴地: 待机帧里柄头最低点在第 72 行(九个形态实测一致); FEET_ROW = 80 ⇒ 斧头悬空 8 像素(约 0.25 m)。

const CELL := 112
const IDLE_BODY_PX := 45.0     # 铁斧待机帧斧高(实测 28..72 行)
const BODY_H_M := 1.40         # 龟身高中位(verify_summon_art ③ 量的同一个分布)
const TEXEL_M := BODY_H_M / IDLE_BODY_PX
const FEET_ROW := 80.0

const FORMS := ["wood", "stone", "iron", "gold", "diamond", "undead", "seraph", "holo", "ember"]

## 动作 → fps。帧数从旧表的 6 变成 8, 时长照旧表的节拍不变(旧表 fps 由代码节拍倒推, 见 ActionElite 头注)。
const FPS := {
	"idle": 6.25,      # 乒乓 8 帧 / 1.28 秒(与 _EQ_BODY_SPR 的 duration 1280 同口径)
	"walk": 13.33,     # 旧 6 帧 @10 = 0.6 秒一圈
	"attack": 16.0,    # 旧 6 帧 @12 = 0.5 秒
	"cast": 16.0,      # 旧 6 帧 @12
	"smash": 10.67,    # 旧 6 帧 @8 = 0.75 秒(普攻间隔 1.25 秒的 60%)
	"cleave": 10.67,
	"sweep": 10.67,
	"slam": 10.67,
	"execute": 10.67,
	"charge": 10.67,   # 循环, 单圈 0.75 秒
	"plant": 10.67,    # 循环, 单圈 0.75 秒
	"throw": 20.0,     # 旧 6 帧 @15 = 0.4 秒(4 秒甩 10 把)
}

## ActionElite 里斧头招式键 → 动作名
const ELITE_KEYS := {
	"axe_cast": "cast", "axe_smash": "smash", "axe_cleave": "cleave", "axe_sweep": "sweep",
	"axe_charge": "charge", "axe_slam": "slam", "axe_throw": "throw", "axe_plant": "plant",
	"axe_execute": "execute",
}


## 这把斧头该用哪个形态: 选了最终造物就是造物, 否则是当前进化档位。认不出来一律木斧。
static func form_of(final_key: String, stage_key: String) -> String:
	if FORMS.has(final_key):
		return final_key
	return stage_key if FORMS.has(stage_key) else "wood"


static func rel_path(form: String, action: String) -> String:
	return "vfx/eq096-axe-%s-%s.png" % [form, action]


static func row(form: String, action: String) -> Array:
	return [rel_path(form, action), float(FPS.get(action, 10.67))]


static func offy() -> float:
	return FEET_ROW - float(CELL) * 0.5


## 把形态帧表装到斧头上: 待机 / 走路 / 普攻三条通道 + 统一贴图尺寸。
## 招式帧(ActionElite 那九个)由 `AxeSystem.play_action` 按 `_axe_form` 取。
## 返回 true = 待机表真的解析到了(门禁拿它当分母)。
static func apply(battle, ax: Dictionary, form: String) -> bool:
	ax["_axe_form"] = form
	ax["_art_px"] = TEXEL_M
	ax["_art_offy"] = offy()
	ax["idle_px"] = TEXEL_M
	ax["idle_offy"] = offy()
	ax["_act_rows"] = {"attack": row(form, "attack")}
	var wr: Array = row(form, "walk")
	ax["run_sd"] = battle._resolve_action(str(wr[0]), float(wr[1]))
	var idle: Dictionary = battle._resolve_action(rel_path(form, "idle"), float(FPS["idle"]))
	if idle.is_empty():
		return false
	ax["idle_sd"] = idle
	battle._set_anim_sheet(ax, idle, "", true)
	return true
