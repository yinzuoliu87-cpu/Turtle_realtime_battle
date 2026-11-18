"""另起一个独立 Chrome(独立临时配置目录、静音、右屏), 用 DevTools 协议抓 GPU 追踪, 统计着色器编译 / 链接 / 贴图上传耗时。
用法: python gputrace.py <仓库根> <网址> [录多少秒=140]
环境变量 COLD=1 ⇒ 关掉 Chrome 的着色器磁盘缓存 / 程序缓存(每次都真编译 = 模拟第一次来看的人; 本机缓存会跨配置目录留存, 不关就量不到首次)。
结束前对页面截一张图(.out/webperf/gputrace_end.png: perf=1 读数里的长帧清单)。
不碰用户自己的 Chrome 配置; 结束时关掉这个独立实例。"""
import json
import os
import subprocess
import sys
import time
import urllib.request

import websocket

ROOT, URL = os.path.abspath(sys.argv[1]), sys.argv[2]   # ★绝对路径: --user-data-dir 给相对路径时 Chrome 起不来(11-18 实测)
SEC = int(sys.argv[3]) if len(sys.argv) > 3 else 140
PORT = 9333
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PROF = os.path.join(ROOT, ".out", "webperf", "chrome_profile")
OUT = os.path.join(ROOT, ".out", "webperf", "gputrace.json")
op = urllib.request.build_opener(urllib.request.ProxyHandler({}))

proc = subprocess.Popen([CHROME, "--user-data-dir=" + PROF, "--remote-debugging-port=%d" % PORT, "--no-first-run",
                         "--no-default-browser-check", "--mute-audio", "--window-position=2000,80", "--window-size=1280,860",
                         "--disable-features=Translate"] + (["--disable-gpu-shader-disk-cache", "--disable-gpu-program-cache"]
                                                            if os.environ.get("COLD") == "1" else []) + ["about:blank"])
ver = None
for _ in range(60):
    try:
        ver = json.loads(op.open("http://127.0.0.1:%d/json/version" % PORT, timeout=2).read())
        break
    except Exception:
        time.sleep(0.5)
assert ver, "devtools not up"
ws = websocket.create_connection(ver["webSocketDebuggerUrl"], timeout=30, suppress_origin=True)
mid = [0]


def send(method, params=None):
    mid[0] += 1
    ws.send(json.dumps({"id": mid[0], "method": method, "params": params or {}}))
    return mid[0]


def wait_id(i):
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == i:
            return m


## ★默认只录显卡那几类(11-18: 带上 blink / toplevel / viz 一局 208 万条, 环形缓冲把前两分半的编译事件挤掉了); 要别的用环境变量 CATS=a,b,c
cats = [c for c in os.environ.get("CATS", "gpu,gpu.service,gpu.angle,disabled-by-default-gpu.service,disabled-by-default-gpu.device").split(",") if c]
## ★边收边写(11-18: 一局 40 万条事件攒成一个列表再 json.dump, Python 3.14 当场崩「Executing a cache」, 文件只写了一半)
_out = open(OUT, "w", encoding="utf-8")
_out.write("[\n")
_n = [0]


def emit(batch):
    for e in batch:
        _out.write((",\n" if _n[0] else "") + json.dumps(e, ensure_ascii=False))
        _n[0] += 1


## 环形缓冲默认只装得下约 220 万条(一局开打前那段会被挤掉); BUF_KB=1500000 之类放大
_tc = {"includedCategories": cats, "recordMode": "recordContinuously"}
if os.environ.get("BUF_KB"):
    _tc["traceBufferSizeInKb"] = int(os.environ["BUF_KB"])
wait_id(send("Tracing.start", {"traceConfig": _tc,
                               "transferMode": "ReportEvents", "bufferUsageReportingInterval": 2000}))
wait_id(send("Target.createTarget", {"url": URL}))
events = []
t_end = time.time() + SEC
ws.settimeout(1.0)
while time.time() < t_end:
    try:
        m = json.loads(ws.recv())
    except websocket.WebSocketTimeoutException:
        continue
    if m.get("method") == "Tracing.dataCollected":
        emit(m["params"]["value"])
ws.settimeout(60)
try:
    pages = [t for t in json.loads(op.open("http://127.0.0.1:%d/json" % PORT, timeout=5).read()) if t.get("type") == "page" and t.get("url", "").startswith("http")]
    if pages:
        pw = websocket.create_connection(pages[0]["webSocketDebuggerUrl"], timeout=30, suppress_origin=True)
        pw.send(json.dumps({"id": 1, "method": "Page.captureScreenshot", "params": {"format": "png"}}))
        while True:
            m = json.loads(pw.recv())
            if m.get("id") == 1:
                break
        import base64
        open(os.path.join(ROOT, ".out", "webperf", "gputrace_end.png"), "wb").write(base64.b64decode(m["result"]["data"]))
        pw.close()
except Exception as e:  # noqa: BLE001
    print("screenshot failed:", e)
send("Tracing.end")
while True:
    m = json.loads(ws.recv())
    if m.get("method") == "Tracing.dataCollected":
        emit(m["params"]["value"])
    elif m.get("method") == "Tracing.tracingComplete":
        break
try:
    send("Browser.close")
except Exception:
    pass
time.sleep(2)
if proc.poll() is None:
    proc.terminate()
_out.write("\n]\n")
_out.close()
print("events %d -> %s" % (_n[0], OUT))
