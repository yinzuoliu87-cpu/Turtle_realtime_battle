# -*- coding: utf-8 -*-
"""tools/dl_android_selftest.py —— `tools/deploy.py --only android`（安卓下载跳转）自测（2026-11-18 · 方案书 20261118b A3）。

不连网、不碰服务器：ssh / scp / GitHub / DNS / HTTPS 回读全部换成假的，只验「什么情况下动服务器、动了什么、回读怎么判」。
  ① 跳转目标行：合形状的 Release 网址才写；空格 / 花括号 / 别的域名 / 别的文件名一律拒（它会被原样写进 Caddy 配置）
  ② 前置检查不过（DNS 没指过来 / Release 没包 / 包太小 / 周末）⇒ 不对服务器写任何东西
  ③ 正常路径：传两份文件 → 一段脚本里 validate 过了才 reload → 回读目标 + 302 Location + 安装包大小
  ④ validate 不过 ⇒ 脚本按备份还原、工具报红；回读 Location 不对 ⇒ 红
  ⑤ 三处同一个链接：游戏里强更挡墙的安卓链接 / android.yml 写进 Release 说明的链接 / Caddy 片段的站点名
"""
import io
import os
import re
import sys
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import deploy as D  # noqa: E402
import sb_common as S  # noqa: E402

REPO = D.REPO
fails = []
n = 0


def check(cond, msg):
    global n
    n += 1
    if cond:
        print("  ok  " + msg)
    else:
        print("  FAIL " + msg)
        fails.append(msg)


VER = "0.23.5"
URL = "https://github.com/yinzuoliu87-cpu/Turtle_realtime_battle/releases/download/v0.23.5/turtle-arena-0.23.5.apk"
ASSET = {"name": "turtle-arena-0.23.5.apk", "size": 175000000, "state": "uploaded", "browser_download_url": URL}


class Fake:
    def __init__(self, dns=True, asset=ASSET, script_out="DL_RELOADED\n", served=URL, probe=(302, URL), weekend=False,
                 head_len=None):
        self.calls = []
        self.scps = []
        self.dns, self.asset, self.script_out, self.served, self.probe = dns, asset, script_out, served, probe
        self.weekend = weekend
        self.head_len = ASSET["size"] if head_len is None else head_len
        self.state_reads = 0

    def ssh(self, cmd, timeout=25, data=None):
        self.calls.append((cmd, data))
        if cmd.startswith("cat /etc/caddy/turtle-dl-target.caddy"):
            self.state_reads += 1
            tgt = D.dl_target_line(self.served) if (self.served and self.state_reads > 1) else ""
            return 0, tgt + "@@\n1\n", ""
        if cmd == "bash -s":
            return 0, self.script_out, ""
        return 0, "", ""

    def writes(self):
        return [c for c, _ in self.calls if c == "bash -s" or c.startswith("mkdir")]


def run(fake, **kw):
    args = dict(version=VER, env="prod", dry_run=False, init=False, allow_weekend=False)
    args.update(kw)
    a = types.SimpleNamespace(**args)
    D.ssh = fake.ssh
    D._scp = lambda local, remote: fake.scps.append((os.path.basename(local), remote, open(local, "rb").read()))
    D.gh_release_asset = lambda v: (fake.asset, None) if fake.asset else (None, "Release v%s 不在" % v)
    D.dl_dns_ok = lambda: (fake.dns, "dl → x")
    D.dl_probe = lambda path="/android": fake.probe
    D.DL_WAIT_SEC = 0
    D.time.sleep = lambda s: None
    real_gm = D.time.gmtime
    D.time.gmtime = lambda *x: types.SimpleNamespace(tm_wday=5 if fake.weekend else 2)

    class _R:
        def __init__(self):
            self.headers = {"Content-Length": str(fake.head_len)}

        def __enter__(self):
            return self

        def __exit__(self, *x):
            return False

    S.OPENER = types.SimpleNamespace(open=lambda req, timeout=30: _R())
    out = io.StringIO()
    old = sys.stdout
    sys.stdout = out
    try:
        rc = D.deploy_android(a)
    finally:
        sys.stdout = old
        D.time.gmtime = real_gm
    return rc, out.getvalue()


