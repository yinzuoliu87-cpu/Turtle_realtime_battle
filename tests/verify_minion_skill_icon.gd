extends Node
## verify_minion_skill_icon —— 小将的两个主动技在信息面板技能格里有图标(2026-10-06 补图前那一格是空的)。
## 走产品自己的取数链: MinionCodex.skill_desc(type) → info_panel._skill_bar_entries 的 icon。
## 2026-10-29 加援军小将「四面合围」(ReserveConsts.SKILL): 图没交时 MinionCodex.info 会把路径清成空串, 这里就红。

const MC := preload("res://scripts/gamedata/minion_codex.gd")
var _fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fails += 1


func _ready() -> void:
	var n := 0
	for t in ["minionBodysurf", "minionRocket", ReserveConsts.SKILL]:
		var md = MC.skill_desc(t)
		_ok("%s 有文案条目" % t, md != null)
		if md == null:
			continue
		n += 1
		var ip := "res://assets/sprites/" + str(md.get("icon", ""))
		_ok("%s 有图标且贴图在(%s)" % [t, ip], str(md.get("icon", "")) != "" and ResourceLoader.exists(ip))
	_ok("分母: 三个小将技能(近战 / 远程 / 援军)都查到了", n == 3, str(n))
	if _fails == 0:
		print("ALL PASS — 小将技能有图标")
	else:
		print("FAIL x%d" % _fails)
	get_tree().quit()
