extends Node
## _probe_client_error_e2e.gd —— 一次性探针(不进门禁): 真客户端 → 真生产库 走一遍报错上报。
## 用法: 全新 user:// + 真后端。会新建一个匿名号; 跑完由调用方按打印的 account_id 删号(级联删掉报错行)。

const SB := preload("res://scripts/net/supabase.gd")
const ER := preload("res://scripts/net/error_reporter.gd")


func _ready() -> void:
	await get_tree().process_frame
	SB.ensure_signed_in_async()
	for i in range(600):
		await get_tree().process_frame
		if SB.token_fresh(int(Time.get_unix_time_from_system())):
			break
	print("[E2E] token=%s account=%s" % [str(SB._token != ""), GameState.account_id])
	push_error("client-error-e2e-probe")
	var p0: int = SB.client_error_posts
	ER.instance().flush("_probe_client_error_e2e.tscn")
	for i in range(300):
		await get_tree().process_frame
	print("[E2E] posts=%d" % (SB.client_error_posts - p0))
	print("[E2E] ACCOUNT=%s" % GameState.account_id)
	get_tree().quit(0)
