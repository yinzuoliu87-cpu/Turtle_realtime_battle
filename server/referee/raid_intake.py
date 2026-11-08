#!/usr/bin/env python3
"""偷袭建任务（主站 → 我们 POST /mainsite/raid）的处理（2026-11-09 · 工作线 A2 ·
方案书 docs/plans/20261107-龟战主站对接.md §4.4 / §4.8 · 主站方案 docs/specs/龟战主站整体方案.md §6.2）。

分工（主站对接契约 §2）：A1 的网关 server/referee/mainsite_gateway.py 只做验签与路由，验签通过后调本模块的
`handle_create(body, rpc)`，把返回原样回给主站。本模块不碰 HTTP、不碰密钥。

  body  主站请求体（已解析的 dict）：{raidId, attacker, defender, seed, stake, isRevenge, expireAt}
          raidId    int64 > 0（幂等键：同一个 raidId 重发回同一个 jobId）
          attacker / defender  主站对外编码用户 ID（base62 字串；纯数字 = 内部 ID ⇒ bad_userId）
          seed      int ≥ 0（主站 randInt63() % 1e9；1 ~ 2^53-1 原样当对局种子，0 由服务端另生成）
          stake     int ≥ 0（只记录，App 里不显示）
          isRevenge bool（只记录；不做复仇，用户 11-08）
          expireAt  毫秒；已过 ⇒ expired（主站 §4.8：建任务收到的是排队截止 6 小时）
  rpc   rpc(fn, body) -> 解析后的 JSON（= referee_poller.rpc 的签名；支持 timeout 关键字参数时传 RPC_TIMEOUT_SEC）

返回（主站要求 10 秒内回、业务失败是 HTTP 200 + ok:false）：
  {"ok": true, "jobId": "<字符串>"}   任务已收（含「没有本周阵容 ⇒ 直接 settle void」那几种：照样 ok，结果走发件箱）
  {"ok": false, "error": "<短码>"}     主站立即作废退回押注：
          bad_body / bad_raidId / bad_userId / same_user / bad_seed / bad_stake / bad_isRevenge / bad_expireAt / expired
          （本模块先查，查不过不调数据库）；raid_off / no_referee / raid_conflict（数据库 raid_create 回的）；
          busy（数据库连不上 / 超时 / 回包不对 —— 这时主站当「龟战忙」处理）

★数据库那一侧（迁移 20261109c raid_create）把同样的参数检查再做一遍：直接调 RPC 的也绕不过。
"""
import inspect
import re
import sys
import time

RPC_FN = "raid_create"
RPC_TIMEOUT_SEC = 8.0                   # 主站等 10 秒；留 2 秒给网关自己
INT63_MAX = 2 ** 63 - 1
_USER_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_DIGITS_RE = re.compile(r"^[0-9]+$")
_ERR_RE = re.compile(r"^[A-Za-z_]{1,32}$")
# 主站请求体键 → raid_create 形参（门禁 tools/raid_intake_selftest.py 拿迁移里的形参逐个对）
ARG_MAP = (("raidId", "p_raid_id"), ("attacker", "p_attacker"), ("defender", "p_defender"), ("seed", "p_seed"),
           ("stake", "p_stake"), ("isRevenge", "p_is_revenge"), ("expireAt", "p_expire_at"))


def _log(msg: str) -> None:
    print("%s raid_intake %s" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), msg), file=sys.stderr, flush=True)


def _int(v, lo: int, hi: int):
    """JSON 整数（bool 不算；Go 的 int64 编出来就是整数）。不合法 ⇒ None。"""
    if isinstance(v, bool) or not isinstance(v, int):
        return None
    return v if lo <= v <= hi else None


def _user_ok(v) -> bool:
    return isinstance(v, str) and bool(_USER_RE.match(v)) and not _DIGITS_RE.match(v)


def validate(body, now_ms: int) -> str:
    """"" = 能建；否则是 ok:false 的错误码。纯函数。"""
    if not isinstance(body, dict):
        return "bad_body"
    if _int(body.get("raidId"), 1, INT63_MAX) is None:
        return "bad_raidId"
    if not _user_ok(body.get("attacker")) or not _user_ok(body.get("defender")):
        return "bad_userId"
    if body["attacker"] == body["defender"]:
        return "same_user"
    if _int(body.get("seed"), 0, INT63_MAX) is None:
        return "bad_seed"
    if _int(body.get("stake", 0), 0, INT63_MAX) is None:
        return "bad_stake"
    if not isinstance(body.get("isRevenge", False), bool):
        return "bad_isRevenge"
    exp = _int(body.get("expireAt"), 1, INT63_MAX)
    if exp is None:
        return "bad_expireAt"
    if exp <= now_ms:
        return "expired"
    return ""


def rpc_args(body: dict) -> dict:
    out = {}
    for k, p in ARG_MAP:
        if k == "stake":
            out[p] = body.get(k, 0)
        elif k == "isRevenge":
            out[p] = bool(body.get(k, False))
        else:
            out[p] = body[k]
    return out


def _call(rpc, fn: str, args: dict):
    try:
        params = inspect.signature(rpc).parameters
    except (TypeError, ValueError):
        params = {}
    if "timeout" in params:
        return rpc(fn, args, timeout=RPC_TIMEOUT_SEC)
    return rpc(fn, args)


def handle_create(body, rpc, now_ms=None) -> dict:
    """主站建任务。返回原样回给主站（见文件头）。不抛异常。"""
    now_ms = int(time.time() * 1000) if now_ms is None else int(now_ms)
    err = validate(body, now_ms)
    if err:
        _log("reject %s raidId=%r" % (err, body.get("raidId") if isinstance(body, dict) else None))
        return {"ok": False, "error": err}
    try:
        r = _call(rpc, RPC_FN, rpc_args(body))
    except Exception as ex:          # 连不上 / 超时 / 5xx：主站按「龟战忙」处理（立即作废退回，不挂单）
        _log("rpc error raidId=%s: %r" % (body.get("raidId"), ex))
        return {"ok": False, "error": "busy"}
    if not isinstance(r, dict):
        _log("bad reply raidId=%s: %r" % (body.get("raidId"), r))
        return {"ok": False, "error": "busy"}
    if r.get("ok") is True:
        jid = r.get("jobId")
        if isinstance(jid, int) and not isinstance(jid, bool):
            jid = str(jid)
        if isinstance(jid, str) and jid != "":
            return {"ok": True, "jobId": jid}
        _log("ok without jobId raidId=%s: %r" % (body.get("raidId"), r))
        return {"ok": False, "error": "busy"}
    e = r.get("error")
    return {"ok": False, "error": e if isinstance(e, str) and _ERR_RE.match(e) else "rejected"}
