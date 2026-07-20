extends Node

## DataRegistry — 全局数据注册表 (Autoload 单例)
##
## 启动时加载 res://data/*.json (从 Phaser PoC 迁移而来), 内存常驻供全 Scene 取用。
##
## 用法:
##   var pet = DataRegistry.pet_by_id["basic"]
##   for pet in DataRegistry.all_pets: print(pet.name)
##   var eq = DataRegistry.equipment_by_id["e_blade"]
##
## 数据来源: games/turtle-battle-poc/scripts/extract-godot-data.ts 一键转出。
##   PoC 数据改了 → 重跑 extractor → 这边自动刷新。

var all_pets: Array = []
var pet_by_id: Dictionary = {}
# 上线版只放这 11 龟 (其余隐藏: 图鉴/选龟/AI池不显, 数据保留, 翻名单即放出). 战斗按 id 仍可用任意龟.
const LAUNCH_IDS := ["basic", "stone", "bamboo", "angel", "ice", "fortune", "rainbow", "lightning", "phoenix", "shell", "lava"]
var launch_pets: Array = []   # all_pets 里属于 LAUNCH_IDS 的子集
var all_equipment: Array = []
var equipment_by_id: Dictionary = {}
# 二阶段装备 (三合一升星, xlsx「处理B」): 59件, 效果已全部接进实时战斗(见 scripts/engine/phase2_equip_runtime.gd)。
# (原注释说"仅数据+名字+emoji·effectImpl=false"是早期状态的化石; 数据里 59/59 都是 effectImpl:true, 该字段本身无代码读取)
var phase2_equipment: Array = []
var phase2_equipment_by_id: Dictionary = {}
var status_defs: Array = []
var battle_rules: Array = []
var passive_icons: Dictionary = {}
var rarity_mult: Dictionary = {}


func _ready() -> void:
	print("[DataRegistry] Loading PoC data → res://data/*.json")

	all_pets = _load_json_array("res://data/pets.json")
	for pet in all_pets:
		pet_by_id[pet["id"]] = pet
		launch_pets.append(pet)   # 用户2026-07-18「把28只龟全部变为选龟可用」: 28龟全封板→全部上线(原LAUNCH_IDS只11只的门控已废, 常量保留供未来分批上线参考)


	all_equipment = _load_json_array("res://data/equipment.json")
	for eq in all_equipment:
		equipment_by_id[eq["id"]] = eq

	phase2_equipment = _load_json_array("res://data/phase2-equipment.json")
	for eq in phase2_equipment:
		phase2_equipment_by_id[eq["id"]] = eq

	status_defs = _load_json_array("res://data/status.json")
	battle_rules = _load_json_array("res://data/battle-rules.json")
	passive_icons = _load_json_dict("res://data/passive-icons.json")
	rarity_mult = _load_json_dict("res://data/rarity-mult.json")


	print("[DataRegistry] ✓ loaded: %d pets, %d equipment, %d status, %d rules"
		% [all_pets.size(), all_equipment.size(), status_defs.size(),
		   battle_rules.size()])


func _load_json_array(path: String) -> Array:
	var result = _load_json(path)
	if result is Array:
		return result
	push_warning("[DataRegistry] expected array at " + path)
	return []


func _load_json_dict(path: String) -> Dictionary:
	var result = _load_json(path)
	if result is Dictionary:
		return result
	push_warning("[DataRegistry] expected dict at " + path)
	return {}


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[DataRegistry] file not found: " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[DataRegistry] cannot open: " + path)
		return null
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("[DataRegistry] invalid JSON: " + path)
	return parsed
