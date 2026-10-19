extends "res://tests/verify_stream_coverage.gd"
## verify_stream_coverage 的第 3 片(共 4 片): 判据、对象表、已知清单全在 verify_stream_coverage.gd, 这里只换分片号。
## 分片 = 对象序号 % 4(龟 / 装备 / 羁绊 / 小将 / 大师交错分到四片, 每片约 50 个对象、约 1 分钟)。


func _init() -> void:
	SHARD = 2
	SHARDS = 4
