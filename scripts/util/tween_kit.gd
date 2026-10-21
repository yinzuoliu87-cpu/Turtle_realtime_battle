class_name TweenKit
extends RefCounted
## tween_kit.gd — 界面上的循环 tween 一律走这里(2026-10-13 内测)。
##
## ★由来: 内测报错表里 `Condition "!is_inside_tree()" is true` @ `can_process`(iOS 排行榜 5 次、选龟页各端都有),
##   只有引擎栈没有脚本栈 ⇒ 不是脚本调出来的, 是 SceneTree 每帧推进 tween 时问被绑节点「能不能处理」。
##   换场景时旧场景先移出树、稍后才释放; 中间这一拍里绑在它上面的**循环** tween 照样被推进 ⇒ 报错。
##   一次性 tween 很快就结束, 循环的永远不结束, 所以只要它们在。
## ⇒ 建循环 tween 时挂到节点的 tree_exiting 上: 节点一要离开树就 kill, 引擎不再推进它。

## 在 node 上建一个无限循环的 tween; node 离开场景树时自动停掉。
static func loop_on(node: Node) -> Tween:
	var t := node.create_tween().set_loops()
	_stop_on_exit(node, t)
	return t


## 在 host 上建、绑到 bind 节点的无限循环 tween(ShopScene 的「create_tween().bind_node(x).set_loops()」形状)。
static func loop_bound(host: Node, bind: Node) -> Tween:
	var t := host.create_tween().bind_node(bind).set_loops()
	_stop_on_exit(bind, t)
	return t


## ★只在「真离开」时停(2026-10-21): UIFrame 收编(remove_child + add_child 搬进设计框)也会发 tree_exiting,
##   原来一律 kill ⇒ 收编之前建的循环全死 —— 商店四盏灯笼的光从做好那天起一次没闪过(用户「商店你不是说灯是动态吗」)。
##   ⇒ 离开那一刻先暂停(引擎不再推进它, 上面那条 can_process 报错的根因照样堵住),
##     这一拍末尾再看: 回到树里了(只是搬家)就接着放, 没回来就 kill。连接不再是一次性的: 搬几次家都管。
## ★延迟那一下只记节点的 id、不抓节点本身: 换场景时节点可能在延迟调用之前就释放了,
##   抓着它的 lambda 一调就是引擎报错「Lambda capture ... was freed」(进门禁致命正则, 也会被报错上报收走)。
static func _stop_on_exit(node: Node, t: Tween) -> void:
	var nid := node.get_instance_id()
	node.tree_exiting.connect(func() -> void:
		if t == null or not t.is_valid():
			return
		t.pause()
		_resume_or_kill.call_deferred(nid, t))


static func _resume_or_kill(nid: int, t: Tween) -> void:
	if t == null or not t.is_valid():
		return
	var n := instance_from_id(nid) as Node
	if n != null and n.is_inside_tree():
		t.play()
	else:
		t.kill()
