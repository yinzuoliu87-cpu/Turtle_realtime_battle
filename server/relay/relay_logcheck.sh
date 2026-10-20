#!/usr/bin/env bash
# 用法(服务器上, root): SB_ANON=<公开 key> bash relay_logcheck.sh   —— 两行输出: 正式实例 journal 含AUTH标记=0; 对照实例 含UA标记>0 且 含AUTH标记=0
# 中转日志不记 Authorization: ①正式实例(无访问日志) journal 里 0 条 ②对照: 临时实例开访问日志, UA 标记在、Authorization 标记不在
set -u
M=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
AUTH="RELAYAUTHMARK$M"; UA="RELAYUAMARK$M"
T0=$(date '+%Y-%m-%d %H:%M:%S')
send() {  # send <base>
  for p in "/rest/v1/service_status?select=*&limit=1" "/auth/v1/settings" "/storage/v1/x" "/streams/00000000-0000-4000-8000-000000000000/end.json"; do
    curl -s -o /dev/null -H "apikey: $SB_ANON" -H "Authorization: Bearer $AUTH" -A "$UA" "$1$p"
  done
  curl -s -o /dev/null -X TRACE -H "Authorization: Bearer $AUTH" -A "$UA" "$1/rest/v1/x"
  head -c 11534336 /dev/zero | curl -s -o /dev/null -X POST --data-binary @- -H "Authorization: Bearer $AUTH" -A "$UA" "$1/rest/v1/rpc/x"
}
send http://127.0.0.1:8082
sleep 1
J=$(journalctl -u caddy --since "$T0" --no-pager -o cat)
echo "正式实例 journal 新增行数=$(printf '%s' "$J" | grep -c .)  含AUTH标记=$(printf '%s' "$J" | grep -c "$AUTH")  含UA标记=$(printf '%s' "$J" | grep -c "$UA")"
# 对照实例
D=$(mktemp -d)
awk '/^\(relay\) \{/{f=1} f{print} f&&/^\}/{exit}' /etc/caddy/relay.caddy > "$D/snip.caddy"
cat > "$D/Caddyfile" <<C2
{
	admin off
	auto_https off
}
import $D/snip.caddy
http://127.0.0.1:18090 {
	bind 127.0.0.1
	log {
		output file $D/access.log
	}
	import relay
}
C2
caddy run --config "$D/Caddyfile" --adapter caddyfile >"$D/run.out" 2>&1 &
P=$!
sleep 2
send http://127.0.0.1:18090
sleep 1
kill $P; wait $P 2>/dev/null
L="$D/access.log"
echo "对照实例 访问日志行数=$(grep -c . "$L")  含UA标记=$(grep -c "$UA" "$L")  含AUTH标记=$(grep -c "$AUTH" "$L")  含REDACTED=$(grep -c REDACTED "$L")"
rm -rf "$D"
