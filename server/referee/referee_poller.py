#!/usr/bin/env python3
"""服务器裁判 · 轮询器（方案书 docs/plans/20261019-服务器裁判.md §1；部署见同目录 README.md）。

循环：领活（PostgREST rpc/referee_claim，service key）→ 调无头 Godot 跑一局（res://scenes/Referee.tscn）→ 写回
（rpc/referee_complete；算不了的 rpc/referee_fail）。并发 N 个工作线程（默认 = CPU 核数），每个线程同一时刻只跑一局。

只用标准库（Ubuntu 24.04 自带 python3.12 即可）。配置全走环境变量（systemd EnvironmentFile）：

  SUPABASE_URL           https://<项目>.supabase.co（不带结尾斜杠）
  SUPABASE_SERVICE_KEY   service_role 密钥（★只放 /etc/turtle-referee/env，权限 600，不进仓库）
  GODOT_BIN              默认 /opt/godot/godot（4.6.3，与客户端同一个引擎版本）
  VERSIONS_DIR           默认 /opt/turtle —— 每个子目录一份工程（读它的 project.godot 里的 config/version；
                         只领这些版本的任务。一个版本一套：结果只在同版本里成立）
  WORK_DIR               默认 /var/lib/turtle-referee（每个线程一个子目录：任务单 / 结果单 / user:// / 日志）
  WORKERS                默认 = CPU 核数
  POLL_SEC               空闲时多久领一次，默认 2
  JOB_TIMEOUT_SEC        一局的墙钟上限，默认 600（10-19 CX33 实测: 真实满装备快照三路打满不录约 150 秒; 原默认 120 会把重局判超时）
  WORKER_NAME            默认 = 主机名（线程号会接在后面）
  STREAM_ROOT            逐帧直播状态流的对外目录（Caddy 只读分发，见 server/stream/README.md）。
                         ★默认空 = 不录流（不给 Godot 传 --stream）。设了也只对含 scripts/systems/stream/ 的工程版本生效。
                         每局：Godot 写 <STREAM_TMP>/<match_id>/，轮询器边算边把**写完的块**一个一个原子 rename 到
                         <STREAM_ROOT>/<match_id>/（块 N 在块 N+1 出现时才算写完），最后挪 end.json。
  STREAM_TMP             默认 <STREAM_ROOT>-tmp（必须与 STREAM_ROOT 同一文件系统，rename 才是原子的）

补流（逐帧直播 §5，迁移 20261020_referee_live_list.sql，2026-10-20 · ★只改了仓库文件、未部署）：
  正常任务领不到时，再领一份「补流」任务（rpc/referee_claim_restream；任务单 = 原任务 + task = "restream"）。
  用原快照 + 种子再算一遍，**只产出状态流**：不调 referee_complete（不写回结果、不改账），算完 rpc/referee_restream_done。
  重算的胜方 / 指纹必须等于原结果（expect_winner / expect_digest），对不上 ⇒ 撤掉这份流、判永久失败。
  没设 STREAM_ROOT / 工程没有录流代码 ⇒ 补不了，判永久失败；对外目录已有 end.json ⇒ 不重算，直接记 done。
  服务端没部署（rpc 404）⇒ 本进程不再领补流。

子命令：
  referee_poller.py                 常驻轮询（systemd 用这个）
  referee_poller.py --once          领一份、跑完、写回就退（上线前手测）
  referee_poller.py --local JOB.json [--out RESULT.json]
                                    不连库：拿本地任务单直接调 Godot（版本取任务单里的 client_version）
  referee_poller.py --health        打印 rpc/referee_backlog；积压或心跳超阈值时退出码 1（给 systemd timer / 外部告警）
  referee_poller.py --versions      打印本机装了哪些版本
"""
import argparse
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

SCENE = "res://scenes/Referee.tscn"
QUIT_AFTER_FRAMES = "20000"            # 防卡死第三道（裁判自己有步数 / 帧数上限）；100ms 预算下一局 < 200 帧
HEALTH_MAX_PENDING_SEC = 120
HEALTH_MAX_HEARTBEAT_SEC = 120
STREAM_PUMP_SEC = 0.25                 # 边算边播: 多久扫一次临时目录
_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_CHUNK_RE = re.compile(r"^[0-9]{6}\.bin$")

_stop = threading.Event()
TASK_RESTREAM = "restream"
_restream_off = threading.Event()      # rpc/referee_claim_restream 回过 404（服务端没上 20261020）⇒ 本进程不再领补流


def log(msg: str) -> None:
    print("%s %s" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), msg), flush=True)


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


