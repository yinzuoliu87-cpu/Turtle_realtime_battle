"""裁判机换 ARM · 抢货(2026-11-16 · 方案书 docs/plans/20261116c-裁判机换ARM.md §4.1)。

用户 11-16「那到时候安排个日子换喽…你看安排哪天，你给它搞好」。
CAX21(ARM 4 核 8G)11-16 傍晚三个机房都没货; 主 IPv4 只能在同一机房里从旧机挪到新机 ⇒ 只等纽伦堡(nbg1)。
.github/workflows/referee-arm-grab.yml 每 30 分钟跑一次 `--run`: nbg1 有货、且还没有 labels.purpose=referee-arm 的机子
⇒ 当场开一台 turtle-referee-2(开出来就按小时计费 €0.0168 不含税, 等装机); 已经有了就什么都不做(最多一台)。
换完机之后删掉那个定时任务。

  python tools/referee_arm_grab.py            自测 decide()(不连 Hetzner; 门禁跑这个, 成功打印 ALL OK)
  python tools/referee_arm_grab.py --status   只读: 各机房 cax21 有没有货 + 已有的 referee-arm 机子
  python tools/referee_arm_grab.py --run      有货且没开过 ⇒ 开机(要 HCLOUD_TOKEN 环境变量或 ~/.config/turtle/hcloud_token)
"""
import json
import os
import sys
import urllib.request

TYPE = "cax21"
LOCATION = "nbg1"                      # 只等这里: 旧机在 nbg1, 主 IP 只能同机房挪
NAME = "turtle-referee-2"
LABEL = {"purpose": "referee-arm"}
SSH_KEY = "turtle-referee"


def decide(avail: dict, existing: list) -> str:
    """avail = {机房: 有没有货}; existing = 已有的 referee-arm 机子名单。
    返回 'exists'(已经开过, 不动)/ 'create'(nbg1 有货, 开)/ 'wait'(没货, 下次再看)。"""
    if existing:
        return "exists"
    return "create" if avail.get(LOCATION) is True else "wait"


def _token() -> str:
    t = os.environ.get("HCLOUD_TOKEN", "").strip()
    if t:
        return t
    p = os.path.expanduser("~/.config/turtle/hcloud_token")
    return open(p, encoding="utf-8").read().strip() if os.path.isfile(p) else ""


def _hz(method: str, path: str, body=None):
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://api.hetzner.cloud/v1" + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + _token(), "Content-Type": "application/json"})
    try:
        with op.open(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def availability() -> dict:
    st, b = _hz("GET", "/server_types?name=" + TYPE)
    t = (b.get("server_types") or [{}])[0]
    return {loc["name"]: bool(loc.get("available")) for loc in t.get("locations", [])}


def existing_arm() -> list:
    st, b = _hz("GET", "/servers?label_selector=purpose%3D" + LABEL["purpose"])
    return [s["name"] for s in b.get("servers", [])]


def run(dry: bool) -> int:
    if not _token():
        print("没有 HCLOUD_TOKEN, 不查")
        return 0
    avail, ex = availability(), existing_arm()
    act = decide(avail, ex)
    print("cax21 有货: %s · 已有 referee-arm: %s ⇒ %s" % (avail, ex or "无", act))
    if act != "create" or dry:
        return 0
    st, b = _hz("POST", "/servers", {"name": NAME, "server_type": TYPE, "image": "ubuntu-24.04", "location": LOCATION,
                                     "ssh_keys": [SSH_KEY], "labels": LABEL})
    if st in (200, 201):
        s = b["server"]
        print("★已开机 %s id=%s IPv4=%s(临时 IP; 切换时换成旧机的 49.13.166.188)" % (
            s["name"], s["id"], s["public_net"]["ipv4"]["ip"]))
    else:
        print("开机失败 %s %s" % (st, json.dumps(b, ensure_ascii=False)[:300]))
    return 0                            # 定时任务不因为没货 / 开失败而报红(下次再试); 结果看本次运行的输出


def selftest() -> int:
    n = fails = 0
    cases = [
        ({"nbg1": True, "fsn1": False, "hel1": False}, [], "create", "nbg1 有货、没开过 ⇒ 开"),
        ({"nbg1": False, "fsn1": True, "hel1": True}, [], "wait", "★别的机房有货也不开(IP 挪不过去)"),
        ({"nbg1": True}, ["turtle-referee-2"], "exists", "★已经开过 ⇒ 不再开第二台"),
        ({"nbg1": False}, ["turtle-referee-2"], "exists", "已经开过、没货 ⇒ exists"),
        ({}, [], "wait", "接口没回机房 ⇒ 等"),
        ({"nbg1": "true"}, [], "wait", "★不是布尔 True 不算有货"),
    ]
    for avail, ex, want, label in cases:
        n += 1
        got = decide(avail, ex)
        ok = got == want
        fails += 0 if ok else 1
        print("  [%s] %s (%s)" % ("PASS" if ok else "FAIL", label, got))
    if fails == 0 and n >= 6:
        print("ALL OK — referee_arm_grab 只在 nbg1 有货且没开过时开一台 (%d 条)" % n)
        return 0
    print("FAIL x%d / %d" % (fails, n))
    return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    a = sys.argv[1:]
    if not a:
        sys.exit(selftest())
    if a[0] == "--status":
        sys.exit(run(dry=True))
    if a[0] == "--run":
        sys.exit(run(dry=False))
    print(__doc__)
    sys.exit(2)
