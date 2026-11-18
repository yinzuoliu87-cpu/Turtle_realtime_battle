"""另起一个独立 Chrome(独立临时配置目录、静音、右屏), 用 DevTools 协议抓 GPU 追踪, 统计着色器编译 / 链接 / 贴图上传耗时。
用法: python gputrace.py <仓库根> <网址> [录多少秒=140]
不碰用户自己的 Chrome 配置; 结束时关掉这个独立实例。"""
import json
import os
import subprocess
import sys
import time
import urllib.request

import websocket

ROOT, URL = sys.argv[1], sys.argv[2]
SEC = int(sys.argv[3]) if len(sys.argv) > 3 else 140
PORT = 9333
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PROF = os.path.join(ROOT, ".out", "webperf", "chrome_profile")
OUT = os.path.join(ROOT, ".out", "webperf", "gputrace.json")
op = urllib.request.build_opener(urllib.request.ProxyHandler({}))

proc = subprocess.Popen([CHROME, "--user-data-dir=" + PROF, "--remote-debugging-port=%d" % PORT, "--no-first-run",
                         "--no-default-browser-check", "--mute-audio", "--window-position=2000,80", "--window-size=1280,860",
                         "--disable-features=Translate", "about:blank"])
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


cats = ["gpu", "gpu.service", "gpu.angle", "disabled-by-default-gpu.service", "disabled-by-default-gpu.device",
        "toplevel", "viz", "blink", "devtools.timeline"]
wait_id(send("Tracing.start", {"traceConfig": {"includedCategories": cats, "recordMode": "recordContinuously"},
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
        events += m["params"]["value"]
ws.settimeout(60)
send("Tracing.end")
while True:
    m = json.loads(ws.recv())
    if m.get("method") == "Tracing.dataCollected":
        events += m["params"]["value"]
    elif m.get("method") == "Tracing.tracingComplete":
        break
try:
    send("Browser.close")
except Exception:
    pass
time.sleep(2)
if proc.poll() is None:
    proc.terminate()
json.dump(events, open(OUT, "w"))
print("events %d -> %s" % (len(events), OUT))
