#!/usr/bin/env python3
"""龟投（主站）接口签名 · 两个方向共用（方案书 docs/plans/20261107-龟战主站对接.md §4.1 / §4.8；主站方案 docs/specs/龟战主站整体方案.md §6）。

网关（server/referee/mainsite_gateway.py，主站 → 我们验签）、发件箱（referee_poller.py outbox_loop，我们 → 主站签名）、
假主站（tools/mock_mainsite.py）三处都 import 这一份，不各写一份。

算法与主站 Go 代码逐字节对齐（turtlebet backend/internal/services/arena_game.go ArenaSign / ArenaVerify）：
  X-Arena-Timestamp: <unix 秒>
  X-Arena-Signature: hex( HMAC-SHA256( secret, FormatInt(ts) + "." + 原始请求体 ) )   ← 小写十六进制
  GET 没有请求体：签 ts + "."（点后面为空）
  验签：secret 去首尾空白，空 ⇒ 拒；时间戳去首尾空白后按 Go strconv.ParseInt(·, 10, 64) 解析（允许 +/- 号与前导零，
        不允许下划线 / 小数 / 超 int64）；|now − ts| > 300 秒 ⇒ 拒（恰好 300 放行）；
        签名去首尾空白、转小写后与 FormatInt(解析出的 ts) 重算的值做常数时间比较
        （★MAC 里拼的是解析后的规范十进制，不是原样的请求头：「+0018…」与「18…」签名相同）。
门禁 tools/mainsite_selftest.py 里有一组用 Go 原函数跑出来的已知向量（签名值 + 20 种验签输入的放行 / 拒绝）。

只用标准库。密钥不打印、不写日志：load_secret() 读环境变量 MAINSITE_HOOK_SECRET，或 MAINSITE_HOOK_SECRET_FILE 指的文件。
"""
import hashlib
import hmac
import os
import re
import time

MAX_SKEW = 300
HDR_TS = "X-Arena-Timestamp"
HDR_SIG = "X-Arena-Signature"
_INT_RE = re.compile(r"^[+-]?[0-9]+$")
_I64_MIN, _I64_MAX = -(1 << 63), (1 << 63) - 1


def _b(body) -> bytes:
    if body is None:
        return b""
    if isinstance(body, str):
        return body.encode("utf-8")
    return bytes(body)


def sign(secret: str, ts: int, body=None) -> str:
    """= Go ArenaSign。body: bytes / str（按 UTF-8）/ None（GET，签 ts + "."）。"""
    mac = hmac.new(secret.encode("utf-8"), digestmod=hashlib.sha256)
    mac.update(str(int(ts)).encode("ascii"))
    mac.update(b".")
    mac.update(_b(body))
    return mac.hexdigest()


def parse_ts(ts_header):
    """= Go strconv.ParseInt(strings.TrimSpace(h), 10, 64)；解析不了返回 None。"""
    s = (ts_header or "").strip()
    if not _INT_RE.match(s):
        return None
    v = int(s)
    if v < _I64_MIN or v > _I64_MAX:
        return None
    return v


def verify(secret: str, ts_header, sig_header, body=None, now=None) -> bool:
    """= Go ArenaVerify（返回 True = 放行）。now 默认取本机时钟（秒）。"""
    secret = (secret or "").strip()
    if not secret:
        return False
    ts = parse_ts(ts_header)
    if ts is None:
        return False
    now_s = int(time.time() if now is None else now)
    if abs(now_s - ts) > MAX_SKEW:
        return False
    want = sign(secret, ts, body)
    got = (sig_header or "").strip().lower()
    return hmac.compare_digest(want.encode("ascii"), got.encode("utf-8", "replace"))


def headers(secret: str, body=None, now=None) -> dict:
    """我们发请求时带的两个头（POST 另由调用方加 Content-Type: application/json）。"""
    ts = int(time.time() if now is None else now)
    return {HDR_TS: str(ts), HDR_SIG: sign(secret, ts, body)}


def load_secret(environ=None) -> str:
    """MAINSITE_HOOK_SECRET（直接给值）优先，其次 MAINSITE_HOOK_SECRET_FILE（文件路径）。没有 ⇒ ""（调用方据此不启用）。"""
    e = os.environ if environ is None else environ
    v = (e.get("MAINSITE_HOOK_SECRET") or "").strip()
    if v:
        return v
    p = (e.get("MAINSITE_HOOK_SECRET_FILE") or "").strip()
    if p:
        try:
            with open(p, encoding="utf-8") as f:
                return f.read().strip()
        except OSError:
            return ""
    return ""
