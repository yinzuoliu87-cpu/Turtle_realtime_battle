class_name WebPlayerCore
extends RefCounted
## 网页录像播放器 · 判据与取数(纯函数; 页面在 scripts/scenes/WebPlayerScene.gd)。
## 方案书 docs/plans/20261105c-主站对接偷袭.md §4.7 · 约定 docs/specs/主站对接约定.md §4.4 · 部署 server/player/README.md。
##
## 地址(都在播放器自己那个域名下, 同源 ⇒ 不用跨域头; 服务端 Caddy 片段 server/player/player.caddy):
##   <origin>/player/?match=<对局号>             入口页(server/player/index.html): 先读 end.json 里的版本, 跳到下面那一个
##   <origin>/player/<版本>/?match=<对局号>      这一版的播放器(导出预设 WebPlayer)
##   <origin>/player/streams/<对局号>/end.json   录完的元数据(版本 client_version、块数 chunks、全场步数 last_step、名字 names …)
##   <origin>/player/streams/<对局号>/<6 位>.bin 状态流块(与 stream.turtlearena.xyz/streams 同一批文件, 不过版本闸: 版本由目录选)
##   <origin>/player/expired/<对局号>            过了保留期被清掉的局留下的记号(server/stream/stream_ops.py purge 写)
## 判定顺序(与入口页同一套, 播放器自己再判一次 —— 有人直接打开 /player/<版本>/ 也得对):
##   手机浏览器 ⇒「请在小游戏内观看」; 对局号不像样 ⇒「未找到该对局的录像」;
##   end.json 200 ⇒ 版本对 ⇒ 播; 版本不对 ⇒ 网页上回入口页重新选目录(带 hop=1, 第二次还不对就说版本不一致);
##   end.json 404 ⇒ expired 记号 200 ⇒「录像已过期」, 否则「未找到该对局的录像」; 连不上 / 5xx ⇒「无法连接服务器。请检查网络连接后重试。」+ 重试。

const F := preload("res://scripts/systems/stream/stream_format.gd")

const DEFAULT_ORIGIN := "https://arena.turtlearena.xyz"
const STREAMS_PATH := "/player/streams"
const EXPIRED_PATH := "/player/expired"
const ENTRY_PATH := "/player/"
## 桌面调试 / 门禁的注入(网页上一律从浏览器读): 对局号、站点、浏览器 UA、触点数。
const ENV_MATCH := "WEBPLAYER_MATCH"
const ENV_ORIGIN := "WEBPLAYER_ORIGIN"
const ENV_UA := "WEBPLAYER_UA"
const ENV_TOUCH := "WEBPLAYER_TOUCH"

## 屏上的字(书面、短; 不出现主站与金额)。前两句是约定 §4.4 的原文。
const TXT_MOBILE := "请在小游戏内观看"
const TXT_EXPIRED := "录像已过期"
const TXT_NOT_FOUND := "未找到该对局的录像"
## 网络失败全游戏只有一种说法(verify_ui_copy 第 7 条)
const TXT_OFFLINE := "无法连接服务器。请检查网络连接后重试。"
const TXT_VERSION := "录像版本与播放器版本不一致"
const TXT_LOADING := "正在载入录像"
const TXT_ENDED := "播放结束"
const BTN_RETRY := "重试"
const BTN_REPLAY := "重新播放"

## 手机 / 平板浏览器的 UA 关键字(iPadOS 13+ 的 Safari 报桌面 Mac UA, 另按触点数认, 见 `is_mobile`)。
const MOBILE_RE := "(?i)(android|iphone|ipad|ipod|mobile|harmonyos|windows phone|iemobile|opera mini|blackberry|kindle|silk)"
const UUID_RE := "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

## 上一次进场播的那一局(看完 / 退出回到播放器页 ⇒ 显示「播放结束」+「重新播放」, 不自动再放一遍)。
static var last_played := ""


## 手机打开 ⇒ 不播(约定 §4.4: 手机走 App)。`touch_points` = navigator.maxTouchPoints。
static func is_mobile(ua: String, touch_points: int) -> bool:
	var re := RegEx.create_from_string(MOBILE_RE)
	if re.search(ua) != null:
		return true
	return ua.contains("Macintosh") and touch_points > 1


## 对局号 → 规范形(小写 uuid); 不像样 ⇒ ""。
static func norm_match_id(s: String) -> String:
	var t := s.strip_edges().to_lower()
	var re := RegEx.create_from_string(UUID_RE)
	return t if re.search(t) != null else ""


## 网址查询串(`?a=1&match=…`)里取一项; 没有 ⇒ ""。
static func query_param(search: String, key: String) -> String:
	var q := search.strip_edges()
	if q.begins_with("?"):
		q = q.substr(1)
	for part in q.split("&", false):
		var i := part.find("=")
		var k := part if i < 0 else part.substr(0, i)
		if k.uri_decode() == key:
			return "" if i < 0 else part.substr(i + 1).uri_decode()
	return ""


static func end_url(origin: String, id: String) -> String:
	return "%s%s/%s/end.json" % [origin.rstrip("/"), STREAMS_PATH, id]


static func expired_url(origin: String, id: String) -> String:
	return "%s%s/%s" % [origin.rstrip("/"), EXPIRED_PATH, id]


static func streams_base(origin: String) -> String:
	return origin.rstrip("/") + STREAMS_PATH


## 版本不对时回入口页的地址(入口页按 end.json 重新选目录)。
static func entry_url(origin: String, id: String) -> String:
	return "%s%s?match=%s&hop=1" % [origin.rstrip("/"), ENTRY_PATH, id]


## end.json 能不能由这一版播放器播: "" = 能; "version" = 版本 / 格式不是这一版; "bad" = 不像一份录完的元数据。
static func check_end(meta: Dictionary, my_version: String) -> String:
	if meta.is_empty() or int(meta.get("chunks", -1)) <= 0:
		return "bad"
	if str(meta.get("client_version", "")) != my_version or int(meta.get("format", -1)) != F.VERSION:
		return "version"
	return ""


## 第 0 块(keyframe)里的地图种子(全局 `seed`; 战斗场建图前就要知道, 见 StreamPlayer `seed_mismatch`)。读不到 ⇒ -1。
static func seed_of_chunk(data: PackedByteArray) -> int:
	var d := F.parse_chunk(data, {})
	if not bool(d.get("ok", false)):
		return -1
	for st in (d["list"] as Array):
		for op in (st[2] as Array):
			if int(op[0]) == F.OP_GLOBAL and (op[1] as Dictionary).has("seed"):
				return int((op[1] as Dictionary)["seed"])
	return -1
