## 推迟挂树(2026-10-27 · 门禁 verify_spawn_busy_root)。`Supabase._spawn` 建的请求节点都走这里。
##   由来: v0.22.1 陪练号离开背包时报「Parent node is busy setting up children, `add_child()` failed」,
##   调用链 InventoryScene._exit_tree → FriendsNet.put_lineup → Supabase._spawn 原来的同步 `root.add_child(n)`
##   ⇒ 节点不在树上 ⇒ `_send` 回失败 ⇒ 那次阵容没传上去(正式服 client_errors 里同类 4 条调用链 / 2 个号)。
##   根因: Godot 4.4 起 `change_scene_to_*` 当场摘下旧场景 ⇒ 旧场景 `_exit_tree` 跑在 root「忙」的那一刻;
##   引擎下发切后台 / 回前台通知那一刻同理(GameState 10-23 注释)。原来这一类在调用方一处处 call_deferred 绕
##   (排行榜 / 赛况板 / 对阵图 `_ready`、GameState / ErrorReporter 的通知), 离开背包这一处没人绕。
## ⇒ GDScript 读不到 root 忙不忙, 不猜: 一律推迟到消息队列刷新时挂(那时 root 不忙, 一般就在本帧之内);
##   用到树的地方(发 HTTPRequest / 等帧 / 看门狗 Timer)先 `await TreeJoin.joined(n)`, Timer 用 autostart。
##   (门禁 B 段在 4.6.3 上量过: 换场景进来的新场景 `_ready` 里是挂得上的。)
class_name TreeJoin
extends RefCounted

const _PENDING := &"tree_join_pending"


## 推迟把 n 挂到 root。n 在那之前已被释放 / 已排队释放 ⇒ 不挂。
static func join_deferred(n: Node) -> void:
	n.set_meta(_PENDING, true)
	Callable(TreeJoin, &"_join").call_deferred(n)


static func _join(n) -> void:
	if not is_instance_valid(n):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if n.is_inside_tree() or n.is_queued_for_deletion() or tree == null or tree.root == null:
		return
	tree.root.add_child(n)


## 等 n 进树。true = 在树上了; false = 不会再进树了(不是 `join_deferred` 挂的又不在树上 / 进过树又离开了)。
static func joined(n: Node) -> bool:
	if n.is_inside_tree():
		return true
	if not n.has_meta(_PENDING) or n.is_node_ready():
		return false
	await n.ready
	return n.is_inside_tree()
