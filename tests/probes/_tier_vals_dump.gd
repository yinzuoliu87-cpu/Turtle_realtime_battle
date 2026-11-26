extends Node
## 探针: 打出 127~156 每件正文里的分档数值(按出现顺序), 供写分星短标签(EquipTierLabels)。不进门禁。
const CD := preload("res://scripts/scenes/codex/detail_views.gd")


func _ready() -> void:
	await get_tree().process_frame
	for eq in DataRegistry.phase2_equipment:
		var eid := str(eq.get("id", ""))
		var n := int(eid.trim_prefix("p2eq_"))
		if n < 127 or n > 156:
			continue
		var plain: String = SkillText.equip_full(eq) + "\n" + SkillText.render_consts(str(eq.get("effectDesc3", "")))
		var vals: Array = CD.tier_values_in_order(plain)
		print("@@", eid, " ", eq.get("name", ""), " | ", vals.size(), " | ", str(vals))
		print("@@TEXT ", plain.replace("\n", " ⏎ "))
	get_tree().quit(0)
