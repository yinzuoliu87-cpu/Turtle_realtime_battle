#!/usr/bin/env bash
# 大陆中转 · 白名单实测（README「检查」）。只发只读请求；不打印任何请求头的值。
#
#   BASE=http://127.0.0.1:8082 SB_ANON=<公开 key> bash relay_check.sh              # 服务器上（本机自检口）
#   BASE=https://stream.turtlearena.xyz:8443 SB_ANON=<公开 key> bash relay_check.sh # 任何地方（第一阶段公网入口）
#   BASE=https://cn.turtlearena.xyz SB_ANON=<公开 key> bash relay_check.sh          # DNS 加好之后
#
# SB_ANON = project.godot 的 turtle/supabase_anon_key（publishable key，公开值）。
# 全部通过打印 RELAY CHECK ALL PASS，退出码 0；任何一条不对退出码 1。
# ★默认绕开本机代理（memory fb-local-proxy-corrupts-post-body）：curl --noproxy '*'。
set -u
BASE="${BASE:?BASE 没给}"
BASE="${BASE%/}"
ANON="${SB_ANON:?SB_ANON 没给}"
VER="${CLIENT_VERSION:-99.0.0}"
UUID0="00000000-0000-4000-8000-000000000000"
fail=0
n=0

code() {  # code <额外 curl 参数...> <url>
	curl --noproxy '*' -s -o /dev/null -w '%{http_code}' --max-time 25 "$@"
}

check() {  # check <名字> <期望码> <实际码>
	n=$((n + 1))
	if [ "$2" = "$3" ]; then
		echo "  [PASS] $1 = $3"
	else
		echo "  [FAIL] $1 = $3（期望 $2）"
		fail=$((fail + 1))
	fi
}

H_KEY=(-H "apikey: $ANON" -H "Authorization: Bearer $ANON")

echo "== 中转 $BASE"
check "healthz" 200 "$(code "$BASE/healthz")"

# ── 白名单内：真到了 Supabase / stream（回的码是上游的口径，不是中转自己编的）
check "REST service_status（只读，公开 key）" 200 "$(code "${H_KEY[@]}" "$BASE/rest/v1/service_status?select=*&limit=1")"
check "REST 不带 apikey ⇒ Supabase 自己的 401" 401 "$(code "$BASE/rest/v1/service_status?select=*&limit=1")"
check "REST 正文与直连逐字相同" same "$( [ "$(curl --noproxy '*' -s --max-time 25 "${H_KEY[@]}" "$BASE/rest/v1/service_status?select=*&limit=1")" = "$(curl --noproxy '*' -s --max-time 25 "${H_KEY[@]}" "https://cjefldecsfpnclhfwriw.supabase.co/rest/v1/service_status?select=*&limit=1")" ] && echo same || echo differ)"
check "Auth settings（只读）" 200 "$(code -H "apikey: $ANON" "$BASE/auth/v1/settings")"
check "直播 不带版本头 ⇒ stream 版本闸 426" 426 "$(code "$BASE/streams/$UUID0/end.json")"
check "直播 带版本头、没有这一局 ⇒ 404" 404 "$(code -H "X-Client-Version: $VER" "$BASE/streams/$UUID0/end.json")"

# ── 白名单外：一律 404（中转自己回，没去上游）
for p in / /storage/v1/object/list/x /functions/v1/x /realtime/v1/websocket /graphql/v1 /pg/meta /rest/v2/x /auth/v2/x /streamsx/y /rest /auth/v1 ; do
	check "白名单外 $p" 404 "$(code "${H_KEY[@]}" "$BASE$p")"
done
check "路径穿越 /rest/v1/../storage/v1/x" 404 "$(code --path-as-is "${H_KEY[@]}" "$BASE/rest/v1/../storage/v1/x")"
check "路径穿越（编码）/rest/v1/%2e%2e/storage/v1/x" 404 "$(code --path-as-is "${H_KEY[@]}" "$BASE/rest/v1/%2e%2e/storage/v1/x")"
check "路径穿越 /streams/../rest/v1/x" 404 "$(code --path-as-is "$BASE/streams/../rest/v1/x")"

# ── 方法白名单
check "TRACE ⇒ 405" 405 "$(code -X TRACE "$BASE/rest/v1/service_status")"
check "PROPFIND ⇒ 405" 405 "$(code -X PROPFIND "$BASE/rest/v1/service_status")"

# ── 请求体上限（10 MB）：11 MB 的正文 ⇒ 413，且没打到上游
big=$(mktemp)
head -c 11534336 /dev/zero > "$big"
check "正文 11 MB ⇒ 413" 413 "$(code -X POST -H 'Content-Type: application/octet-stream' --data-binary @"$big" "${H_KEY[@]}" "$BASE/rest/v1/rpc/no_such_fn")"
rm -f "$big"

echo "== $n 条，失败 $fail"
if [ "$fail" -eq 0 ]; then
	echo "RELAY CHECK ALL PASS"
	exit 0
fi
exit 1
