#!/bin/sh
# 内测服裁判轮询器高峰停起（turtle-referee-beta-peak.service 调；放到 /opt/turtle-beta/referee/）。
# 正式服赛程高峰 = 周六、周日全天 UTC（2026-10-26 起闯关赛打到周日 17:30，紧接着周日小组赛 18:00、冠军杯赛 20:00）。
# 按真实 UTC 判，不看内测服的假时间。/etc/turtle-referee/beta-off 存在 ⇒ 一直停。
dow=$(date -u +%u)
hm=$(date -u +%H%M)
peak=0
[ "$dow" = "6" ] && peak=1
[ "$dow" = "7" ] && peak=1
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
