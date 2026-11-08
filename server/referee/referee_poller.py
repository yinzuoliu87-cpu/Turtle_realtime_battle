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
  POLL_SEC               刚忙过时多久领一次，默认 2
  IDLE_AFTER_SEC         连续这么久没活才算真空闲，默认 30
  IDLE_POLL_SEC          真空闲时多久领一次，默认 6
  RESTREAM_POLL_SEC      没领到补流后隔多久再问，默认 60；领到了说明有积压，立刻接着问
  JOB_TIMEOUT_SEC        一局的墙钟上限，默认 600（10-19 CX33 实测: 真实满装备快照三路打满不录约 150 秒; 原默认 120 会把重局判超时）
  WORKER_NAME            默认 = 主机名（线程号会接在后面）
  STREAM_ROOT            逐帧直播状态流的对外目录（Caddy 只读分发，见 server/stream/README.md）。
                         ★默认空 = 不录流（不给 Godot 传 --stream）。设了也只对含 scripts/systems/stream/ 的工程版本生效。
                         每局：Godot 写 <STREAM_TMP>/<match_id>/，轮询器边算边把**写完的块**一个一个原子 rename 到
                         <STREAM_ROOT>/<match_id>/（块 N 在块 N+1 出现时才算写完），最后挪 end.json。
  STREAM_TMP             默认 <STREAM_ROOT>-tmp（必须与 STREAM_ROOT 同一文件系统，rename 才是原子的）
  MAINSITE_OUTBOX        龟投发件箱线程（2026-11-09 · 迁移 20261109a）：★默认空 = 关；"1" 才起（见 outbox_loop）
  MAINSITE_BASE          发件箱发往的主站根地址（{MAINSITE_BASE}/api/arena-hook/{topic}）
  MAINSITE_HOOK_SECRET[_FILE]  签名密钥（同网关 mainsite_gateway.py；★不进仓库、不打印）
  OUTBOX_POLL_SEC / OUTBOX_IDLE_POLL_SEC / OUTBOX_IDLE_AFTER_SEC  发件箱忙时 / 空闲时多久领一次、多久算空闲，默认 5 / 30 / 60

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
  referee_poller.py --outbox-once   龟投发件箱只发一批就退（手测；不看 MAINSITE_OUTBOX 开关）
  referee_poller.py --bot-pool [--version V] [--out DIR]
                                    周六机器人快照池（迁移 20261020c，2026-10-20 · ★只改了仓库文件、未部署）：
                                    对每个装了的版本（或只 V）调 Godot 生成（scripts/referee/bot_pool.gd = Backend.make_bot 同一个函数），
                                    分批 rpc/referee_bot_pool_load 上传（第一批清掉同规则版本的旧池）；给了 --out 就只写文件不上传。
                                    ★每装一个新版本都要跑一次（服务端按 rules_ver 挑机器人；池子空 ⇒ 挑不到机器人 ⇒ 玩家开不了战，--health 报警）。
                                    ★2026-11-01 起同一条命令顺带生成并上传**积分赛对手池**（迁移 20261101d · 方案书
                                    docs/plans/20261101c-积分赛服务器裁判.md）：内置陪练（客户端池子里那 396 份）+ 兜底机器人
                                    （scripts/referee/bot_pool.gd generate_ranked，Godot 参数 --ranked-pool=）→ rpc/referee_ranked_pool_load
                                    （按种类分批，每种第一批清旧）。工程里没有 generate_ranked（0.22.7 之前的版本）⇒ 跳过这一半。
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


_now = time.monotonic                  # 自测换成假时钟


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


class IdlePacer:
    """决定下一次领活等多久、这一轮问不问补流（2026-11-07，#23 Supabase 出站流量超额）。

    两个线程闲着也每 2 秒问两次，一天约 12.4 万次，是流量最大头（响应头每次约 900 字节）。
    忙时不变；连续 idle_after 秒没活才放慢到 idle_poll。补流不急：没领到隔 restream_poll 秒再问，
    领到了立刻接着问，不让积压排队。
    """

    def __init__(self, poll: float, idle_poll: float, idle_after: float, restream_poll: float) -> None:
        self.poll = poll
        self.idle_poll = max(poll, idle_poll)
        self.idle_after = idle_after
        self.restream_poll = restream_poll
        self.last_job = _now()
        self.next_restream = 0.0

    def busy(self) -> None:
        self.last_job = _now()

    def restream_due(self) -> bool:
        return _now() >= self.next_restream

    def restream_asked(self, got: bool) -> None:
        self.next_restream = 0.0 if got else _now() + self.restream_poll

    def wait_sec(self) -> float:
        return self.idle_poll if _now() - self.last_job >= self.idle_after else self.poll