# ─────────────────────────────── 版本 → 工程 ───────────────────────────────

_warned = set()
_VER_RE = re.compile(r'^\s*config/version\s*=\s*"([^"]+)"', re.M)


def discover_versions(root: str) -> dict:
    """VERSIONS_DIR 下每个含 project.godot 的子目录 → {client_version: 工程路径}。"""
    out = {}
    if not os.path.isdir(root):
        return out
    for name in sorted(os.listdir(root)):
        proj = os.path.join(root, name)
        pg = os.path.join(proj, "project.godot")
        if not os.path.isfile(pg):
            continue
        # ★没有裁判入口的版本(0.19.571 及更早)不算 —— 领了也跑不了
        if not os.path.isfile(os.path.join(proj, "scenes", "Referee.tscn")):
            if proj not in _warned:
                _warned.add(proj)
                log("WARN %s 没有 scenes/Referee.tscn(裁判入口之前的版本), 跳过" % proj)
            continue
        try:
            with open(pg, encoding="utf-8") as f:
                m = _VER_RE.search(f.read())
        except OSError:
            continue
        if m:
            if m.group(1) in out:
                log("WARN 版本 %s 有两份工程: %s / %s（用前一个）" % (m.group(1), out[m.group(1)], proj))
                continue
            out[m.group(1)] = proj
    return out


# ─────────────────────────────── PostgREST ───────────────────────────────

def rpc(fn: str, body: dict, timeout: float = 20.0):
    url = env("SUPABASE_URL").rstrip("/") + "/rest/v1/rpc/" + fn
    key = env("SUPABASE_SERVICE_KEY")
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST", headers={
        "apikey": key,
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
        "Accept": "application/json",
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
    return json.loads(raw) if raw else None


# ─────────────────────────────── 状态流发布（逐帧直播 S4） ───────────────────────────────

class StreamPublisher:
    """Godot 往临时目录写块；本类把写完的块一个一个原子 rename 到对外目录（Caddy 只读分发）。

    判「写完」：录流器按序号顺序写、每块 open → store → close 之后才开下一块 ⇒ 块 N+1 出现时块 N 已写完；
    end.json 出现或进程已退出 ⇒ 剩下的块都写完了。对外目录里**只会出现完整的文件**。
    """

    def __init__(self, root: str, tmp_root: str, match_id: str):
        self.pub = os.path.join(root, match_id)
        self.tmp = os.path.join(tmp_root, match_id)
        self.moved = 0

    @staticmethod
    def for_job(job: dict, proj: str):
        """开关没开 / 这个版本没有录流 / match_id 不是 uuid / 这局早已完整发布过 ⇒ None（不录）。"""
        root = env("STREAM_ROOT").rstrip("/")
        if not root:
            return None
        if not os.path.isfile(os.path.join(proj, "scripts", "systems", "stream", "stream_recorder.gd")):
            return None
        mid = str(job.get("match_id", "")).lower()
        if not _UUID_RE.match(mid):
            log("WARN job=%s match_id 不是 uuid, 不录流" % job.get("job_id"))
            return None
        sp = StreamPublisher(root, env("STREAM_TMP") or root + "-tmp", mid)
        if os.path.isfile(os.path.join(sp.pub, "end.json")):
            # 重领(写回失败后)的同一局: 结果确定性相同, 已发布的那份照样有效 —— 别换成特效随机不同的另一份
            log("job=%s 状态流已完整发布过, 本次不再录" % job.get("job_id"))
            return None
        return sp

    def prepare(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)
        shutil.rmtree(self.pub, ignore_errors=True)    # 上次失败留下的半截
        os.makedirs(self.tmp, exist_ok=True)
        os.makedirs(self.pub, mode=0o755, exist_ok=True)
        os.chmod(self.pub, 0o755)

    def pump(self, final: bool = False) -> None:
        try:
            names = sorted(n for n in os.listdir(self.tmp) if _CHUNK_RE.match(n))
        except OSError:
            return
        if not (final or os.path.exists(os.path.join(self.tmp, "end.json"))):
            names = names[:-1]                         # 最新那块可能还在写
        for n in names:
            src = os.path.join(self.tmp, n)
            os.chmod(src, 0o644)
            os.replace(src, os.path.join(self.pub, n))
            self.moved += 1

    def finish(self, ok: bool) -> None:
        """进程已退出后调。成功 ⇒ 挪完剩下的块、最后挪 end.json；失败 ⇒ 撤掉半截（重领会从头再录）。"""
        if ok:
            self.pump(final=True)
            ej = os.path.join(self.tmp, "end.json")
            if os.path.exists(ej):
                os.chmod(ej, 0o644)
                os.replace(ej, os.path.join(self.pub, "end.json"))
            else:
                log("WARN %s: 局算完了但没有 end.json" % self.tmp)
        else:
            shutil.rmtree(self.pub, ignore_errors=True)
        shutil.rmtree(self.tmp, ignore_errors=True)
        log("stream %s: %s, 发布 %d 块" % (os.path.basename(self.pub), "ok" if ok else "撤回", self.moved))