def main():
    S.stdout_utf8()
    print("== ① 跳转目标行")
    check(D.dl_target_line(URL) == "redir @android %s 302\n" % URL, "合形状的网址 ⇒ 一行 redir @android … 302")
    check(D.dl_parse_target(D.dl_target_line(URL)) == URL, "写进去的能原样读回")
    check(D.dl_parse_target("# 空\n") is None and D.dl_parse_target("") is None, "空目标文件 ⇒ None（即将开放）")
    bad = [URL + " 302", URL.replace("github.com", "evil.example"), URL + "}", URL.replace(".apk", ".zip"),
           URL.replace("turtle-arena-0.23.5", "other-0.23.5"), "", None]
    rej = 0
    for b in bad:
        try:
            D.dl_target_line(b)
        except ValueError:
            rej += 1
    check(rej == len(bad), "不合形状的 %d 种全拒（空格 / 别的域名 / 花括号 / 别的扩展名 / 别的文件名 / 空）" % len(bad))

    print("== ② 前置检查不过 ⇒ 不写服务器")
    for name, f in (("DNS 没指过来", Fake(dns=False)), ("Release 没包", Fake(asset=None)),
                    ("包太小", Fake(asset=dict(ASSET, size=1000))), ("周末", Fake(weekend=True))):
        rc, out = run(f)
        check(rc == 1 and not f.writes() and not f.scps, "%s ⇒ 红且没写服务器（rc=%s, 写 %d 次）" % (name, rc, len(f.writes())))
    f = Fake(weekend=True)
    rc, out = run(f, allow_weekend=True)
    check(rc == 0 and f.writes(), "周末带 --allow-weekend ⇒ 照装")
    f = Fake()
    rc, out = run(f, env="beta")
    check(rc == 1 and not f.writes(), "--env beta ⇒ 拒（只有正式一份）")
    f = Fake()
    rc, out = run(f, dry_run=True)
    check(rc == 0 and not f.writes() and not f.scps and "会做的事" in out, "--dry-run ⇒ 只打印、不写")

    print("== ③ 正常路径")
    f = Fake()
    rc, out = run(f)
    check(rc == 0, "rc=0（%s）" % out.strip().splitlines()[-1] if out.strip() else "")
    names = sorted(s[0] for s in f.scps)
    check(names == ["turtle-dl-target.caddy", "turtle-dl.caddy"], "传了两份文件 %s" % names)
    tgt = [s for s in f.scps if s[0] == "turtle-dl-target.caddy"]
    check(tgt and tgt[0][2] == D.dl_target_line(URL).encode(), "目标文件内容 = 这一版的 redir 行")
    snip = [s for s in f.scps if s[0] == "turtle-dl.caddy"]
    check(snip and b"\r\n" not in snip[0][2], "片段传上去是 LF（仓库工作区可能是 CRLF）")
    script = [d for c, d in f.calls if c == "bash -s"]
    check(len(script) == 1, "换入只发一段脚本")
    sc = script[0].decode("utf-8") if script and isinstance(script[0], bytes) else (script[0] if script else "")
    iv = sc.find("caddy validate")
    ir = sc.find("systemctl reload caddy")
    check(0 <= iv < ir, "先 validate 后 reload")
    check("Caddyfile.bak-dl-" in sc and "DL_INVALID_RESTORED" in sc and "rm -f $f" in sc,
          "validate 不过 ⇒ Caddyfile 与两份片段按备份还原（原来没有的删掉）")
    check("grep -q '^import /etc/caddy/turtle-dl.caddy'" in sc, "import 只在没有时追加一次")

    print("== ④ 出错要红")
    f = Fake(script_out="Error: …\nDL_INVALID_RESTORED\n")
    rc, out = run(f)
    check(rc == 1, "validate 不过 ⇒ 红")
    f = Fake(probe=(302, URL.replace("0.23.5", "0.23.4")))
    rc, out = run(f)
    check(rc == 1, "回读 Location 是别的版本 ⇒ 红")
    f = Fake(probe=(404, None))
    rc, out = run(f)
    check(rc == 1, "回读还是 404 ⇒ 红")
    f = Fake(served=URL.replace("0.23.5", "0.23.4"))
    rc, out = run(f)
    check(rc == 1, "服务器上的目标文件没换成这一版 ⇒ 红")
    f = Fake(head_len=12345)
    rc, out = run(f)
    check(rc == 1, "跟到底下载回读大小 ≠ Release ⇒ 红")
    f = Fake(asset=None, served=None, probe=(404, None))
    rc, out = run(f, init=True)
    check(rc == 0 and f.writes(), "--init（还没放过版本）⇒ 装空目标、回读 404 即将开放")

    print("== ⑤ 三处同一个链接")
    want = "https://%s/android" % D.DL_HOST
    vw = io.open(os.path.join(REPO, "scripts", "util", "version_wall.gd"), encoding="utf-8").read() \
        if os.path.exists(os.path.join(REPO, "scripts", "util", "version_wall.gd")) else ""
    if not vw:
        for root, _, files in os.walk(os.path.join(REPO, "scripts")):
            if "version_wall.gd" in files:
                vw = io.open(os.path.join(root, "version_wall.gd"), encoding="utf-8").read()
                break
    m = re.search(r'STORE_URL_ANDROID\s*:?=\s*"([^"]+)"', vw)
    check(m and m.group(1) == want, "游戏强更挡墙安卓链接 = %s（读到 %s）" % (want, m.group(1) if m else None))
    wf = io.open(os.path.join(REPO, ".github", "workflows", "android.yml"), encoding="utf-8").read()
    check(want in wf, "android.yml 写进 Release 说明的玩家链接 = %s" % want)
    sn = io.open(D.DL_SNIPPET, encoding="utf-8").read()
    check(re.search(r"^%s \{" % re.escape(D.DL_HOST), sn, re.M) is not None, "Caddy 片段站点名 = %s" % D.DL_HOST)
    check("@android path /android /android/" in sn and "import /etc/caddy/turtle-dl-target.caddy" in sn,
          "片段里 @android 匹配器 + import 目标文件")

    print("\n[分母] %d 条" % n)
    if fails:
        print("FAIL %d 条" % len(fails))
        return 1
    print("ALL OK — 安卓下载跳转自测 %d 条" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