def worker_loop(idx: int, once: bool) -> None:
    worker = "%s-%d" % (env("WORKER_NAME", socket.gethostname()), idx)
    wdir = os.path.join(env("WORK_DIR", "/var/lib/turtle-referee"), "w%d" % idx)
    poll = float(env("POLL_SEC", "2"))
    pacer = IdlePacer(poll, float(env("IDLE_POLL_SEC", "6")), float(env("IDLE_AFTER_SEC", "30")),
                      float(env("RESTREAM_POLL_SEC", "60")))
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
        if not jobs and pacer.restream_due():
            ## 正常任务空了才领补流（真比赛永远优先）
            try:
                jobs = claim_restream(worker, versions)
            except (urllib.error.URLError, OSError, ValueError) as ex:
                log("WARN %s 领补流失败: %s" % (worker, ex))
                jobs = []
            pacer.restream_asked(bool(jobs))
        if not jobs:
            if once:
                log("%s: 没有待算的任务" % worker)
                return
            _stop.wait(pacer.wait_sec())
            continue
        pacer.busy()
        for job in jobs:
            try:
                if str(job.get("task", "")) == TASK_RESTREAM:
                    handle_restream(job, versions, worker, wdir)
                else:
                    handle(job, versions, worker, wdir)
            except Exception as ex:      # 网络 / 意外: 不写回 ⇒ 租期一过别的裁判重领
                log("ERROR %s job=%s: %r" % (worker, job.get("job_id"), ex))
        pacer.busy()
        if once:
            return


# ─────────────────────────────── 龟投发件箱（2026-11-09 · 迁移 20261109a_mainsite_core） ───────────────────────────────
# 所有「我们调主站」的写请求（defense / pet-level / started / settle / unlinked）先进表 mainsite_outbox，这个线程发。
# 顺序由 rpc/mainsite_outbox_claim 定（按 id；同 raidId、同 userId 各一条道，settle 等 started）；本线程按回包里的 id 顺序发。
# 重试（方案书 20261107 §4.8）：连不上、5xx、401 ⇒ 退避重试（5 秒起翻倍，封顶 5 分钟，不设次数上限）；
#   HTTP 200 + ok:false ⇒ 记下 last_status 后停（终态）；其余 4xx（请求本身不对，重发也一样）⇒ 终态。
# 开关：MAINSITE_OUTBOX=1 才起（默认关）；另要 MAINSITE_BASE 与 MAINSITE_HOOK_SECRET[_FILE]，缺一个就不起（打一行 WARN）。
# ★签名模块 mainsite_sign.py 用到时才 import：只拷了本文件、没拷它的旧部署照样能跑裁判。
OUTBOX_BATCH = 20
OUTBOX_LEASE_SEC = 120
OUTBOX_RETRY_MAX_SEC = 300
OUTBOX_HTTP_TIMEOUT = 10.0
_outbox_off = threading.Event()          # rpc/mainsite_outbox_claim 回过 404（库里没上 20261109a）⇒ 本进程不再领


def outbox_enabled() -> bool:
    return env("MAINSITE_OUTBOX") == "1"


def _ms():
    """同目录的 mainsite_sign（没有 ⇒ ImportError）。"""
    d = os.path.dirname(os.path.abspath(__file__))
    if d not in sys.path:
        sys.path.insert(0, d)
    import mainsite_sign
    return mainsite_sign


def outbox_retry_sec(attempts: int) -> int:
    """第 attempts 次（从 0 起）失败之后隔多久再发：5、10、20、40 … 封顶 OUTBOX_RETRY_MAX_SEC。"""
    return int(min(OUTBOX_RETRY_MAX_SEC, 5 * (2 ** max(0, min(int(attempts), 12)))))


