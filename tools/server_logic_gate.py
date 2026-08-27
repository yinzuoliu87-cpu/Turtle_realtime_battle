# -*- coding: utf-8 -*-
"""服务端云函数的【逻辑】门禁 —— 起本地宿主跑真 index.js, 再用 backend_smoke 验一遍。

方案书 docs/plans/20260820-阵容上传后端.md 的 V3-服务端 原本标着「代码写好了没部署所以没验」。
但"没部署"挡住的只是**部署**, 挡不住**逻辑**: 云函数无非 `exports.main(event) → {statusCode, body}`,
把 SDK 换成内存库就能原样跑(server/local_host.js, 它**不复制任何 index.js 的逻辑**)。

⇒ 六类伪造快照的拒绝规则、V2 的存取往返、同 id 去重, 全部可以在本地逐条验完并进门禁。
   **仍然没验的只剩"云上真部署"**(要腾讯云账号+实名) —— 方案书里如实标着。

★没有 node 时会 SKIP, 但**大声打出来**并计数 —— 静默跳过等于把门禁掏空。
  (CI 的 ubuntu runner 自带 node, 所以线上不会走这条路。)
"""
import os
import shutil
import socket
import subprocess
import sys
import time

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

SMOKE = 'tools/backend_smoke.py'

## ★★两个宿主【都要跑同一套冒烟】。
##   腾讯云版与 Deno 版共用 `server/rules.mjs` 的校验规则, 但**存储层各写各的**
##   (文档库 vs KV) —— 而"同 id 去重""桶封顶挤最旧的"这些语义正是存储层实现的,
##   只验一个宿主就守不住另一个。两边跑同一套 13 条, 表现必须一样。
HOSTS = [
    {
        'name': '腾讯云版(local_host + 真 index.js)',
        'need': ['server/local_host.js', 'server/cloudbase/index.js'],
        'cmd': lambda port: ['node', 'server/local_host.js', str(port)],
        'bin': 'node',
    },
    {
        'name': 'Deno 版(main.ts + Deno KV)',
        'need': ['server/deno/main.ts'],
        'cmd': lambda port: ['deno', 'run', '-A', '--unstable-kv', 'server/deno/main.ts', str(port)],
        'bin': 'deno',
    },
]


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def have(binname):
    """找到可执行文件的**真实路径**并取版本号。

    ★不能直接 `subprocess.run(['deno', ...])`: Windows 上 npm 装的是 `deno.cmd`(不是 .exe),
      而 subprocess 不走 PATHEXT ⇒ 明明装好了却报"没有 deno", 于是那个宿主被静默跳过。
      `shutil.which` 会按 PATHEXT 解析, 拿到真实路径后再调。
    """
    exe = shutil.which(binname)
    if not exe:
        return False, '', None
    try:
        r = subprocess.run([exe, '--version'], capture_output=True, text=True,
                           encoding='utf-8', errors='replace', timeout=60)
        if r.returncode != 0:
            return False, '', None
        return True, (r.stdout or '').strip().split(chr(10))[0], exe
    except Exception:
        return False, '', None


def run_one(host):
    """起一个宿主, 跑冒烟, 返回 (跑没跑, 出错列表)。"""
    miss = [p for p in host['need'] if not os.path.exists(p)]
    if miss:
        return True, ['%s: 缺文件 %s' % (host['name'], miss)]
    ok_bin, ver, exe = have(host['bin'])
    if not ok_bin:
        ## ★不是"通过", 是"没跑"。打得足够响, 免得被当成绿灯。
        print('  [SKIP] 本机没有 %s ⇒ 【%s 这一轮没有被检查】' % (host['bin'], host['name']))
        return False, []

    port = free_port()
    cmd = host['cmd'](port)
    cmd[0] = exe          # 用解析出来的真实路径
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True,
                            encoding='utf-8', errors='replace')
    try:
        up = False
        for _ in range(80):
            try:
                sk = socket.create_connection(('127.0.0.1', port), timeout=0.5)
                sk.close()
                up = True
                break
            except Exception:
                time.sleep(0.25)
        if not up:
            out = proc.stdout.read() if proc.stdout else ''
            return True, ['%s 起不来(%s, 端口 %d): %s' % (host['name'], ver, port, (out or '')[:300])]

        r = subprocess.run([sys.executable, SMOKE, 'http://127.0.0.1:%d' % port],
                           capture_output=True, text=True, encoding='utf-8', errors='replace')
        txt = (r.stdout or '') + (r.stderr or '')
        n_pass = txt.count('[PASS]')
        n_fail = txt.count('[FAIL]')
        print('  [分母] %s · %s · 检查 %d 条(PASS %d / FAIL %d)'
              % (host['name'], ver, n_pass + n_fail, n_pass, n_fail))
        if n_pass + n_fail < 12:
            return True, ['%s 只跑到 %d 条(<12) —— 空检查不是通过%s%s'
                          % (host['name'], n_pass + n_fail, chr(10), txt[-500:])]
        if r.returncode != 0 or n_fail > 0:
            bad = [ln.strip() for ln in txt.split(chr(10)) if '[FAIL]' in ln]
            return True, ['%s: %s' % (host['name'], b) for b in bad]
        return True, []
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=10)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass


def main():
    if not os.path.exists(SMOKE):
        print('  [FAIL] 缺 %s' % SMOKE)
        return 1

    fails = []
    ran = 0
    for host in HOSTS:
        did, errs = run_one(host)
        ran += 1 if did else 0
        fails += errs

    ## ★分母: 一个宿主都没跑成 = 这份门禁本轮什么都没验。
    if ran == 0:
        print('  [SKIP] 两个宿主都没跑(缺 node 与 deno) —— 服务端逻辑本轮未被检查')
        print('')
        print('ALL OK — 服务端逻辑门禁(本轮全部 SKIP)')
        return 0
    print('  [分母] 实际跑了 %d/%d 个宿主' % (ran, len(HOSTS)))

    for x in fails:
        print('  [FAIL] ' + x)
    if fails:
        print('')
        print('FAILED: %d 处 —— 服务端逻辑对不上' % len(fails))
        return 1
    print('')
    if ran < len(HOSTS):
        print('ALL OK — 服务端逻辑达标(**只跑了 %d/%d 个宿主**·V2 往返/V3 六类伪造/去重)'
              % (ran, len(HOSTS)))
    else:
        print('ALL OK — 服务端逻辑达标(%d 个宿主各 13 条·V2 往返/V3 六类伪造/去重)' % ran)
    return 0


if __name__ == '__main__':
    sys.exit(main())
