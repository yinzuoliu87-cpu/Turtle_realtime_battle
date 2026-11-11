## 切场景(2026-10-23)—— 全项目点按钮换屏都走这一个。
##
## 由来: 正式服 iOS / Android 每个进程都报 `Condition "!is_inside_tree()" is true … can_process (node.cpp:902)`,
##   没有脚本栈。按钮 `pressed` 在**抬起**那一下发; 回调里同步 `change_scene_to_file` ⇒ 旧场景**当场**离树,
##   同一次抬起的触摸事件还在往下分发, GUI 拿这颗已离树的按钮去问 can_process ⇒ 报一条。
## 做法: ① 旧场景**当场停掉处理**(与同步切换时「旧场景当场离树、不再跑」同一语义): 在旧场景某个节点自己的
##          `_process` 里调 go() 时, 延后队列要到这一帧末尾才清, 同一帧里排在它后面的旧场景节点还会再跑一次
##          (回放 / 复算这类先挂好静态状态再切的, 旧战斗场多跑的那一下会去动给新场准备的状态);
##       ② 换屏本身延后到这一帧输入分发完。
## ★2026-11-01 游戏必须联网(方案书 docs/plans/20261101b-游戏必须联网.md): 去匹配屏要先过 `OnlineGate`。
##   匹配屏是积分赛 / 闯关赛进对局的唯一一扇门(选龟页「出战」、周六排队回匹配屏都从这里走), 在这里拦一次 ⇒
##   正式包断网时到不了「本机挑对手、本机开打」那一步。连不上 ⇒ 当前屏上弹「无法连接服务器」, 重试连上了再走。
## 门禁: tests/verify_scene_change_on_release.gd · tests/verify_online_only.gd
class_name SceneNav
extends RefCounted

## 要先联网才能去的屏。
const ONLINE_ONLY := ["res://scenes/Matchmaking.tscn"]

## 【门禁注入点】有效 ⇒ 过了联网那一道之后不真换屏, 改调它(入参 = 目标路径)。默认无效 ⇒ 玩家路径一字不动。
## ⚠ static, 用完必须还原。
static var nav_for_test: Callable = Callable()
## ★切页过场(2026-11-05, SceneFader 头注): 有窗口时暗幕淡入 → 后台加载 → 换场 → 淡出。无头(门禁 / 陪练号 / 裁判)
##   照旧同步换场 —— 几百条门禁按帧数等换屏, 不让它们跟着变; 过场本身由 verify_scene_transition 把这个开关打开来量。
## ⚠ static, 门禁用完必须还原。
static var transition_in_headless := false


static func go(tree: SceneTree, path: String) -> void:
	if tree == null:
		return
	if path in ONLINE_ONLY and not OnlineGate.check(tree.current_scene, OnlineGate.WHAT_MATCH,
			func() -> void: go(tree, path)):
		return
	if nav_for_test.is_valid():
		nav_for_test.call(path)
		return
	var cur := tree.current_scene
	if cur != null:
		cur.process_mode = Node.PROCESS_MODE_DISABLED
	if DisplayServer.get_name() != "headless" or transition_in_headless:
		SceneFader.instance(tree).go(path)   # 换场在暗幕盖满之后(已过了这一帧的输入分发)
		return
	SkillText.flush_prewarm()   # 同步换场前让文案常量的后台预加载收完(两边同时编同一批脚本会拿到半成品, 见 SkillText.prewarm_busy)
	tree.change_scene_to_file.call_deferred(path)
