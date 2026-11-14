"""外服英雄联盟训练营: 全程不用人点(2026-11-06 实走通)。只用外服, 绝不开 WeGame(国服)。

用法:
  python tools/oneoff/lol_practice.py enter <英雄ID>    进训练营, 例 82 = 莫德凯撒
  python tools/oneoff/lol_practice.py quit              对局已退出后, 关掉英雄联盟客户端

走法: Riot 客户端 → 本机接口启动游戏(等同点「开始」) → 客户端本机接口建训练房 → 选人 → 等游戏窗口。
命令行 --launch-product 只在 Riot 客户端没开时有用; 已开时日志写 Auto-launch is disabled, 只切前台不启动。
设计规矩: 前置不满足立刻退出; 等待看进展, 30 秒无变化就停下打印日志, 不等到超时。
退出对局不杀进程: Esc → 点 Exit Game → 点 LEAVE(窗口 1920×1032 时约 (646,804) 与 (844,480), 先截图再点)。
"""
import base64
import ctypes
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
RC_EXE = r"E:\Riot Games\Riot Client\RiotClientServices.exe"
RC_LOCK = os.path.expandvars(r"%LOCALAPPDATA%\Riot Games\Riot Client\Config\lockfile")
RC_LOGS = os.path.expandvars(r"%LOCALAPPDATA%\Riot Games\Riot Client\Logs\Riot Client Logs")
LOL_LOCK = r"D:\Riot Games\League of Legends\lockfile"
STATUS = r"C:\ProgramData\Riot Games\Metadata\league_of_legends.live\league_of_legends.live.update-status.json"
TITLE = "League of Legends (TM) Client"
LOBBY = {"queueId": 3140, "isCustom": True, "customGameLobby": {"configuration": {
    "gameMode": "PRACTICETOOL", "gameMutator": "", "gameServerRegion": "", "mapId": 11, "mutators": {"id": 1},
    "spectatorPolicy": "AllAllowed", "teamSize": 5}, "lobbyName": "Practice Tool", "lobbyPassword": ""}}
_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE
_op = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=_ctx))


def call(lock, method, path, body=None, timeout=8):
    _, _, port, pw, _ = open(lock, encoding="utf-8").read().strip().split(":")
    auth = base64.b64encode(("riot:" + pw).encode()).decode()
    data = b"" if body is None and method == "POST" else (None if body is None else json.dumps(body).encode())
    req = urllib.request.Request("https://127.0.0.1:%s%s" % (port, path), data=data, method=method,
                                 headers={"Authorization": "Basic " + auth, "Content-Type": "application/json"})
    try:
        r = _op.open(req, timeout=timeout)
        t = r.read().decode("utf-8")
        return r.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:200]
    except Exception as e:
        return 0, str(e)[:120]


def log_tail(n=8):
    fs = sorted(os.listdir(RC_LOGS), key=lambda f: os.path.getmtime(os.path.join(RC_LOGS, f)))
    rows = open(os.path.join(RC_LOGS, fs[-1]), encoding="utf-8", errors="replace").read().splitlines()
    for r in rows[-n:]:
        if not any(w in r.lower() for w in ("token", "cookie", "chat:")):
            print("  日志:", r[:150])


def state():
    q = subprocess.run("sc query vgc", shell=True, capture_output=True, text=True, errors="ignore").stdout
    vgc = next((x.split()[3] for x in q.splitlines() if "STATE" in x), "?")
    c = subprocess.run("tasklist", capture_output=True, text=True, errors="ignore").stdout.lower().count("leagueclient")
    return "vgc=%s client=%d lock=%s" % (vgc, c, os.path.exists(LOL_LOCK))


def die(code, msg):
    print("退出:", msg)
    log_tail()
    sys.exit(code)


def start_client():
    if os.path.exists(LOL_LOCK):
        print("英雄联盟客户端已在运行")
        return
    ## 11-13: Riot 客户端上次退出留下旧 lockfile ⇒ 原来当成「已开」, 去连本机接口被拒(10061)。进程不在就当没开。
    rc_up = "riotclientservices" in subprocess.run("tasklist", capture_output=True, text=True, errors="ignore").stdout.lower()
    if not os.path.exists(RC_LOCK) or not rc_up:
        if os.path.exists(RC_LOCK):
            os.remove(RC_LOCK)
        subprocess.Popen([RC_EXE], close_fds=True)
        for _ in range(10):
            time.sleep(3)
            if os.path.exists(RC_LOCK):
                break
        else:
            die(2, "Riot 客户端 30 秒没起来")
    if os.path.exists(STATUS) and json.load(open(STATUS, encoding="utf-8")).get("status", {}).get("updateRequired"):
        die(3, "游戏要更新(updateRequired), 启动接口不会更新, 要先在 Riot 界面更新")
    st, t = call(RC_LOCK, "POST", "/product-launcher/v1/products/league_of_legends/patchlines/live", timeout=5)
    print("启动接口", st, str(t)[:80], "(读超时属正常, 看下面进展)")
    last, same = "", 0
    while not os.path.exists(LOL_LOCK):
        time.sleep(5)
        s = state()
        same = same + 1 if s == last else 0
        if same == 0:
            print(" ", s, flush=True)
        last = s
        if same >= 6:
            die(4, "30 秒无进展: " + s)


def enter(cid):
    start_client()
    for _ in range(20):
        st, s = call(LOL_LOCK, "GET", "/lol-summoner/v1/current-summoner")
        if st == 200:
            break
        time.sleep(2)
    else:
        die(5, "40 秒没登录上")
    for _ in range(4):
        st, r = call(LOL_LOCK, "POST", "/lol-lobby/v2/lobby", LOBBY)
        if st == 200:
            break
        time.sleep(4)
    else:
        die(6, "建房失败 %s %s" % (st, str(r)[:100]))
    call(LOL_LOCK, "POST", "/lol-lobby/v1/lobby/custom/start-champ-select", {})
    for _ in range(12):
        time.sleep(1.5)
        st, s = call(LOL_LOCK, "GET", "/lol-champ-select/v1/session")
        if st != 200 or not isinstance(s, dict):
            continue
        me = s.get("localPlayerCellId")
        for grp in s.get("actions", []):
            for a in grp:
                if a.get("actorCellId") == me and a.get("type") == "pick" and not a.get("completed"):
                    st2, r2 = call(LOL_LOCK, "PATCH", "/lol-champ-select/v1/session/actions/%d" % a["id"],
                                   {"championId": cid, "completed": True})
                    if st2 in (200, 204):
                        print("已选人", cid)
                        return wait_window()
                    die(7, "选人失败 %s %s" % (st2, str(r2)[:100]))
    die(8, "18 秒没轮到选人")


def wait_window():
    u = ctypes.windll.user32
    for i in range(30):
        if u.FindWindowW(None, TITLE):
            print("游戏窗口已出现 %d 秒" % (i * 2))
            return
        time.sleep(2)
    die(9, "60 秒没出现游戏窗口")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "enter":
        enter(int(sys.argv[2]))
    elif len(sys.argv) >= 2 and sys.argv[1] == "quit":
        print("退出客户端", call(LOL_LOCK, "POST", "/process-control/v1/process/quit")[0])
    else:
        print(__doc__)