def outbox_send(base: str, secret: str, topic: str, body: dict, timeout: float = OUTBOX_HTTP_TIMEOUT) -> tuple:
    """签名 POST {base}/api/arena-hook/{topic}。返回 (last_status, 回包 dict 或 None, 要不要重试)。"""
    MS = _ms()
    data = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    hdr = MS.headers(secret, data)
    hdr["Content-Type"] = "application/json"
    req = urllib.request.Request(base.rstrip("/") + "/api/arena-hook/" + topic, data=data, method="POST", headers=hdr)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # 代理会改写 POST body ⇒ 签名对不上
    try:
        with opener.open(req, timeout=timeout) as r:
            code, raw = r.status, r.read()
    except urllib.error.HTTPError as ex:
        code, raw = ex.code, ex.read()
    except Exception as ex:      # 连不上 / 超时 / 对面断开（http.client 的几种异常不都是 OSError）⇒ 当没送到
        return "conn: %s" % (str(getattr(ex, "reason", ex))[:120],), None, True
    try:
        reply = json.loads(raw.decode("utf-8")) if raw else None
    except (ValueError, UnicodeDecodeError):
        reply = None
    if not isinstance(reply, dict):
        reply = None
    if code == 401 or code >= 500:
        return "http_%d" % code, reply, True
    if 200 <= code < 300:
        if reply is None:
            return "bad_reply_http_%d" % code, None, True      # 200 却不是 JSON：多半是中间层的错误页，当没送到
        if reply.get("ok") is True:
            return "ok", reply, False
        return "ok_false: %s" % (str(reply.get("error", ""))[:200],), reply, False
    return "http_%d" % code, reply, False


def outbox_pass(base: str, secret: str) -> int:
    """领一批、按 id 发完、逐条记结果。返回这一批的条数（领活失败 ⇒ -1）。"""
    try:
        rows = rpc("mainsite_outbox_claim", {"p_limit": OUTBOX_BATCH, "p_lease_sec": OUTBOX_LEASE_SEC}) or []
    except urllib.error.HTTPError as ex:
        if ex.code == 404:
            _outbox_off.set()
            log("mainsite_outbox_claim 404（库里没上 20261109a）: 本进程不再发件")
        else:
            log("WARN 发件箱领活失败: HTTP %d" % ex.code)
        return -1
    except (urllib.error.URLError, OSError, ValueError) as ex:
        log("WARN 发件箱领活失败: %s" % ex)
        return -1
    for row in sorted(rows, key=lambda r: int(r.get("id", 0))):
        st, reply, retry = outbox_send(base, secret, str(row.get("topic")), row.get("body") or {})
        mark = {"p_id": row.get("id"), "p_status": st, "p_reply": reply,
                "p_retry_sec": outbox_retry_sec(int(row.get("attempts") or 0)) if retry else None}
        try:
            rpc("mainsite_outbox_mark", mark)
        except (urllib.error.URLError, OSError, ValueError) as ex:
            ## 记不上：租期一过这一条会重发（主站各接口按 raidId / userId 幂等）
            log("WARN 发件箱记结果失败 id=%s: %s" % (row.get("id"), ex))
        log("outbox id=%s %s → %s%s" % (row.get("id"), row.get("topic"), st, "（重试）" if retry else ""))
    return len(rows)


def outbox_loop(once: bool = False) -> int:
    """发件箱常驻线程（MAINSITE_OUTBOX=1 才起）。once ⇒ 只跑一批就返回。返回总共发了几条。"""
    base = env("MAINSITE_BASE").rstrip("/")
    try:
        MS = _ms()
    except ImportError:
        log("WARN 发件箱: 同目录没有 mainsite_sign.py, 不启动")
        return 0
    secret = MS.load_secret()
    if not base or not secret:
        log("WARN 发件箱: 缺 MAINSITE_BASE / MAINSITE_HOOK_SECRET(_FILE), 不启动")
        return 0
    pacer = IdlePacer(float(env("OUTBOX_POLL_SEC", "5")), float(env("OUTBOX_IDLE_POLL_SEC", "30")),
                      float(env("OUTBOX_IDLE_AFTER_SEC", "60")), 0.0)
    total = 0
    while not _stop.is_set():
        try:
            n = outbox_pass(base, secret)
        except Exception as ex:      # 意外（回包形状不对等）：记一行、照常等下一轮 —— 线程不能悄悄死掉
            log("ERROR 发件箱: %r" % (ex,))
            n = -1
        if _outbox_off.is_set():
            break
        if n > 0:
            total += n
            pacer.busy()
        if once:
            return total
        _stop.wait(0.2 if n >= OUTBOX_BATCH else (max(pacer.poll, 10.0) if n < 0 else pacer.wait_sec()))
    return total


