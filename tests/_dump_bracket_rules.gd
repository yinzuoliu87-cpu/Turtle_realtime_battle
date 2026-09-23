extends Node
## _dump_bracket_rules.gd — 把 `bracket.gd` 的切桶答案打成 JSON，给真服务器探针比对用。
##
## ★不是自证测试(文件名不以 `verify_` 开头 ⇒ 门禁不会自动发现它)。
##   它的用处只有一个: 让 `tools/probe_finals_server.py` 拿到**规格那一份**的答案,
##   逐个人数去对**服务端执行那一份**(`finals_bucket_size` / `_count` / `_of`)。
##
## ★为什么需要这条: 切桶是**服务端一次性**的事, 客户端只从回包里拿「这个桶几个人」,
##   所以 `bucket_size_for` / `bucket_count` / `bucket_of_seed` 在产品代码里**零个调用者** ——
##   它们是**规格**(41 条门禁守着), SQL 里那一份才是**实现**。
##   两份必须给同一个答案, 而"必须"要有人真的去量(memory `fb-hand-rolled-copies-drift`)。
##
## 跑法: <godot> --headless --path . res://tests/_dump_bracket_rules.tscn --quit-after 120

const B := preload("res://scripts/gamedata/bracket.gd")


func _ready() -> void:
	var out: Dictionary = {"size": {}, "count": {}, "of": {}}
	for n in range(0, 401):
		out["size"][str(n)] = B.bucket_size_for(n)
		out["count"][str(n)] = B.bucket_count(n)
	## 蛇形: 几种桶数 × 前 40 个种子
	for nb in [1, 2, 3, 4, 5, 7, 8, 13]:
		var row: Array = []
		for i in range(40):
			row.append(B.bucket_of_seed(i, nb))
		out["of"][str(nb)] = row
	var p := "user://bracket_rules.json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("DUMPED ", ProjectSettings.globalize_path(p))
	get_tree().quit(0)
