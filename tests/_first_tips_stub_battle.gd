extends Control
## verify_first_tips ⑦c 用: 只带 FirstTips.is_server_match 要读的那两样(_replay.mode / is_live)。不是战斗场。

var _replay := StubReplay.new()


class StubReplay extends RefCounted:
	var mode := "stream"
	var live = null

	func is_live() -> bool:
		return false
