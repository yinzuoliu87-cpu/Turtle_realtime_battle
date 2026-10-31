#!/bin/sh
# 内测服裁判轮询器高峰停起（turtle-referee-beta-peak.service 调；放到 /opt/turtle-beta/referee/）。
# 正式服赛程高峰 = 周六、周日全天 UTC（2026-10-26 起闯关赛打到周日 17:30，紧接着周日小组赛 18:00、冠军杯赛 20:00）。
# 按真实 UTC 判，不看内测服的假时间。/etc/turtle-referee/beta-off 存在 ⇒ 一直停。
#
# 两种用法：
#   不带参数     停起（timer 调，要 root）
#   --should-run 只判断、不动手：内测服裁判此刻该在岗 ⇒ 退出 0；被故意停着（高峰 / beta-off）或刚起来不到 3 分钟 ⇒ 退出 1
#                （turtle-referee-beta-health 的 ExecCondition 用它。2026-10-31：周末被这里停掉之后，健康检查照样每 5 分钟
#                  报一次「心跳: 没有裁判在线」= 全是误报；退出 1 让 systemd 把这一次记成「条件不满足、跳过」而不是失败）
dow=$(date -u +%u)
hm=$(date -u +%H%M)
peak=0
[ "$dow" = "6" ] && peak=1
[ "$dow" = "7" ] && peak=1
off=0
[ "$peak" = "1" ] && off=1
[ -e /etc/turtle-referee/beta-off ] && off=1
if [ "$1" = "--should-run" ]; then
  [ "$off" = "1" ] && exit 1
  # 该在岗却没起来 ⇒ 让健康检查照常跑、照常报（那是真问题）
  systemctl is-active --quiet turtle-referee-beta || exit 0
  # 刚由上面那段起来（周一 00:00 后的头一轮）⇒ 心跳还没报上来，等 3 分钟再查
  since=$(systemctl show -p ActiveEnterTimestamp --value turtle-referee-beta 2>/dev/null)
  t0=$(date -u -d "$since" +%s 2>/dev/null || echo 0)
  [ $(( $(date -u +%s) - t0 )) -lt 180 ] && exit 1
  exit 0
fi
if [ "$off" = "1" ]; then
  if systemctl is-active --quiet turtle-referee-beta; then
    systemctl stop turtle-referee-beta && echo "beta poller stopped (peak=$peak dow=$dow hm=$hm)"
  fi
else
  if ! systemctl is-active --quiet turtle-referee-beta; then
    systemctl start turtle-referee-beta && echo "beta poller started (dow=$dow hm=$hm)"
  fi
fi
exit 0