BOT_POOL_BATCH = 200                    # 一批几行（每行约 1.4 KB 快照）


def gen_bot_pool(proj: str, out_path: str, timeout_sec: int = 600) -> dict:
    """调 Godot 生成一份机器人池（同一个版本的代码），返回解析后的 json；失败抛 RuntimeError。"""
    wdir = os.path.join(env("WORK_DIR", "/var/lib/turtle-referee"), "botpool")
    ud = os.path.join(wdir, "userdata")
    shutil.rmtree(ud, ignore_errors=True)
    os.makedirs(ud, exist_ok=True)
    e = dict(os.environ)
    e.pop("SUPABASE_SERVICE_KEY", None)
    e.update({"XDG_DATA_HOME": ud, "APPDATA": ud, "HOME": ud, "TURTLE_SUPABASE": " ", "TURTLE_BACKEND": " "})
    if os.path.exists(out_path):
        os.remove(out_path)
    cmd = [env("GODOT_BIN", "/opt/godot/godot"), "--headless", "--audio-driver", "Dummy", "--path", proj, SCENE,
           "--quit-after", QUIT_AFTER_FRAMES, "--", "--bot-pool=" + out_path]
    r = subprocess.run(cmd, env=e, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout_sec)
    if r.returncode != 0 or not os.path.exists(out_path):
        raise RuntimeError("godot rc=%s %s" % (r.returncode, (r.stdout + r.stderr)[-400:]))
    with open(out_path, encoding="utf-8") as f:
        pool = json.load(f)
    if not isinstance(pool, dict) or not isinstance(pool.get("rows"), list) or not pool["rows"] \
            or int(pool.get("rules_ver", 0)) < 1:
        raise RuntimeError("池子形状不对: %s" % out_path)
    return pool


def ranked_pool_supported(proj: str) -> bool:
    """这一版工程会不会生成积分赛池（bot_pool.gd 里有 generate_ranked = 0.22.7 起）。"""
    try:
        with open(os.path.join(proj, "scripts", "referee", "bot_pool.gd"), encoding="utf-8") as f:
            return "static func generate_ranked(" in f.read()
    except OSError:
        return False


def gen_ranked_pool(proj: str, out_path: str, timeout_sec: int = 600) -> dict:
    """调 Godot 生成积分赛池（--ranked-pool=），返回解析后的 json；失败抛 RuntimeError。参数与 gen_bot_pool 同一套。"""
    wdir = os.path.join(env("WORK_DIR", "/var/lib/turtle-referee"), "botpool")
    ud = os.path.join(wdir, "userdata-ranked")
    shutil.rmtree(ud, ignore_errors=True)
    os.makedirs(ud, exist_ok=True)
    e = dict(os.environ)
    e.pop("SUPABASE_SERVICE_KEY", None)
    e.update({"XDG_DATA_HOME": ud, "APPDATA": ud, "HOME": ud, "TURTLE_SUPABASE": " ", "TURTLE_BACKEND": " "})
    if os.path.exists(out_path):
        os.remove(out_path)
    cmd = [env("GODOT_BIN", "/opt/godot/godot"), "--headless", "--audio-driver", "Dummy", "--path", proj, SCENE,
           "--quit-after", QUIT_AFTER_FRAMES, "--", "--ranked-pool=" + out_path]
    r = subprocess.run(cmd, env=e, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout_sec)
    if r.returncode != 0 or not os.path.exists(out_path):
        raise RuntimeError("godot rc=%s %s" % (r.returncode, (r.stdout + r.stderr)[-400:]))
    with open(out_path, encoding="utf-8") as f:
        pool = json.load(f)
    if not isinstance(pool, dict) or int(pool.get("rules_ver", 0)) < 1             or not isinstance(pool.get("seed_rows"), list) or not pool["seed_rows"]             or not isinstance(pool.get("bot_rows"), list) or not pool["bot_rows"]:
        raise RuntimeError("积分赛池形状不对: %s" % out_path)
    return pool


