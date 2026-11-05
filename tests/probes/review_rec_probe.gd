extends Node
## 审核片录制外壳(tools/review_reel.py 用; 2026-11-04 用户给的审核格式「寒冰龟的普攻…技能命中敌人…报多少秒…把所有龟都给我看」):
## 包住战斗场景, 每帧看受审龟的技能冷却, 冷却突然回满 = 放了一次技能, 打印 [CAST] frame=N(Movie Maker 帧号)。
var sc: Node = null
var f := 0
var tid := ""
var last := {}
func _ready() -> void:
	tid = OS.get_environment("REVIEW_TURTLE")
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)
func _process(_d: float) -> void:
	f += 1
	if sc == null or not ("_units" in sc):
		return
	for u in sc._units:
		if str(u.get("id", "")) == tid and str(u.get("side", "")) == "left":
			var cds: Dictionary = u.get("skill_cd", {})
			for k in cds:
				var v := float(cds[k])
				if last.has(k) and v > float(last[k]) + 0.5:
					print("[CAST] frame=%d skill=%s" % [f, str(k)])
				last[k] = v
			break
