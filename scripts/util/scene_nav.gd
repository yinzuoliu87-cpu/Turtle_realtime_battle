## 切场景(2026-10-23)—— 全项目点按钮换屏都走这一个。
##
## 由来: 正式服 iOS / Android 每个进程都报 `Condition "!is_inside_tree()" is true … can_process (node.cpp:902)`,
##   没有脚本栈。按钮 `pressed` 在**抬起**那一下发; 回调里同步 `change_scene_to_file` ⇒ 旧场景**当场**离树,
##   同一次抬起的触摸事件还在往下分发, GUI 拿这颗已离树的按钮去问 can_process ⇒ 报一条。
## 做法: ① 旧场景**当场停掉处理**(与同步切换时「旧场景当场离树、不再跑」同一语义): 在旧场景某个节点自己的
##          `_process` 里调 go() 时, 延后队列要到这一帧末尾才清, 同一帧里排在它后面的旧场景节点还会再跑一次
##          (回放 / 复算这类先挂好静态状态再切的, 旧战斗场多跑的那一下会去动给新场准备的状态);
##       ② 换屏本身延后到这一帧输入分发完。
## 门禁: tests/verify_scene_change_on_release.gd
class_name SceneNav
extends RefCounted


static func go(tree: SceneTree, path: String) -> void:
	if tree == null:
		return
	var cur := tree.current_scene
	if cur != null:
		cur.process_mode = Node.PROCESS_MODE_DISABLED
	tree.change_scene_to_file.call_deferred(path)
