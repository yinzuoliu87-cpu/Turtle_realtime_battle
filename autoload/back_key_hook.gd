extends Node
## 安卓返回键 / 返回手势的接收点(2026-11-18 · 做法见 scripts/util/back_key.gd 头注)。
## 引擎把 NOTIFICATION_WM_GO_BACK_REQUEST 从根节点往下逐个传, 这时根节点「忙」, 同步 add_child(确认框 / 换屏暗幕)会失败
##   (GameState._notification 那条注释同一个坑) ⇒ 延后到这一帧末尾再处理。
## ★单独一个 autoload: GameState.gd 已顶到单文件 3000 行上限(tools/arch_budget.py)。


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle.call_deferred()


func _handle() -> void:
	BackKey.handle(get_tree())
