extends Node
## _probe_bamboo_growth.gd —— 竹叶龟【生长】一局里长了多少、跨路是否保留(2026-11-19 方案书 20261119 竹叶龟生长随大轮保留 §2 取数)
## 截图台那份真实玩家 + 把第一统领换成竹叶龟(上路), 真战斗场 det 模式整局打完。
## 每帧记: 我方竹叶龟所在路(_dl_state 切换) / maxHp / 攻击力 / 基础攻击力; maxHp 每涨一次记一笔。不是门禁, 只打数。
## 用法: PROBE_SMACK=1 选【竹击】(skill idx 2), 否则默认技能。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"

func _ready() -> void:
	await get_tree().process_frame
	load("res://tests/_setup_appstore.gd").run()
	var gs = get_node("/root/GameState")
	gs.season_leaders = ["bamboo", "phoenix", "lightning"]
	gs.dual_lineup = {}
	gs.get_dual_lineup()
	gs.persistent_equipped = {"bamboo": [], "phoenix": [], "lightning": []}
	if OS.has_environment("PROBE_SMACK"):
		gs.loadouts["bamboo"] = 2
	gs.dual_active = true
	var b = load(BATTLE_SCENE).instantiate()
	b._deterministic = true
	add_child(b)
	var last_state := ""
	var lane_i := 0
	var seen_unit = null
	var grows: Array = []
	var lanes: Array = []
	for _f in range(60 * 60 * 8):
		await get_tree().process_frame
		if not is_instance_valid(b):
			break
		var st := str(b._dl_state)
		if st != last_state:
			print("  [state] %s → %s  t=%.1f" % [last_state, st, float(b._t)])
			last_state = st
		var bu = null
		for u in b._units:
			if str(u.get("id", "")) == "bamboo" and str(u.get("side", "")) == "left":
				bu = u
		if bu == null:
			continue
		if not is_same(bu, seen_unit):
			seen_unit = bu
			lane_i += 1
			lanes.append({"lane": lane_i, "state": st, "maxHp0": float(bu["maxHp"]), "atk": float(bu["atk"]), "base_atk": float(bu["base_atk"]), "skills": str(bu.get("active_skills", []))})
			print("  [新单位] 第 %d 次出场 state=%s maxHp=%.0f atk=%.1f base_atk=%.1f 技能=%s" % [lane_i, st, float(bu["maxHp"]), float(bu["atk"]), float(bu["base_atk"]), str(bu.get("active_skills", []))])
			bu["_probe_last_max"] = float(bu["maxHp"])
		var m := float(bu["maxHp"])
		if m > float(bu.get("_probe_last_max", m)) + 0.01:
			grows.append({"lane": lane_i, "d": m - float(bu["_probe_last_max"]), "atk": float(bu["atk"]), "base_atk": float(bu["base_atk"])})
			bu["_probe_last_max"] = m
		if st == "done" or st == "result":
			break
	print("=== 生长 %d 次 ===" % grows.size())
	var tot := 0.0
	var new18 := 0.0
	var new25 := 0.0
	for g in grows:
		tot += float(g["d"])
		new18 += 0.18 * float(g["atk"])
		new25 += 0.25 * float(g["atk"])
		print("  第%d次出场 +%.1f (atk %.1f base %.1f)" % [int(g["lane"]), float(g["d"]), float(g["atk"]), float(g["base_atk"])])
	print("现行合计 +%.0f · 换成 18%%×攻击力 ≈ +%.0f · 25%%×攻击力 ≈ +%.0f" % [tot, new18, new25])
	print(str(lanes))
	get_tree().quit(0)