def upload_ranked_pool(pool: dict) -> dict:
    """两种（seed / bot）各自分批上传；每种第一批 p_replace = true。返回 {seed: 回包, bot: 回包}（含 total）。"""
    out = {}
    for kind, key in (("seed", "seed_rows"), ("bot", "bot_rows")):
        rows = pool[key]
        last = {}
        for i in range(0, len(rows), BOT_POOL_BATCH):
            last = rpc("referee_ranked_pool_load", {"p_client_version": str(pool["client_version"]),
                                                    "p_rules_ver": int(pool["rules_ver"]), "p_kind": kind,
                                                    "p_rows": rows[i:i + BOT_POOL_BATCH], "p_replace": i == 0},
                       timeout=60.0) or {}
            if not last.get("ok") or int(last.get("rejected", 0)) > 0:
                raise RuntimeError("积分赛池 %s 第 %d 批被拒: %s" % (kind, i // BOT_POOL_BATCH, json.dumps(last, ensure_ascii=False)))
        if int(last.get("total", -1)) != len(rows):
            raise RuntimeError("积分赛池 %s 上传后行数 %s ≠ 生成的 %d" % (kind, last.get("total"), len(rows)))
        out[kind] = last
    return out


def upload_bot_pool(pool: dict) -> dict:
    """分批上传；第一批 p_replace = true（清掉同规则版本的旧池）。返回最后一批的回包（含 total）。"""
    rows = pool["rows"]
    last = {}
    for i in range(0, len(rows), BOT_POOL_BATCH):
        last = rpc("referee_bot_pool_load", {"p_client_version": str(pool["client_version"]),
                                              "p_rules_ver": int(pool["rules_ver"]),
                                              "p_rows": rows[i:i + BOT_POOL_BATCH], "p_replace": i == 0}, timeout=60.0) or {}
        if not last.get("ok") or int(last.get("rejected", 0)) > 0:
            raise RuntimeError("第 %d 批被拒: %s" % (i // BOT_POOL_BATCH, json.dumps(last, ensure_ascii=False)))
    if int(last.get("total", -1)) != len(rows):
        raise RuntimeError("上传后池子行数 %s ≠ 生成的 %d" % (last.get("total"), len(rows)))
    return last


def bot_pool_cmd(versions: dict, only: str, out_dir: str) -> int:
    targets = {v: p for v, p in versions.items() if not only or v == only}
    if not targets:
        print("没有要生成的版本（VERSIONS_DIR=%s, --version=%s）" % (env("VERSIONS_DIR", "/opt/turtle"), only))
        return 2
    rc = 0
    for ver, proj in sorted(targets.items()):
        path = os.path.join(out_dir or os.path.join(env("WORK_DIR", "/var/lib/turtle-referee"), "botpool"),
                            "bot_pool_%s.json" % ver)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        try:
            pool = gen_bot_pool(proj, path)
            if str(pool.get("client_version")) != ver:
                raise RuntimeError("生成的版本 %s ≠ 工程版本 %s" % (pool.get("client_version"), ver))
            if out_dir:
                log("bot-pool %s: rules_ver=%s rows=%d → %s（只写文件）" % (ver, pool["rules_ver"], len(pool["rows"]), path))
            else:
                r = upload_bot_pool(pool)
                log("bot-pool %s: rules_ver=%s rows=%d 上传完 → %s" % (ver, pool["rules_ver"], len(pool["rows"]), json.dumps(r)))
        except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired, urllib.error.URLError) as ex:
            log("ERROR bot-pool %s: %s" % (ver, ex))
            rc = 1
        ## 积分赛池（2026-11-01 · 迁移 20261101d）：0.22.7 之前的工程没有生成器 ⇒ 跳过这一半（它们也不会有积分赛裁判局）
        if not ranked_pool_supported(proj):
            log("ranked-pool %s: 这一版工程没有 generate_ranked, 跳过" % ver)
            continue
        rpath = os.path.join(os.path.dirname(path), "ranked_pool_%s.json" % ver)
        try:
            rpool = gen_ranked_pool(proj, rpath)
            if str(rpool.get("client_version")) != ver:
                raise RuntimeError("生成的版本 %s ≠ 工程版本 %s" % (rpool.get("client_version"), ver))
            if out_dir:
                log("ranked-pool %s: rules_ver=%s seeds=%d bots=%d → %s（只写文件）" % (
                    ver, rpool["rules_ver"], len(rpool["seed_rows"]), len(rpool["bot_rows"]), rpath))
                continue
            r = upload_ranked_pool(rpool)
            log("ranked-pool %s: rules_ver=%s seeds=%d bots=%d 上传完 → %s" % (
                ver, rpool["rules_ver"], len(rpool["seed_rows"]), len(rpool["bot_rows"]), json.dumps(r)))
        except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired, urllib.error.URLError) as ex:
            log("ERROR ranked-pool %s: %s" % (ver, ex))
            rc = 1
    return rc


def health_problems(b: dict) -> list:
    """referee_backlog 回包 → 要报警的问题（空 = 健康）。"""
    out = []
    if int((b or {}).get("oldest_pending_sec", 0)) > HEALTH_MAX_PENDING_SEC:
        out.append("积压: 最老的任务等了 %s 秒" % (b or {}).get("oldest_pending_sec"))
    ws = (b or {}).get("workers") or []
    if not ws or min(int(w.get("seen_sec", 1 << 30)) for w in ws) > HEALTH_MAX_HEARTBEAT_SEC:
        out.append("心跳: 没有裁判在线")
    ## 20261020c: 周六开着而某个启用版本的机器人池是空的 ⇒ 那个版本的玩家挑不到机器人就开不了战
    if (b or {}).get("gauntlet_on"):
        for p in (b or {}).get("bot_pool") or []:
            if int(p.get("rows", 0)) <= 0:
                out.append("机器人池空: 版本 %s（rules_ver=%s）—— 跑 referee_poller.py --bot-pool" % (
                    p.get("client_version"), p.get("rules_ver")))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="服务器裁判轮询器")
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--local")
    ap.add_argument("--out")
    ap.add_argument("--health", action="store_true")
    ap.add_argument("--versions", action="store_true")
    ap.add_argument("--bot-pool", action="store_true")
    ap.add_argument("--version", default="")
    ap.add_argument("--outbox-once", action="store_true", help="龟投发件箱只发一批就退（手测；不看 MAINSITE_OUTBOX 开关）")
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
    if a.bot_pool and a.out:
        return bot_pool_cmd(versions, a.version, a.out)      # 只写文件: 不需要钥匙
    if not env("SUPABASE_URL") or not env("SUPABASE_SERVICE_KEY"):
        print("缺 SUPABASE_URL / SUPABASE_SERVICE_KEY")
        return 2
    if a.bot_pool:
        return bot_pool_cmd(versions, a.version, "")
    if a.health:
        b = rpc("referee_backlog", {})
        print(json.dumps(b, ensure_ascii=False))
        probs = health_problems(b)
        for s in probs:
            log("HEALTH " + s)
        return 1 if probs else 0
    if a.outbox_once:
        print("发件箱: 这一批发了 %d 条" % outbox_loop(once=True))
        return 0
    n = int(env("WORKERS", str(os.cpu_count() or 1)))
    log("referee poller: %d workers, versions=%s, 龟投发件箱=%s" % (
        1 if a.once else n, sorted(versions), "开" if outbox_enabled() and not a.once else "关"))
    signal.signal(signal.SIGTERM, lambda *_: _stop.set())
    signal.signal(signal.SIGINT, lambda *_: _stop.set())
    ts = [threading.Thread(target=worker_loop, args=(i, a.once), daemon=True) for i in range(1 if a.once else n)]
    if outbox_enabled() and not a.once:
        ts.append(threading.Thread(target=outbox_loop, daemon=True))
    for t in ts:
        t.start()
    for t in ts:
        while t.is_alive():
            t.join(1.0)
    log("referee poller: stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
