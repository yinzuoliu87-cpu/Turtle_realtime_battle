#!/bin/sh
# 内测服裁判轮询器高峰停起（turtle-referee-beta-peak.service 调；放到 /opt/turtle-beta/referee/）。
# 正式服赛程高峰 = 周六全天 + 周日 17:30~24:00 UTC（周日小组赛 18:00 起、冠军杯赛 20:00 起）。
# 按真实 UTC 判，不看内测服的假时间。/etc/turtle-referee/beta-off 存在 ⇒ 一直停。
dow=$(date -u +%u)
hm=$(date -u +%H%M)
peak=0
[ "$dow" = "6" ] && peak=1
[ "$dow" = "7" ] && [ "$hm" -ge 1730 ] && peak=1
if [ "$peak" = "1" ] || [ -e /etc/turtle-referee/beta-off ]; then
  if systemctl is-active --quiet turtle-referee-beta; then
    systemctl stop turtle-referee-beta && echo "beta poller stopped (peak=$peak dow=$dow hm=$hm)"
  fi
else
  if ! systemctl is-active --quiet turtle-referee-beta; then
    systemctl start turtle-referee-beta && echo "beta poller started (dow=$dow hm=$hm)"
  fi
fi
exit 0
