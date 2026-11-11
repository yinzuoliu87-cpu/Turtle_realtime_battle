extends Node
## 忍者龟动作播放探针(不进门禁; 跑法: REVIEW=1 REVIEW_TURTLE=ninja REVIEW_SKILL=1~3 + 隔离存档 + godot-quiet.sh --fixed-fps 60 res://tests/probes/_ninja_anim_probe.tscn。11-10 用户「有的时候忍者龟这个整个动作播放是不是有问题啊」)。默认对战(右队 demo 里有忍者), 逐帧记录忍者:
## 帧条文件 / 帧号 / anim_action / _manual_anim / sim 状态 / 是否在冲刺; 帧条或动作一变就打一行 [CHG], 普攻结算 / 放技能 / 冲刺开始打 [EVT]。
var sc: Node = null
var f := 0
var last := {}
var last_cd := {}
const MAX_F := 3600


func _ready() -> void:
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)


func _process(_d: float) -> void:
	f += 1
	if f > MAX_F:
		get_tree().quit()
		return
	if sc == null or not ("_units" in sc):
		return
	for u in sc._units:
		if str(u.get("id", "")) != "ninja":
			continue
		var key: String = "%s#%d" % [str(u.get("side", "")), int(u.get("uid", 0)) if u.has("uid") else 0]
		var spr = u.get("sprite", null)
		if not (spr is Sprite3D) or not is_instance_valid(spr):
			continue
		var s: Sprite3D = spr
		var sd: Dictionary = u.get("anim_sd", {})
		var tex = s.texture
		var file: String = tex.resource_path.get_file() if tex != null else "-"
		var act := str(u.get("anim_action", ""))
		var st := "%s/%s" % [str(u.get("state", "")), str(u.get("pending", ""))]
		var cur := {"file": file, "act": act, "manual": bool(u.get("_manual_anim", false)), "glide": bool(u.get("_ninja_gliding", false)), "alive": bool(u.get("alive", false))}
		var prev: Dictionary = last.get(key, {})
		if prev.is_empty() or prev["file"] != cur["file"] or prev["act"] != cur["act"] or prev["manual"] != cur["manual"] or prev["glide"] != cur["glide"] or prev["alive"] != cur["alive"]:
			print("[CHG] %d t=%.3f %s file=%s act=%s frame=%d/%d manual=%s glide=%s st=%s fps=%.1f" % [f, float(sc._t), key, file, act, s.frame, s.hframes * s.vframes, str(cur["manual"]), str(cur["glide"]), st, float(sd.get("fps", 0.0))])
		last[key] = cur
		## 普攻结算: atk_cd 跳涨; 放技能: skill_cd 跳涨; 冲刺: _ninja_last_dash 变
		var cd := float(u.get("atk_cd", 0.0))
		if last_cd.has(key + "atk") and cd > float(last_cd[key + "atk"]) + 0.2:
			print("[EVT] %d t=%.3f %s 普攻结算 file=%s act=%s frame=%d manual=%s" % [f, float(sc._t), key, file, act, s.frame, str(cur["manual"])])
		last_cd[key + "atk"] = cd
		var cds: Dictionary = u.get("skill_cd", {})
		for k in cds:
			var v := float(cds[k])
			if last_cd.has(key + str(k)) and v > float(last_cd[key + str(k)]) + 0.5:
				print("[EVT] %d t=%.3f %s 放技能 %s file=%s act=%s frame=%d manual=%s glide=%s" % [f, float(sc._t), key, str(k), file, act, s.frame, str(cur["manual"]), str(cur["glide"])])
			last_cd[key + str(k)] = v
		var ld := float(u.get("_ninja_last_dash", -99.0))
		if last_cd.has(key + "dash") and ld != float(last_cd[key + "dash"]):
			print("[EVT] %d t=%.3f %s 冲刺开始 file=%s act=%s frame=%d st=%s" % [f, float(sc._t), key, file, act, s.frame, st])
		last_cd[key + "dash"] = ld
