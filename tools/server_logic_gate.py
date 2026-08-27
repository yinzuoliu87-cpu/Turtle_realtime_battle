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
import socket
import subprocess
import sys
import time

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HOST = 'server/local_host.js'
SMOKE = 'tools/backend_smoke.py'


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def have_node():
    try:
        r = subprocess.run(['node', '--version'], capture_output=True, text=True,
                           encoding='utf-8', errors='replace', timeout=20)
        return r.returncode == 0, (r.stdout or '').strip()
    except Exception:
        return False, ''


def main():
    for p in (HOST, SMOKE):
        if not os.path.exists(p):
            print('  [FAIL] 缺 %s' % p)
            return 1

    ok_node, ver = have_node()
    if not ok_node:
        ## ★不是"通过", 是"没跑"。打得足够响, 免得被当成绿灯。
        print('  [SKIP] 本机没有 node —— 服务端逻辑【这一轮没有被检查】')
        print('  [SKIP] (装了 node 就会自动跑; CI 的 ubuntu runner 自带 node)')
        print('')
        print('ALL OK — 服务端逻辑门禁(本轮 SKIP: 无 node)')
        return 0

    port = free_port()
    proc = subprocess.Popen(['node', HOST, str(port)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding='utf-8', errors='replace')
    try:
        ## 等宿主起来 —— 轮询端口而不是 sleep 固定秒数(慢机器上 sleep 会不够)。
        up = False
        for _ in range(60):
            try:
                s = socket.create_connection(('127.0.0.1', port), timeout=0.5)
                s.close()
                up = True
                break
            except Exception:
                time.sleep(0.25)
        if not up:
            print('  [FAIL] 本地宿主起不来(node %s, 端口 %d)' % (ver, port))
            out = proc.stdout.read() if proc.stdout else ''
            print('        ' + (out or '')[:400])
            return 1

        r = subprocess.run([sys.executable, SMOKE, 'http://127.0.0.1:%d' % port],
                           capture_output=True, text=True, encoding='utf-8', errors='replace')
        txt = (r.stdout or '') + (r.stderr or '')
        n_pass = txt.count('[PASS]')
        n_fail = txt.count('[FAIL]')
        print('  [分母] node %s · 端口 %d · 检查 %d 条(PASS %d / FAIL %d)'
              % (ver, port, n_pass + n_fail, n_pass, n_fail))
        if n_pass + n_fail < 12:
            print('  [FAIL] ★分母: 只跑到 %d 条(<12) —— 空检查不是通过' % (n_pass + n_fail))
            print(txt[-800:])
            return 1
        if r.returncode != 0 or n_fail > 0:
            for ln in txt.split(chr(10)):
                if '[FAIL]' in ln:
                    print('  ' + ln.strip())
            print('')
            print('FAILED: 服务端逻辑对不上')
            return 1
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=10)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

    print('')
    print('ALL OK — 服务端逻辑达标(V2 存取往返 / V3 六类伪造全拒 / 同 id 去重)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
