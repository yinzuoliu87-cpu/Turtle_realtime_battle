extends RefCounted
## save_own_write.gd — 云存档「回包丢了 ⇒ 永久冲突」自愈(supabase.gd 的 D-8 存档同步调它)
##
## ★根因(2026-10-23 LouisT01 #F5ZRDR 实测, 手机沙盒里 savegame.before-recover 对照云端第 441 版):
##   10-17 切后台那一推, 服务端已经收下(第 441 版), 回包没回来(iOS 切后台把进程挂起 / 杀掉)
##   ⇒ 本机还记着第 440 版 ⇒ 之后每一推都被判「冲突」, 而冲突的另一边**就是它自己上一推**。
##   冲突 = 停推、等玩家去设置页二选一, 没有别的提示 ⇒ 云端从此停在 10-17。
##
## ★做法: 每推之前把「期望版本号 + 这一推的内容指纹」落盘(进程被杀也记得);
##   冲突且云端恰好是「期望 + 1」⇒ 拉云端那份比指纹:
##     · 是自己发过的 ⇒ 认下这个版本号、标脏, 下一拍把现在的进度接着推上去
##     · 不是(另一台设备)⇒ 真冲突, 照旧停推等玩家二选一
##     · 没拉到 ⇒ 不下结论(不进冲突、不认版本号), 下一拍再推再查
## ★同一个期望版本号可能连发好几推都没回包(第一推没到、第二推到了)⇒ 记一串指纹, 不是一个。
## ★服务端存的就是请求里的 p_payload 原样(schema.sql `set payload = p_payload`)⇒ 指纹能比。

const UNACKED_PATH := "user://cloud_push_unacked.json"
const UNACKED_KEEP := 32
## ★运行时 load 而不 preload: supabase.gd 也 preload 本文件, 互相 preload 会成环
const SB_PATH := "res://scripts/net/supabase.gd"


static func _sb():
	return load(SB_PATH)


## 内容指纹(按线上形态归一): 本机发出去的那份与从云端拉回来的那份要能比 ——
##   两边都过一遍「序列化 → 解析」, 整数与小数成同一种形态; 键序由 payload_hash 排好。
static func wire_hash(p: Dictionary) -> String:
	var back = JSON.parse_string(JSON.stringify(p))
	return _sb().payload_hash(back if back is Dictionary else {})


static func read() -> Dictionary:
	if not FileAccess.file_exists(UNACKED_PATH):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(UNACKED_PATH))
	return j if j is Dictionary else {}


## 发之前调: 记下这一推(同账号、同期望版本号的指纹累加; 换了就重记)。
static func note(account_id: String, expected_rev: int, wh: String) -> void:
	var u := read()
	var hs: Array = []
	if str(u.get("account", "")) == account_id and int(u.get("rev", -1)) == expected_rev \
			and u.get("hashes", null) is Array:
		hs = u["hashes"]
	if not hs.has(wh):
		hs.append(wh)
	while hs.size() > UNACKED_KEEP:
		hs.remove_at(0)
	var f := FileAccess.open(UNACKED_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"account": account_id, "rev": expected_rev, "hashes": hs}))
		f.close()


static func clear() -> void:
	if FileAccess.file_exists(UNACKED_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UNACKED_PATH))


## 推送回包是「冲突」时调。返回 true = 已经去拉云端那份来比了(结果出来之前 inflight 闸挡着, 不会再推)。
static func maybe_check(gs, conflict_rev: int) -> bool:
	if gs == null:
		return false
	var u := read()
	if str(u.get("account", "")) != str(gs.account_id) or conflict_rev != int(u.get("rev", -2)) + 1:
		return false
	var SB = _sb()
	var n = SB._spawn()
	if n == null:
		return false
	if not SB.enabled():
		n._bye()
		return false
	SB._save_inflight = true
	var url: String = SB.base_url().rstrip("/") + "/rest/v1/saves?select=payload,save_rev&account_id=eq." \
		+ str(gs.account_id).uri_encode()
	n._http("GET", url, "", func(res) -> void:
		apply_check(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")), conflict_rev)
		n._bye())
	return true


## 拉回来之后下结论。返回 healed / conflict / net。
static func apply_check(ok: bool, code: int, body: String, conflict_rev: int) -> String:
	var SB = _sb()
	SB._save_inflight = false
	var r: Dictionary = SB.pull_result(ok, code, body)
	var gs = SB._gs()
	if str(r["kind"]) == "net":
		print("[SupabaseNet] 查冲突时没拉到云存档(code=%d), 下一拍再试" % code)
		return "net"
	var hs = read().get("hashes", [])
	if gs != null and str(r["kind"]) == "found" and int(r["rev"]) == conflict_rev \
			and hs is Array and (hs as Array).has(wire_hash(r["payload"])):
		gs.cloud_rev = conflict_rev
		clear()
		SB._last_pushed_hash = ""
		SB._save_dirty = true
		gs.save()
		print("[SupabaseNet] 云端第 %d 版就是本机上一推(回包丢了) ⇒ 认下版本号, 接着推" % conflict_rev)
		return "healed"
	SB._save_conflict_rev = conflict_rev
	print("[SupabaseNet] 存档冲突: 云端是第 %d 版, 本机上次对上的是第 %d 版(不是本机发的)" % [
		conflict_rev, int(gs.cloud_rev) if gs != null else -1])
	return "conflict"