# ─────────────────────────────── 跑一局 ───────────────────────────────

def run_godot(job: dict, proj: str, wdir: str, timeout_sec: int, accept=None, sp="auto") -> tuple:
    """写任务单 → 调 Godot（录流开着时边算边发布块）→ 读结果单。返回 (rc, result_dict_or_None, log_tail)。

    accept(res) -> bool：额外判「这份流算不算数」（补流用：重算结果必须等于原结果），False ⇒ 撤掉这份流。
    sp：调用方已经决定好的发布器（补流先判过「能不能录」）；"auto" = 按任务单自己判。
    """
    os.makedirs(wdir, exist_ok=True)
    jp = os.path.join(wdir, "job.json")
    rp = os.path.join(wdir, "result.json")
    lp = os.path.join(wdir, "godot.log")
    ud = os.path.join(wdir, "userdata")
    if os.path.exists(rp):
        os.remove(rp)
    # ★每局一份干净的 user://（Linux 上 user:// 走 XDG_DATA_HOME —— CLAUDE.md §2「只修了当前平台」那一课）
    shutil.rmtree(ud, ignore_errors=True)
    os.makedirs(ud, exist_ok=True)
    with open(jp, "w", encoding="utf-8") as f:
        json.dump(job, f, ensure_ascii=False)
    e = dict(os.environ)
    e.pop("SUPABASE_SERVICE_KEY", None)   # Godot 不需要、也不该看到钥匙
    e.update({"XDG_DATA_HOME": ud, "APPDATA": ud, "HOME": ud,
              "TURTLE_SUPABASE": " ", "TURTLE_BACKEND": " "})
    for k in ("TURTLE_SEED", "DL_AUTOFIGHT", "STRESS", "SIM_AUTOPILOT"):
        e.pop(k, None)
    e.pop("REFEREE_STREAM", None)
    cmd = [env("GODOT_BIN", "/opt/godot/godot"), "--headless", "--audio-driver", "Dummy", "--path", proj, SCENE,
           "--quit-after", QUIT_AFTER_FRAMES, "--", "--job=" + jp, "--out=" + rp]
    if sp == "auto":
        sp = StreamPublisher.for_job(job, proj)
    if sp is not None:
        sp.prepare()
        cmd.append("--stream=" + sp.tmp)
    t0 = time.time()
    with open(lp, "w", encoding="utf-8", errors="replace") as lf:
        p = subprocess.Popen(cmd, stdout=lf, stderr=subprocess.STDOUT, env=e)
        while True:
            try:
                rc = p.wait(timeout=STREAM_PUMP_SEC)
                break
            except subprocess.TimeoutExpired:
                pass
            if time.time() - t0 > timeout_sec:
                p.kill()
                p.wait()
                rc = -9
                break
            if sp is not None:
                try:
                    sp.pump()
                except OSError as ex:      # 发布出错不影响算结果: 这一局放弃录流
                    log("WARN 发布块失败, 本局不再发布: %r" % ex)
                    sp.finish(False)
                    sp = None
    tail = ""
    try:
        with open(lp, encoding="utf-8", errors="replace") as lf:
            tail = "".join(lf.readlines()[-30:])
    except OSError:
        pass
    res = None
    if os.path.exists(rp):
        try:
            with open(rp, encoding="utf-8") as f:
                res = json.load(f)
        except (OSError, ValueError):
            res = None
    if sp is not None:
        try:
            good = rc == 0 and isinstance(res, dict) and res.get("ok") is True
            sp.finish(good and (accept is None or bool(accept(res))))
        except OSError as ex:
            log("WARN 收尾发布失败: %r" % ex)
    log("godot rc=%s %.1fs job=%s" % (rc, time.time() - t0, job.get("job_id")))
    return rc, res, tail


