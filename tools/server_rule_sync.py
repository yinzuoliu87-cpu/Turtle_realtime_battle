# -*- coding: utf-8 -*-
"""服务端规则 ↔ 客户端事实源 逐条对账 (2026-08-26)。

`server/cloudbase/index.js` 是【手抄】客户端规则的一份副本(它跑在 Node 上, 读不了 .gd)。
本项目对这种副本有明确教训 —— **手抄的副本必然落后**, 而且落后时的表现是静默的:
服务端会把合法快照判成伪造, 玩家侧只看到"我的阵容传不上去", 谁都不会去看 JS。

⇒ 把对账焊成门禁。四个常量 + 两份白名单, 对不上直接红。

★这份门禁守的是【一致性】, 不是【服务端行为】。服务端还没部署过
  (要腾讯云账号 + 实名, 用户 2026-08-25「先不管」) —— 方案书 V2/V3 的服务端半边
  仍然标着「未验」, 本文件不能被当成"服务端做完了"。

跑法: python tools/server_rule_sync.py
"""
import io
import json
import os
import re
import subprocess
import tempfile
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

## ★常量已从 index.js 移到【两个宿主共用的】rules.mjs(2026-08-27 加 Deno 版时抽的)。
## 对账对的是这一份 ⇒ 两个服务端不可能各漂各的。
JS = 'server/rules.mjs'
WL = 'server/cloudbase/whitelist.json'

# JS 常量名 → (GDScript 文件, 常量名)
PAIRS = {
    'SCHEMA_VER':     ('scripts/net/backend.gd', 'SCHEMA_VER'),
    'BUCKET_CAP':     ('scripts/net/backend.gd', 'BUCKET_CAP'),
    'MAX_LEVEL':      ('scripts/gamedata/phase2_config.gd', 'MAX_LEVEL'),
    'UNIT_EQUIP_CAP': ('scripts/gamedata/phase2_config.gd', 'UNIT_EQUIP_CAP'),
}

fails = []
checked = 0


def gd_const(path, name):
    s = io.open(path, encoding='utf-8').read()
    m = re.search(r'^const %s\s*:?=\s*(-?\d+)' % re.escape(name), s, re.M)
    return int(m.group(1)) if m else None


def js_const(s, name):
    ## rules.mjs 里是 `export const X = N`
    m = re.search(r'^export const %s\s*=\s*(-?\d+)' % re.escape(name), s, re.M)
    return int(m.group(1)) if m else None


def main():
    global checked
    try:
        js = io.open(JS, encoding='utf-8').read()
    except OSError:
        print('  [FAIL] 读不到 %s' % JS)
        return 1

    for jsname, (gdpath, gdname) in sorted(PAIRS.items()):
        jv, gv = js_const(js, jsname), gd_const(gdpath, gdname)
        ## ★分母: 任一侧没解析出来 = 这条根本没在对账, 必须报 FAIL 而不是静默跳过
        ##   (N=0 是空检查不是通过)。
        if jv is None:
            fails.append('%s: 服务端 %s 解析不出来(改名了? 那对账已经形同虚设)' % (JS, jsname))
            continue
        if gv is None:
            fails.append('%s: 客户端 %s 解析不出来' % (gdpath, gdname))
            continue
        checked += 1
        if jv != gv:
            fails.append('常量漂了: 服务端 %s=%d ≠ 客户端 %s.%s=%d'
                         % (jsname, jv, gdpath, gdname, gv))

    ## 白名单: 重新生成一份, 与盘上那份逐字节比 —— 龟/装备增删后忘了重跑就会红。
    try:
        before = io.open(WL, encoding='utf-8').read()
    except OSError:
        before = None
    ## ★写到临时文件再比 —— 审计器不许改工作区(见 gen_server_whitelist 里的长注释)。
    ## ★encoding 必须显式给 utf-8: Windows 上 text=True 默认按 GBK 解码子进程输出,
    ##   中文一来就在读取线程里抛 UnicodeDecodeError —— 打出一大段 Traceback,
    ##   而门禁的致命报错正则会把它当成真崩溃。
    tmp = os.path.join(tempfile.gettempdir(), 'turtle_wl_check.json')
    r = subprocess.run([sys.executable, 'tools/gen_server_whitelist.py', tmp],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    if r.returncode != 0:
        fails.append('白名单生成器跑挂了: %s' % (r.stderr or r.stdout).strip()[:200])
    else:
        after = io.open(tmp, encoding='utf-8').read()
        checked += 1
        if before is None:
            fails.append('%s 原本不存在(现已生成, 请提交)' % WL)
        elif before != after:
            fails.append('%s 过期了 —— 龟/装备表改过但没重跑 gen_server_whitelist.py' % WL)
        d = json.loads(after)
        n_t, n_e = len(d['TURTLE_IDS']), len(d['EQUIP_IDS'])
        if n_t < 20 or n_e < 40:
            fails.append('白名单过小(龟 %d / 装备 %d)' % (n_t, n_e))
        print('  [分母] 白名单: 龟 %d 只 / 装备 %d 件' % (n_t, n_e))

    print('  [分母] 常量对账 %d 组(应为 %d 组 + 白名单 1 组)' % (checked, len(PAIRS)))
    if checked < len(PAIRS) + 1:
        fails.append('对账组数只有 %d(<%d) —— 有条目没被检查到' % (checked, len(PAIRS) + 1))

    for x in fails:
        print('  [FAIL] ' + x)
    if fails:
        print('')
        print('FAILED: %d 处' % len(fails))
        return 1
    print('')
    print('ALL OK — 服务端规则与客户端事实源一致')
    return 0


if __name__ == '__main__':
    sys.exit(main())
