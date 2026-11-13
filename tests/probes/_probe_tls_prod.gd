extends Node
## _probe_tls_prod —— 用户 11-12 桌面正式包「无法连接服务器」: 用 Godot 自己的 HTTPRequest(mbedTLS + 引擎自带根证书)连正式服几个地址, 打结果码。
##   不带密钥 ⇒ 不建账号、不写库, 只看 TLS / HTTP 通不通。探针, 不进门禁。
const URLS := ["https://cjefldecsfpnclhfwriw.supabase.co/rest/v1/", "https://cjefldecsfpnclhfwriw.supabase.co/auth/v1/health", "https://stream.turtlearena.xyz/"]

func _ready() -> void:
	for u in URLS:
		var h := HTTPRequest.new()
		h.timeout = 15.0
		add_child(h)
		var err := h.request(u)
		var r: Array = await h.request_completed
		print("[TLS] %s -> request()=%d result=%d http=%d" % [u, err, int(r[0]), int(r[1])])
		h.queue_free()
	get_tree().quit(0)