def handle(job: dict, versions: dict, worker: str, wdir: str) -> None:
    jid = job.get("job_id")
    ver = str(job.get("client_version", ""))
    proj = versions.get(ver)
    if proj is None:
        # 领活时已按版本过滤, 走到这里 = 工程目录在两次扫描之间被删了 —— 放回去给别的裁判
        rpc("referee_fail", {"p_job_id": jid, "p_worker": worker, "p_error": "no_project:" + ver, "p_permanent": False})
        return
    rc, res, tail = run_godot(job, proj, wdir, int(env("JOB_TIMEOUT_SEC", "600")))
    if rc == 0 and isinstance(res, dict) and res.get("ok") is True:
        if str(res.get("match_id")) != str(job.get("match_id")):
            rpc("referee_fail", {"p_job_id": jid, "p_worker": worker, "p_error": "match_id_mismatch", "p_permanent": False})
            return
        r = rpc("referee_complete", {"p_job_id": jid, "p_worker": worker, "p_result": res})
        log("complete job=%s winner=%s score=%s steps=%s digest=%s → %s" % (
            jid, res.get("winner"), res.get("score_code"), res.get("steps"), res.get("digest"), json.dumps(r)))
        return
    permanent = isinstance(res, dict) and bool(res.get("permanent"))
    err = (res or {}).get("error") if isinstance(res, dict) else None
    err = err or ("rc=%s %s" % (rc, tail[-400:].replace("\n", " | ")))
    r = rpc("referee_fail", {"p_job_id": jid, "p_worker": worker, "p_error": err, "p_permanent": permanent})
    log("fail job=%s permanent=%s err=%s → %s" % (jid, permanent, err[:200], json.dumps(r)))


def restream_check(job: dict, res) -> str:
    """补流重算的结果与原结果对不对得上。"" = 对得上；否则是原因。"""
    if not isinstance(res, dict) or res.get("ok") is not True:
        return "not_ok"
    if str(res.get("match_id")) != str(job.get("match_id")):
        return "match_id_mismatch"
    ew = job.get("expect_winner")
    if ew and str(res.get("winner")) != str(ew):
        return "winner_mismatch:%s!=%s" % (res.get("winner"), ew)
    ed = job.get("expect_digest")
    if ed and str(res.get("digest")) != str(ed):
        return "digest_mismatch"
    return ""


def handle_restream(job: dict, versions: dict, worker: str, wdir: str) -> None:
    """补流：原快照 + 种子再算一遍，只发布状态流。★不调 referee_complete（不写回结果、不改账）。"""
    mid = str(job.get("match_id", ""))
    ver = str(job.get("client_version", ""))

    def done(ok: bool, err: str = "", permanent: bool = False) -> None:
        r = rpc("referee_restream_done", {"p_match_id": mid, "p_worker": worker, "p_ok": ok,
                                          "p_error": err or None, "p_permanent": permanent})
        log("restream %s %s %s → %s" % (mid, "ok" if ok else "fail", err[:200], json.dumps(r)))

    proj = versions.get(ver)
    if proj is None:
        done(False, "no_project:" + ver)
        return
    if not env("STREAM_ROOT").rstrip("/") or not os.path.isfile(
            os.path.join(proj, "scripts", "systems", "stream", "stream_recorder.gd")):
        done(False, "stream_off", permanent=True)
        return
    root = env("STREAM_ROOT").rstrip("/")
    if os.path.isfile(os.path.join(root, mid.lower(), "end.json")):
        done(True)                     # 已经有完整的一份（别的线程 / 上一次补过）: 不再重算
        return
    sp = StreamPublisher.for_job(job, proj)
    if sp is None:
        done(False, "no_publisher", permanent=True)
        return
    why = {"v": ""}

    def accept(res) -> bool:
        why["v"] = restream_check(job, res)
        return why["v"] == ""

    rc, res, tail = run_godot(job, proj, wdir, int(env("JOB_TIMEOUT_SEC", "600")), accept=accept, sp=sp)
    if rc == 0 and isinstance(res, dict) and res.get("ok") is True:
        if why["v"] == "":
            done(True)
        else:
            done(False, why["v"], permanent=True)     # 同版本同快照同种子却算出不同的结果: 重试也一样, 流已撤
        return
    permanent = isinstance(res, dict) and bool(res.get("permanent"))
    err = (res or {}).get("error") if isinstance(res, dict) else None
    done(False, err or ("rc=%s %s" % (rc, tail[-400:].replace("\n", " | "))), permanent)


def claim_restream(worker: str, versions: dict) -> list:
    """领一份补流任务；服务端没部署（404）⇒ 本进程以后不再领。"""
    if _restream_off.is_set():
        return []
    try:
        return rpc("referee_claim_restream", {"p_worker": worker, "p_versions": sorted(versions), "p_limit": 1}) or []
    except urllib.error.HTTPError as ex:
        if ex.code == 404:
            _restream_off.set()
            log("referee_claim_restream 404（服务端没上 20261020）: 本进程不再领补流")
            return []
        raise


