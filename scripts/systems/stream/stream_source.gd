class_name StreamSource
extends RefCounted
## 服务器逐帧直播 · 块来源(S2 手机播放)。方案书 docs/plans/20261019-服务器逐帧直播.md §4。
##
## 播放器只问块来源三件事: 现在有几块可读(`available`)、第 i 块的字节(`chunk`)、服务器那一局录完了没有(`ended`)。
## 传输层(S4: Hetzner HTTPS 静态文件)将来再实现一个 HTTP 子类; 这里只有两个:
##   · `Dir`  本地目录(裁判 `--stream=<目录>` 写出来的 `<6 位序号>.bin` + `end.json`), 每次问都重新看盘 ⇒ 边录边播也能用
##   · `Mem`  内存里的块字节(门禁: 裁判 `keep` 模式留下的 `stream_chunks`); `limit` 可以人为卡住「服务器才录到第几块」
##
## ★块来源只管「有没有、是什么」, 不判对错: 版本 / 魔数 / 解压失败由播放器判, 判了就停在「无法播放」(绝不改成本机重算)。


## 接口(鸭子类型, 播放器只调这四个; 新的来源照这个形状写一个内部类即可):
##   available() -> int                 现在能读到第几块之前(连续的块数)
##   chunk(i: int) -> PackedByteArray   第 i 块的整个文件字节; 读不到返回空
##   ended() -> bool                    服务器那一局已经录完(收尾元数据已写)
##   end_meta() -> Dictionary           收尾元数据(end.json); 没有就是空


class Dir extends RefCounted:
	var dir := ""
	var _n := 0                   # 已确认存在的连续块数(只增不减: 文件不会被撤回)
	var _end: Dictionary = {}

	func _init(d: String) -> void:
		dir = d

	func available() -> int:
		while FileAccess.file_exists(dir.path_join("%06d.bin" % _n)):
			_n += 1
		return _n

	func chunk(i: int) -> PackedByteArray:
		var p := dir.path_join("%06d.bin" % i)
		if not FileAccess.file_exists(p):
			return PackedByteArray()
		return FileAccess.get_file_as_bytes(p)

	func ended() -> bool:
		return not end_meta().is_empty()

	func end_meta() -> Dictionary:
		if _end.is_empty():
			var p := dir.path_join("end.json")
			if FileAccess.file_exists(p):
				var d = JSON.parse_string(FileAccess.get_file_as_string(p))
				if d is Dictionary:
					_end = d
		return _end


class Mem extends RefCounted:
	var chunks: Array = []
	var meta: Dictionary = {}
	var limit := -1               # ≥0 ⇒ 只放出前 limit 块(模拟服务器还没录到), 而且不算录完

	func _init(c: Array, m: Dictionary = {}) -> void:
		chunks = c
		meta = m

	func available() -> int:
		return chunks.size() if limit < 0 else mini(limit, chunks.size())

	func chunk(i: int) -> PackedByteArray:
		if i < 0 or i >= available():
			return PackedByteArray()
		return chunks[i]

	func ended() -> bool:
		return limit < 0

	func end_meta() -> Dictionary:
		return meta if ended() else {}
