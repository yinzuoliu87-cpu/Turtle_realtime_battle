#!/usr/bin/env bash
# tools/force_update_when_approved.sh <版本> [--finals] —— 苹果 Beta 审核一批就抬强制更新（2026-11-11, 取代每次手写的后台循环）。
#   每 10 分钟跑一次 prod_flags.py force-update <版本> --yes-prod（工具自己卡: 只升不降 / 苹果 APPROVED / referee_versions 已登记）;
#   抬成功 ⇒ 带 --finals 时再把 finals_version 换成 <版本>; 然后退出。
#   ★只在英国时间周一~周五写（周末不动正式服）: 到周六就退出（退出码 2）, 留到周一。
#   ★这是正式服写入: 每次起这个循环之前都要用户点头（--yes-prod 不是授权）。
#   日志: .out/force_update_<版本>.log（成功打 RESULT 一行）。会话断了循环会停 ⇒ 下次先看日志, 没 RESULT 就重起。
set -u
VER="${1:?用法: force_update_when_approved.sh <版本> [--finals]}"
FINALS=0
[ "${2:-}" = "--finals" ] && FINALS=1
cd "$(dirname "$0")/.." || exit 1
PY="${PY:-C:/Users/Louis/AppData/Local/Python/pythoncore-3.14-64/python.exe}"
while true; do
  DOW=$(TZ=Europe/London date +%u)
  NOW=$(TZ=Europe/London date '+%a %H:%M')
  if [ "$DOW" -ge 6 ]; then
    echo "$NOW 英国时间周末: 不写正式服, 退出(周一再起)"; exit 2
  fi
  if "$PY" tools/prod_flags.py force-update "$VER" --yes-prod; then
    echo "$NOW RESULT min_client_version = $VER"
    if [ "$FINALS" = 1 ]; then
      "$PY" tools/prod_flags.py set finals_version "$VER" --yes-prod && echo "$NOW RESULT finals_version = $VER"
    fi
    exit 0
  fi
  echo "$NOW 还不能抬(见上), 10 分钟后再看"
  sleep 600
done