def worker_loop(idx: int, once: bool) -> None:
    worker = "%s-%d" % (env("WORKER_NAME", socket.gethostname()), idx)
    wdir = os.path.join(env("WORK_DIR", "/var/lib/turtle-referee"), "w%d" % idx)
    poll = float(env("POLL_SEC", "2"))
    while not _stop.is_set():
        versions = discover_versions(env("VERSIONS_DIR", "/opt/turtle"))
        if not versions:
            log("WARN %s: VERSIONS_DIR 下没有工程, 不领活" % worker)
            _stop.wait(30)
            continue
        try:
            jobs = rpc("referee_claim", {"p_worker": worker, "p_versions": sorted(versions), "p_limit": 1}) or []
        except (urllib.error.URLError, OSError, ValueError) as ex:
            log("WARN %s 领活失败: %s" % (worker, ex))
            _stop.wait(max(poll, 5))
            continue
        if not jobs:
            ## 正常任务空了才领补流（真比赛永远优先）
            try:
                jobs = claim_restream(worker, versions)
            except (urllib.error.URLError, OSError, ValueError) as ex:
                log("WARN %s 领补流失败: %s" % (worker, ex))
                jobs = []
        if not jobs:
            if once:
                log("%s: 没有待算的任务" % worker)
                return
            _stop.wait(poll)
            continue
        for job in jobs:
            try:
                if str(job.get("task", "")) == TASK_RESTREAM:
                    handle_restream(job, versions, worker, wdir)
                else:
                    handle(job, versions, worker, wdir)
            except Exception as ex:      # 网络 / 意外: 不写回 ⇒ 租期一过别的裁判重领
                log("ERROR %s job=%s: %r" % (worker, job.get("job_id"), ex))
        if once:
            return


def main() -> int:
    ap = argparse.ArgumentParser(description="服务器裁判轮询器")
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--local")
    ap.add_argument("--out")
    ap.add_argument("--health", action="store_true")
    ap.add_argument("--versions", action="store_true")
    a = ap.parse_args()
    versions = discover_versions(env("VERSIONS_DIR", "/opt/turtle"))
    if a.versions:
        print(json.dumps(versions, ensure_ascii=False, indent=1))
        return 0
    if a.local:
        with open(a.local, encoding="utf-8") as f:
            job = json.load(f)
        proj = versions.get(str(job.get("client_version", "")))
        if proj is None:
            print("本机没有版本 %s 的工程（VERSIONS_DIR=%s）" % (job.get("client_version"), env("VERSIONS_DIR", "/opt/turtle")))
            return 2
        rc, res, tail = run_godot(job, proj, os.path.join(env("WORK_DIR", "/var/lib/turtle-referee"), "local"),
                                  int(env("JOB_TIMEOUT_SEC", "600")))
        if a.out and res is not None:
            with open(a.out, "w", encoding="utf-8") as f:
                json.dump(res, f, ensure_ascii=False)
        brief = {k: (res or {}).get(k) for k in ("ok", "error", "winner", "score_code", "steps", "digest", "elapsed_ms")}
        print(json.dumps({"rc": rc, **brief}, ensure_ascii=False))
        return 0 if rc == 0 else 1
    if not env("SUPABASE_URL") or not env("SUPABASE_SERVICE_KEY"):
        print("缺 SUPABASE_URL / SUPABASE_SERVICE_KEY")
        return 2
    if a.health:
        b = rpc("referee_backlog", {})
        print(json.dumps(b, ensure_ascii=False))
        stale = int((b or {}).get("oldest_pending_sec", 0)) > HEALTH_MAX_PENDING_SEC
        ws = (b or {}).get("workers") or []
        dead = not ws or min(int(w.get("seen_sec", 1 << 30)) for w in ws) > HEALTH_MAX_HEARTBEAT_SEC
        return 1 if (stale or dead) else 0
    n = int(env("WORKERS", str(os.cpu_count() or 1)))
    log("referee poller: %d workers, versions=%s" % (1 if a.once else n, sorted(versions)))
    signal.signal(signal.SIGTERM, lambda *_: _stop.set())
    signal.signal(signal.SIGINT, lambda *_: _stop.set())
    ts = [threading.Thread(target=worker_loop, args=(i, a.once), daemon=True) for i in range(1 if a.once else n)]
    for t in ts:
        t.start()
    for t in ts:
        while t.is_alive():
            t.join(1.0)
    log("referee poller: stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
