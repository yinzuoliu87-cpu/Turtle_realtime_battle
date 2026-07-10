extends Node
## soak_memory.gd — 5分钟持续战斗浸泡: 测对象/节点/单位数是【平台化】还是【线性无限涨】
## 用户 2026-07-11 疑: 黑屏是不是"内存不断增长"。评审场假人不死→持续战斗, 每20s采样一次。
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
func _ready() -> void:
	await get_tree().process_frame
	var gs=get_node_or_null("/root/GameState")
	if gs!=null: gs.test_mode=true
	var scene=RTScene.new(); add_child(scene)
	await get_tree().process_frame; await get_tree().process_frame
	print("t(s)  nodes  orphans  objects  units  tweens  pending  follow")
	var samples:=[]
	var t:=0.0; var nxt:=0.0
	while t<300.0:
		await get_tree().process_frame
		t+=get_process_delta_time()
		if t>=nxt:
			nxt+=20.0
			var nodes:=get_tree().get_node_count()
			var orph:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
			var objs:=int(Performance.get_monitor(Performance.OBJECT_COUNT))
			var u:=int((scene._units as Array).size()) if scene.get("_units")!=null else -1
			var tw:=int((scene._sim_tweens as Array).size()) if scene.get("_sim_tweens")!=null else -1
			var pd:=int((scene._pending_shots as Array).size()) if scene.get("_pending_shots")!=null else -1
			var fv:=int((scene._follow_vfx as Array).size()) if scene.get("_follow_vfx")!=null else -1
			samples.append([t,objs])
			print("%5.0f %6d %8d %8d %6d %7d %8d %7d"%[t,nodes,orph,objs,u,tw,pd,fv])
	# 判定: 后半段还在涨吗
	if samples.size()>=4:
		var mid: Array = samples[int(samples.size()/2)]
		var last: Array = samples[samples.size()-1]
		var rate: float = (float(last[1])-float(mid[1]))/maxf(1.0,float(last[0])-float(mid[0]))
		print("")
		print("后半段(%.0fs→%.0fs)对象增长率: %.2f 个/秒"%[float(mid[0]),float(last[0]),rate])
		print("判定: "+("★线性增长(疑泄漏)" if rate>2.0 else ("轻微增长" if rate>0.3 else "已平台化(无泄漏)")))
	get_tree().quit(0)
