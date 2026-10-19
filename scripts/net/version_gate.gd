class_name VersionGate
extends RefCounted
## 强制最低版本的纯判据(2026-10-19 从 supabase.gd 拆出: 那个文件超了 3000 行上帝对象上限)。
##
## ─────────────────────────────────────────────────────────────
## 强制最低版本(2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §4)
##   用户 10-19「需要强制最低版本」。服务端 `service_status.min_client_version`(schema.sql §5)。
##   ★原来(E15, 10-04)只在主菜单飘一句「发现新版本」、不拦人; 现在低于它 ⇒ 整屏挡住(`version_wall.gd`)。
##   ★判据只有 `update_required()` 一处, 三道闸都读它: 整屏挡墙(version_wall.gd) / 主菜单开局闸 / 出口 `_http` 拦写。
##   ★服务端另一道: 请求头 `X-Client-Version` → pre-request 钩子拒旧包(migrations/20261019_min_version_gate.sql)。
##   ★★离线不判旧: 只有这一进程真的问到了服务端才挡; 问不到 ⇒ 不挡。
### ─────────────────────────────────────────────────────────────
## 纯函数: 版本串 a 是否**严格低于** b。按「.」分段逐段比**整数**(0.19.10 > 0.19.9),
##   段数不同时缺的段当 0(0.19 == 0.19.0)。任何一段不是纯数字 ⇒ 判 false(看不懂就不挡, 不吓人)。
static func version_less(a: String, b: String) -> bool:
	var pa := a.strip_edges().split(".")
	var pb := b.strip_edges().split(".")
	for p in pa + pb:
		if not (p as String).is_valid_int() or int(p) < 0:
			return false
	for i in range(maxi(pa.size(), pb.size())):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x < y
	return false


## 纯函数: 这个回包是不是服务端在说「客户端太旧」。
##   426 = pre-request 钩子(`PT426`); 短回包里的 `"update_required"` = 各 RPC 自己的拒收(finals_report 等)。
##   ★只看短回包: 录像 / 快照正文里恰好有这串字的话不能误判。
static func is_update_required_response(res: Dictionary) -> bool:
	var code := int(res.get("code", 0))
	if code == 426:
		return true
	if code <= 0:
		return false
	var body := str(res.get("body", ""))
	return body.length() <= 512 and body.find("\"update_required\"") >= 0
