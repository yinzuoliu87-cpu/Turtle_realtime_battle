extends RefCounted
## SkillIcons — 技能 type → 图标路径的**单一查询点** (2026-08-29)。
##
## 用 preload 引:  const SkillIcons = preload("res://scripts/gamedata/skill_icons.gd")
##
## ★为什么单独开一份: 原来只有 `info_panel._skill_icon_path(sk: Dictionary)` ——
##   它要**技能字典**当参数, 而战斗里很多地方手上只有一个 **type 字符串**
##   (龟壳复制就是: 从敌人的 `active_skills` 里拿到的是 type)。
##   照着 info_panel 那套在战斗侧再手写一遍 = memory [[fb-hand-rolled-copies-drift]]
##   说的"抄一次永远落后一次"。
##
## ★三级回落, 顺序有讲究:
##   ① **多形态技能按当前形态取**(SkillForms) —— 海盗船/精英铁锤一格两态, 图标不同,
##      拿"技能池里那一条"会永远显示第一态
##   ② pets.json 的 skillPool[].icon（实测 112/112 条技能都有 icon 且文件都在）
##   ③ 查不到 → 返回 ""。**调用方必须能接受空串** ——
##      小将技(minionBodysurf/minionRocket)走 MinionCodex, 那张表里没有 icon 字段。
##
## ★贴图存在性【一定要查】: 没导入时 `ResourceLoader.exists` 是 false,
##   直接 load 会返回 null 而**一句报错都没有**(info_panel `_skill_icon_path` 头注踩过)。

const SkillForms = preload("res://scripts/gamedata/skill_forms.gd")

## type → "res://assets/sprites/..." 绝对路径; 查不到或贴图没导入返回 ""。
##
## `u`: 可选。给了就按这只单位【当前的形态】取(多形态技能用)；不给就走 pets.json。
static func path_of(stype: String, u = null) -> String:
	if stype == "":
		return ""
	## ① 多形态技能: 按当前形态
	if SkillForms.is_multi(stype):
		var f: Dictionary = SkillForms.current_form(u if u is Dictionary else {}, stype)
		var p1 := _abs(str(f.get("icon", "")))
		if p1 != "":
			return p1
	## ② pets.json 技能池
	for pid in DataRegistry.pet_by_id.keys():
		var pet: Dictionary = DataRegistry.pet_by_id[pid]
		for sk in (pet.get("skillPool", []) as Array):
			if sk is Dictionary and str((sk as Dictionary).get("type", "")) == stype:
				return _abs(str((sk as Dictionary).get("icon", "")))
	## ③ 查不到 —— 调用方必须能接受空串(小将技就走到这里)
	return ""


static func _abs(rel: String) -> String:
	if not rel.ends_with(".png"):
		return ""
	var p := "res://assets/sprites/" + rel
	return p if ResourceLoader.exists(p) else ""
