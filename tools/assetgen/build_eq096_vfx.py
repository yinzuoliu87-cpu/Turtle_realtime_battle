# -*- coding: utf-8 -*-
"""把 PixelLab 生成的斧头特效帧拉下来, 组装成横排 sheet。

★用户 2026-08-29:「不要拿图片贴图敷衍我, **我要动画像素特效**」⇒ 全是多帧, 不是静止图。
★用户 2026-08-03 铁律「素材不复用除非点名」⇒ 这五组是为斧头(096)新生成的,
  没有拿剑(eq084)那套顶替。

★★不做"加工" —— 2026-08-29 的教训写在 build_eq084_vfx.py 头上:
  **原始帧比我加工后的好**, 我照自己拍的阈值把分层刀光洗白、把辐射细丝剁成碎条。
  这里只做两件不改内容的事: ①拼成横排 sheet ②裁掉全透明边(省显存, 不动像素)。
  任何"提亮/削材质/统一色数"都不做。
"""
import io, os, sys, json, urllib.request

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
from PIL import Image

OUT = os.path.join('assets', 'sprites', 'vfx')

## key → (第 i 帧的 URL 模板, 帧数)
JOBS = {}


## ★★必须【绕开本机代理】—— 直接 urlopen 会 403 Forbidden。
##   本机装着 HTTP(S)_PROXY=127.0.0.1:18081, 它对这个 CDN 会把请求改坏。
##   同族 memory [[fb-local-proxy-corrupts-post-body]]: 那次它给 POST body 头部
##   加 CRLF、末尾截 4 字节, 害我把六条"伪造被拒"全判成了恒真式。
##   ⇒ 凡是本仓库自己发的 HTTP 请求, 一律显式 ProxyHandler({}) 绕开。
_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
_OPENER.addheaders = [('User-Agent', 'Mozilla/5.0'), ('Accept', 'image/png,*/*')]


## ★这个 CDN 直连**不稳定** —— 实测同一个 URL 单次能成、下一次 SSL 握手超时。
##   memory [[fb-no-n1-comparison-on-flaky-process]]: 在会随机失败的通道上做 N=1 判断
##   会把"网络抖了一下"误判成"素材没了"。⇒ 重试三次, 每次都打印, 三次都不行才算失败。
_PROXIED = urllib.request.build_opener()
_PROXIED.addheaders = _OPENER.addheaders


def fetch(url, tries=3):
    last = None
    for i in range(tries):
        for op, tag in ((_OPENER, 'direct'), (_PROXIED, 'proxy')):
            try:
                with op.open(url, timeout=120) as r:
                    return Image.open(io.BytesIO(r.read())).convert('RGBA')
            except Exception as e:
                last = '%s/%s: %s' % (i, tag, e)
                print('  [warn] %s' % last)
    raise SystemExit('  [FAIL] 三次重试(直连+代理)都拿不到: ' + url)


def build(key, url_tpl, n):
    frames = [fetch(url_tpl.replace('{i}', str(i))) for i in range(n)]
    w, h = frames[0].size
    for f in frames:
        if f.size != (w, h):
                print('  [warn] %s' % last)
    raise SystemExit('  [FAIL] 三次重试(直连+代理)都拿不到: ' + url)
    for i, f in enumerate(frames):
        sheet.paste(f, (i * w, 0))
    path = os.path.join(OUT, 'eq096-%s.png' % key)
    sheet.save(path)
    live = sum(1 for i in range(n) if frames[i].getbbox())
    print('  %-10s %d 帧 %dx%d → %s  (非空帧 %d)' % (key, n, w * n, h, path, live))
    if live < n:
        print('     ⚠ 有 %d 帧是全透明的 —— 播出来会"闪一下没了"' % (n - live))
    return live == n


if __name__ == '__main__':
    spec = json.load(io.open(sys.argv[1], encoding='utf-8'))
    ok = True
    for k, v in spec.items():
        ok = build(k, v['url'], int(v['n'])) and ok
    print('  ⇒ %s' % ('全部帧非空' if ok else '★有空帧, 要重生成'))
    sys.exit(0 if ok else 1)
