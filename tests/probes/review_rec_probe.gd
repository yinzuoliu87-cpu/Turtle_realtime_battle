extends Node
## 审核片录制外壳(tools/review_reel.py 用; 2026-11-04 用户给的审核格式「寒冰龟的普攻…技能命中敌人…报多少秒…把所有龟都给我看」):
## 包住战斗场景, 每帧看受审龟的技能冷却, 冷却突然回满 = 放了一次技能, 打印 [CAST] frame=N(Movie Maker 帧号)。
## REVIEW_FORM(2026-11-05 用户「熔岩龟特效几乎看不见」⇒ 查出录像里龟已变身火山龟, 放的是火山技能):
##   normal  = 受审龟怒气每帧归零, 一直是普通形态(熔岩龟)
##   volcano = 开打 2 秒后直接变身火山龟(熔岩龟), 之后放的都是火山形态技能
var sc: Node = null
var f := 0
var tid := ""
var form := ""
var transformed := false
var last := {}
func _ready() -> void:
	tid = OS.get_environment("REVIEW_TURTLE")
	form = OS.get_environment("REVIEW_FORM")
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)
var _sfx_seen := 0
func _process(_d: float) -> void:
	f += 1
	## 这一帧新播的音效(Audio.played_total 涨了几条 ⇒ recent 末尾几条), 和 [CAST] / [POS] 同一套帧号(11-05: 画面与声音对齐审)
	var au = get_node_or_null("/root/Audio")
	if au != null and int(au.played_total) > _sfx_seen:
		var k: int = mini(int(au.played_total) - _sfx_seen, au.recent.size())
		for nm in au.recent.slice(au.recent.size() - k):
			print("[SFX] %d %s" % [f, nm])
		_sfx_seen = int(au.played_total)
	if sc == null or not ("_units" in sc):
		return
	for u in sc._units:
		if str(u.get("id", "")) == tid and str(u.get("side", "")) == "left":
			if form == "normal" and u.has("rage"):
				u["rage"] = 0.0
			elif form == "volcano" and not transformed and f > 60 and "_lava_sys" in sc:
				sc._lava_sys._lava_transform(u)
				transformed = true
				print("[FORM] frame=%d volcano" % f)
			if "_cam" in sc and sc._cam != null:   # 受审龟每帧的屏幕位置(tools/review_frames.py 按它跟拍裁切)
				var sp: Vector2 = sc._cam.unproject_position(sc._world_pos(u["pos"], 0.0))
				print("[POS] %d %d %d" % [f, int(sp.x), int(sp.y)])
			var cds: Dictionary = u.get("skill_cd", {})
			for k in cds:
				var v := float(cds[k])
				if last.has(k) and v > float(last[k]) + 0.5:
					print("[CAST] frame=%d skill=%s" % [f, str(k)])
				last[k] = v
			break
