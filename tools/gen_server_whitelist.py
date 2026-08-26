# -*- coding: utf-8 -*-
"""从产品自己的属性表生成服务端白名单 —— server/cloudbase/whitelist.json。

★为什么要生成而不是手写: 龟 28 只、装备 59+ 件, 手写一份到服务端 = 抄一次永远落后一次
  (memory: 手抄的副本必然落后)。新增一只龟, 手写的白名单会把**合法快照判成伪造**,
  表现是"新龟的玩家永远传不上去", 而且是静默的。

跑法: python tools/gen_server_whitelist.py
对账: python tools/server_rule_sync.py (进 run-tests 门禁)
"""
import io
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

OUT = 'server/cloudbase/whitelist.json'
TURTLE = 'scripts/gamedata/turtle_stats.gd'
EQUIP = 'scripts/gamedata/equip_stats.gd'


def top_level_keys(path, const_name):
    """取 `const <NAME> := { ... }` 里【顶层】的字符串键。

    ★不能用"找所有 "xxx":" 的正则": 嵌套字典里的字段名(hp/atk/…)会一起被捞进来。
      判据落在**缩进深度**: 顶层键恰好是一层 tab。
    """
    s = io.open(path, encoding='utf-8').read()
    m = re.search(r'^const %s\s*:?=\s*\{' % const_name, s, re.M)
    if not m:
        raise SystemExit('在 %s 里找不到 const %s' % (path, const_name))
    body = s[m.end():]
    keys, depth = [], 1
    for ln in body.split(chr(10)):
        depth += ln.count('{') - ln.count('}')
        if depth <= 0:
            break
        k = re.match(r'^\t"([^"]+)"\s*:', ln)
        if k:
            keys.append(k.group(1))
    return keys


def main():
    turtles = top_level_keys(TURTLE, 'STATS')
    equips = top_level_keys(EQUIP, 'STATS')
    # ★分母: 空名单会让服务端把【所有】快照判成伪造 —— 那比不校验还糟, 必须硬失败。
    if len(turtles) < 20 or len(equips) < 40:
        raise SystemExit('白名单过小(龟 %d / 装备 %d) —— 解析八成错了, 拒绝生成'
                         % (len(turtles), len(equips)))
    ## 可指定输出路径 —— 审计器拿它写临时文件再比对, 这样【审计器不改工作区】
    ##   (只读审计器可反复跑是本项目的约定; 一个会顺手改文件的"审计器"会把
    ##    "过期了"这条问题在报出来的同时抹掉, 下一次跑就绿了 = 问题看不见了)。
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    d = os.path.dirname(out)
    if d:
        os.makedirs(d, exist_ok=True)
    io.open(out, 'w', encoding='utf-8', newline=chr(10)).write(
        json.dumps({'TURTLE_IDS': sorted(turtles), 'EQUIP_IDS': sorted(equips)},
                   ensure_ascii=False, indent=1) + chr(10))
    print('已生成 %s —— 龟 %d 只 / 装备 %d 件' % (out, len(turtles), len(equips)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
