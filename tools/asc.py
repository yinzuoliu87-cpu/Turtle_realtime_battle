# -*- coding: utf-8 -*-
"""tools/asc.py —— TestFlight 提审（App Store Connect API）（2026-11-02 · 方案书 20261102-文件管理与发版流程重整 §4.2 P2）。

此前这一步只活在会话临时目录里（asc.py + 9 份 asc_submit_* 变体），出过的事：
  · 11-02 422 ANOTHER_BUILD_IN_REVIEW：同版本旧构建 1401 还在审，新构建提不进去
  · 0.22.3 的构建从没提审；本次更新内容的换行被 heredoc 吞掉
⇒ 收成一条命令，每步先查再做、做完回读；`--dry-run` 只发 GET（代码里断言：演练中发写请求直接抛异常）。

  status [<版本>]                     这一版每个构建：构建号 / processingState / expired / betaReviewState /
                                      externalBuildState / 在不在公开测试组 / 有没有中文更新说明；不给版本 ⇒ 列公开测试组
  submit <版本> [--build N] [--dry-run] [--notes 文件] [--wait-min 90]
        ① 等一份没作废的构建 VALID（默认取最新构建号；--build 指定）
        ② 加进公开测试组
        ③ 本次更新内容（zh-Hans）= CHANGELOG 里这一版那段压成纯文本（### 小标题变一行【…】，上限 4000 字）
        ④ ★先作废【同一版本】里其他还在审（WAITING_FOR_REVIEW / IN_REVIEW）的构建 —— 否则 422 ANOTHER_BUILD_IN_REVIEW
        ⑤ 提交 Beta 版审核，回读 betaReviewState
  expire <构建号> [--ver x.y.z] [--dry-run] [--force]   作废一份构建（不可撤回）
  group-remove <版本> [--dry-run] [--force]             把这一版的构建撤出公开测试组
        ★默认拒绝：组里没有更高版本、已过审、没作废的构建时（撤了公测玩家就没包可装）

凭据只在本机：~/.config/turtle/secrets/asc.json（key_id / issuer / app_id / public_group）
            + ~/.config/turtle/secrets/AuthKey_<key_id>.p8。令牌不打印、不进仓库。
网络默认绕开系统代理（memory fb-local-proxy-corrupts-post-body）；真要走代理设 USE_PROXY=1。
"""
import argparse
import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release as R  # noqa: E402  —— 版本号格式 / CHANGELOG 段落 / 占位记号共用一份

SECRETS = os.path.join(os.path.expanduser("~"), ".config", "turtle", "secrets")
CFG_FILE = os.path.join(SECRETS, "asc.json")
BASE = "https://api.appstoreconnect.apple.com"
WHATS_NEW_MAX = 4000            # 苹果 whatsNew 上限
FOOTER = "遇到问题请在设置 → 问题反馈中提交，或截图反馈。"
IN_REVIEW = ("WAITING_FOR_REVIEW", "IN_REVIEW")

DRY_RUN = False
COUNTS = {"GET": 0, "WRITE": 0}


class DryRunWrite(AssertionError):
    """演练里发了写请求 —— 代码错了，立刻停。"""


class AscError(Exception):
    pass


# ── 凭据与请求 ──────────────────────────────────────────────────
_cfg = None
_tok = (None, 0)


def cfg():
    global _cfg
    if _cfg is None:
        if not os.path.exists(CFG_FILE):
            raise AscError("缺 %s（key_id / issuer / app_id / public_group）" % CFG_FILE)
        with open(CFG_FILE, encoding="utf-8") as f:
            c = json.load(f)
        miss = [k for k in ("key_id", "issuer", "app_id", "public_group") if not c.get(k)]
        if miss:
            raise AscError("%s 缺字段 %s" % (CFG_FILE, miss))
        _cfg = c
    return _cfg


def token():
    global _tok
    if _tok[0] and time.time() < _tok[1] - 60:
        return _tok[0]
    import jwt  # PyJWT + cryptography（ES256）
    c = cfg()
    kf = os.path.join(SECRETS, "AuthKey_%s.p8" % c["key_id"])
    if not os.path.exists(kf):
        raise AscError("缺私钥 %s" % kf)
    with open(kf, encoding="utf-8") as f:
        key = f.read()
    now = int(time.time())
    t = jwt.encode({"iss": c["issuer"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                   key, algorithm="ES256", headers={"kid": c["key_id"], "typ": "JWT"})
    _tok = (t, now + 1200)
    return t


def _opener():
    if os.environ.get("USE_PROXY") == "1":
        return urllib.request.build_opener()
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


def call(method, path, body=None):
    """返回 (HTTP 状态, JSON 或 {})。★DRY_RUN 时只许 GET。"""
    method = method.upper()
    if method != "GET":
        if DRY_RUN:
            raise DryRunWrite("演练中试图发 %s %s —— 演练只许 GET" % (method, path))
        COUNTS["WRITE"] += 1
    else:
        COUNTS["GET"] += 1
    url = path if path.startswith("http") else BASE + path
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with _opener().open(req, timeout=90) as r:
                t = r.read()
                return r.status, (json.loads(t) if t.strip() else {})
        except urllib.error.HTTPError as e:
            t = e.read()
            if e.code == 429 and attempt < 3:
                time.sleep(10 * (attempt + 1))
                continue
            try:
                return e.code, json.loads(t) if t.strip() else {}
            except ValueError:
                return e.code, {"errors": [{"detail": t.decode("utf-8", "replace")[:500]}]}
        except urllib.error.URLError as e:
            if attempt < 3 and method == "GET":
                time.sleep(5)
                continue
            raise AscError("连不上 App Store Connect: %s" % e)
    return 0, {}


def get_ok(path):
    code, js = call("GET", path)
    if code != 200:
        raise AscError("GET %s → %s %s" % (path, code, err(js)))
    return js


def get_all(path):
    out, inc = [], []
    js = get_ok(path)
    while True:
        out += js.get("data") or []
        inc += js.get("included") or []
        nxt = (js.get("links") or {}).get("next")
        if not nxt:
            return out, inc
        js = get_ok(nxt)


def err(js):
    return json.dumps((js or {}).get("errors"), ensure_ascii=False)[:600]


# ── 查询 ────────────────────────────────────────────────────────
def builds_of(ver):
    """这一版的全部构建（按构建号升序）：[{id, number, state, expired, uploaded}]。"""
    c = cfg()
    pvs, _ = get_all("/v1/preReleaseVersions?filter[app]=%s&filter[version]=%s&limit=10" % (c["app_id"], ver))
    rows = []
    for pv in pvs:
        data, _ = get_all("/v1/preReleaseVersions/%s/builds?fields[builds]=version,processingState,expired,uploadedDate"
                          "&limit=200" % pv["id"])
        for b in data:
            at = b.get("attributes") or {}
            rows.append({"id": b["id"], "ver": ver, "number": str(at.get("version")),
                         "state": at.get("processingState"), "expired": bool(at.get("expired")),
                         "uploaded": (at.get("uploadedDate") or "")[:16]})
    return sorted(rows, key=lambda r: _num(r["number"]))


def _num(s):
    try:
        return int(s)
    except (TypeError, ValueError):
        return -1


def review_state(build_id):
    code, js = call("GET", "/v1/builds/%s/betaAppReviewSubmission" % build_id)
    if code == 404:
        return None
    if code != 200:
        raise AscError("查审核状态 %s → %s %s" % (build_id, code, err(js)))
    return ((js.get("data") or {}).get("attributes") or {}).get("betaReviewState")


def beta_detail(build_id):
    code, js = call("GET", "/v1/builds/%s/buildBetaDetail" % build_id)
    if code != 200:
        return None
    return ((js.get("data") or {}).get("attributes") or {}).get("externalBuildState")


def group_builds():
    """公开测试组里的构建：{build_id: (版本, 构建号)}。
    ★不用 /v1/betaGroups/{id}/builds：那个接口不收 include（400 PARAMETER_ERROR.ILLEGAL，
      临时目录里的 asc_ro_group.py 没查状态码，一直以为它能用）⇒ 走 /v1/builds?filter[betaGroups]=…"""
    data, inc = get_all("/v1/builds?filter[betaGroups]=%s&fields[builds]=version,preReleaseVersion"
                        "&include=preReleaseVersion&limit=200" % cfg()["public_group"])
    pv = {x["id"]: (x.get("attributes") or {}).get("version") for x in inc if x.get("type") == "preReleaseVersions"}
    out = {}
    for b in data:
        rid = (((b.get("relationships") or {}).get("preReleaseVersion") or {}).get("data") or {}).get("id")
        out[b["id"]] = (pv.get(rid, "?"), str((b.get("attributes") or {}).get("version")))
    return out


def zh_localization(build_id):
    data, _ = get_all("/v1/builds/%s/betaBuildLocalizations" % build_id)
    for loc in data:
        if (loc.get("attributes") or {}).get("locale") == "zh-Hans":
            return loc
    return None


def build_rows(ver, detail=True):
    """status / submit / prod_flags.force-update 共用：每个构建带上审核状态与组成员。"""
    rows = builds_of(ver)
    grp = group_builds() if rows else {}
    for r in rows:
        r["in_group"] = r["id"] in grp
        r["review"] = review_state(r["id"])
        if detail:
            r["external"] = beta_detail(r["id"])
            loc = zh_localization(r["id"])
            r["whats_new"] = ((loc or {}).get("attributes") or {}).get("whatsNew") or ""
    return rows


def approved_build(ver):
    """prod_flags.force-update 用：这一版里过了 Beta 审核、没作废的构建（最新那份）；没有 ⇒ None。"""
    ok = [r for r in build_rows(ver, detail=False) if r["review"] == "APPROVED" and not r["expired"]]
    return ok[-1] if ok else None


def _pad(s, w):
    """按显示宽度补空格（中文占两格）。"""
    s = str(s)
    n = sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)
    return s + " " * max(1, w - n)


def print_rows(rows):
    cols = [("构建号", 8), ("处理", 12), ("作废", 6), ("审核", 20), ("外部测试状态", 26), ("公开组", 8), ("中文说明", 0)]
    print("  " + "".join(_pad(n, w) if w else n for n, w in cols))
    for r in rows:
        vals = [r["number"], r["state"], "是" if r["expired"] else "否", r.get("review") or "（未提交）",
                r.get("external") or "-", "是" if r.get("in_group") else "否",
                ("%d 字" % len(r["whats_new"])) if r.get("whats_new") else "无"]
        print("  " + "".join(_pad(v, w) if w else str(v) for v, (_, w) in zip(vals, cols)))


# ── 本次更新内容 ────────────────────────────────────────────────
def whats_new_from_changelog(ver, text):
    """CHANGELOG 这一版那段 → 纯文本。返回 (文本, [警告])。"""
    sec = R.changelog_section(text, ver)
    if sec is None:
        raise AscError("CHANGELOG.md 里没有 ## %s 这一段" % ver)
    if R.PLACEHOLDER in sec:
        raise AscError("CHANGELOG.md ## %s 还有「%s」没填" % (ver, R.PLACEHOLDER))
    warn = []
    body = []
    for ln in sec.split("\n"):
        s = ln.strip()
        if not s:
            continue
        if s.startswith("#"):
            body.append("【%s】" % s.lstrip("#").strip())
            continue
        if re.match(r"^[-*+]\s+", s):
            s = "· " + re.sub(r"^[-*+]\s+", "", s)
        s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
        s = re.sub(r"`([^`]*)`", r"\1", s)
        s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
        body.append(s)
    head = "本版更新（%s）：" % ver
    lines = [head] + body
    txt = "\n".join(lines + [FOOTER])
    if len(txt) > WHATS_NEW_MAX:
        keep = [head]
        for s in body:
            if len("\n".join(keep + [s, "……", FOOTER])) > WHATS_NEW_MAX:
                break
            keep.append(s)
        warn.append("超过 %d 字，截到 %d 条（共 %d 条）" % (WHATS_NEW_MAX, len(keep) - 1, len(body)))
        txt = "\n".join(keep + ["……", FOOTER])
    astral = sorted({c for c in txt if ord(c) > 0xFFFF})
    if astral:
        txt = "".join(c for c in txt if ord(c) <= 0xFFFF)
        warn.append("去掉了 BMP 以外的字符（emoji 等）: %s" % " ".join("U+%X" % ord(c) for c in astral))
    odd = sorted({c for c in txt if c in "✕✓★⇒"})
    if odd:
        warn.append("含符号 %s（0.22.6 换掉过「✕」，看一眼要不要改写）" % " ".join(odd))
    return txt, warn


# ── 子命令 ──────────────────────────────────────────────────────
def cmd_status(a):
    if not a.version:
        grp = group_builds()
        print("公开测试组 %s：%d 份构建" % (cfg()["public_group"][:8], len(grp)))
        for bid, (v, n) in sorted(grp.items(), key=lambda x: (R.vtuple(x[1][0]) if R.VER_RE.match(x[1][0] or "") else (0,), _num(x[1][1]))):
            print("  %s (%s) 审核: %s" % (v, n, review_state(bid) or "（未提交）"))
        return 0
    R.vtuple(a.version)
    rows = build_rows(a.version)
    print("%s：%d 份构建" % (a.version, len(rows)))
    if rows:
        print_rows(rows)
    return 0


def _pick(rows, want):
    live = [r for r in rows if not r["expired"]]
    if want:
        hit = [r for r in rows if r["number"] == str(want)]
        if not hit:
            raise AscError("这一版没有构建号 %s（有: %s）" % (want, ", ".join(r["number"] for r in rows) or "无"))
        if hit[0]["expired"]:
            raise AscError("构建 %s 已作废" % want)
        return hit[0]
    return live[-1] if live else None


def cmd_submit(a):
    global DRY_RUN
    DRY_RUN = bool(a.dry_run)
    ver = a.version
    R.vtuple(ver)
    if a.notes:
        with open(a.notes, encoding="utf-8") as f:
            notes = f.read().replace("\r\n", "\n").strip()
        warn = []
        if R.PLACEHOLDER in notes:
            raise AscError("%s 里还有「%s」" % (a.notes, R.PLACEHOLDER))
        if len(notes) > WHATS_NEW_MAX:
            raise AscError("%s 有 %d 字，超过 %d" % (a.notes, len(notes), WHATS_NEW_MAX))
    else:
        notes, warn = whats_new_from_changelog(ver, R.rtext(R.REPO, R.F_CHANGELOG))
    print("本次更新内容（zh-Hans，%d 字，%d 行）:" % (len(notes), notes.count("\n") + 1))
    for ln in notes.split("\n"):
        print("  | " + ln)
    for w in warn:
        print("  ⚠ " + w)

    # ① 等构建
    deadline = time.time() + a.wait_min * 60
    while True:
        rows = builds_of(ver)
        tgt = _pick(rows, a.build)
        print("%s 构建: %s" % (time.strftime("%H:%M"), ", ".join(
            "%s %s%s" % (r["number"], r["state"], " 已作废" if r["expired"] else "") for r in rows) or "无"))
        if tgt and tgt["state"] == "VALID":
            break
        if a.dry_run:
            print("（演练: 目标构建还没 VALID；真跑会每 60 秒查一次、最多等 %d 分钟）" % a.wait_min)
            break
        if tgt and tgt["state"] in ("FAILED", "INVALID"):
            print("✗ 构建 %s 处理失败（%s）" % (tgt["number"], tgt["state"]))
            return 1
        if time.time() > deadline:
            print("✗ 等了 %d 分钟还没有 VALID 的构建" % a.wait_min)
            return 1
        time.sleep(60)
    if not tgt:
        print("✗ 这一版没有没作废的构建")
        return 1
    bid = tgt["id"]
    grp = group_builds()
    for r in rows:
        r["review"] = review_state(r["id"])
    tgt_review = tgt["review"]
    print("目标构建: %s %s（处理 %s，审核 %s，%s公开组）" % (
        ver, tgt["number"], tgt["state"], tgt_review or "未提交", "在" if bid in grp else "不在"))

    # 同版本里还在审的旧构建（④ 的对象）；别的版本在审只提醒
    stale = [r for r in rows if r["id"] != bid and not r["expired"] and r["review"] in IN_REVIEW]
    others = []
    for gid, (gv, gn) in grp.items():
        if gv != ver:
            st = review_state(gid)
            if st in IN_REVIEW:
                others.append("%s (%s) %s" % (gv, gn, st))

    loc = zh_localization(bid)
    cur_notes = ((loc or {}).get("attributes") or {}).get("whatsNew") or ""

    # ★已有的中文说明不拿 CHANGELOG 生成的去盖（可能是手改过的精简版）；要改就显式给 --notes
    write_notes = cur_notes != notes and (not cur_notes.strip() or bool(a.notes))
    plan = []
    if bid not in grp:
        plan.append("② 加进公开测试组")
    if write_notes:
        plan.append("③ %s本次更新内容（现在 %d 字）" % ("改写" if loc else "新建", len(cur_notes)))
    elif cur_notes != notes:
        plan.append("③ 已有 %d 字的中文说明，与上面这份不同 —— 不覆盖（要覆盖用 --notes <文件>）" % len(cur_notes))
    for r in stale:
        plan.append("④ 作废同版本在审的旧构建 %s（%s）" % (r["number"], r["review"]))
    if tgt_review is None:
        plan.append("⑤ 提交 Beta 版审核")
    else:
        plan.append("⑤ 已提交过（%s），不再提交" % tgt_review)
    print("计划:")
    for p in plan:
        print("  · " + p)
    for o in others:
        print("  ⚠ 别的版本有构建在审: %s —— 苹果可能回 422 ANOTHER_BUILD_IN_REVIEW；本工具不动别的版本" % o)
    if a.dry_run:
        assert COUNTS["WRITE"] == 0, "演练里写了 %d 次" % COUNTS["WRITE"]
        print("（演练: GET %d 次，写 0 次）" % COUNTS["GET"])
        return 0

    if bid not in grp:
        code, js = call("POST", "/v1/betaGroups/%s/relationships/builds" % cfg()["public_group"],
                        {"data": [{"type": "builds", "id": bid}]})
        print("② 加进公开测试组: %s %s" % (code, "ok" if code < 300 else err(js)))
        if code >= 300:
            return 1
    if write_notes:
        if loc:
            code, js = call("PATCH", "/v1/betaBuildLocalizations/%s" % loc["id"],
                            {"data": {"type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": notes}}})
        else:
            code, js = call("POST", "/v1/betaBuildLocalizations", {"data": {
                "type": "betaBuildLocalizations", "attributes": {"locale": "zh-Hans", "whatsNew": notes},
                "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        print("③ 本次更新内容: %s %s" % (code, "ok" if code < 300 else err(js)))
        if code >= 300:
            return 1
    for r in stale:
        code, js = call("PATCH", "/v1/builds/%s" % r["id"],
                        {"data": {"type": "builds", "id": r["id"], "attributes": {"expired": True}}})
        print("④ 作废 %s: %s %s" % (r["number"], code, "ok" if code < 300 else err(js)))
        if code >= 300:
            return 1
    if tgt_review is None:
        code, js = call("POST", "/v1/betaAppReviewSubmissions", {"data": {
            "type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        print("⑤ 提交 Beta 版审核: %s %s" % (code, "ok" if code < 300 else err(js)))
        if code >= 300:
            return 1

    # 回读
    st = review_state(bid)
    in_grp = bid in group_builds()
    loc = zh_localization(bid)
    got = ((loc or {}).get("attributes") or {}).get("whatsNew") or ""
    same = bool(got.strip()) and (got == notes or not write_notes)
    left = [r["number"] for r in builds_of(ver) if r["id"] != bid and not r["expired"] and review_state(r["id"]) in IN_REVIEW]
    ok = st in ("WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED") and in_grp and same and not left
    print("回读: 审核 %s / 公开组 %s / 中文说明 %d 字%s / 同版本其他在审 %s  %s" % (
        st, "在" if in_grp else "不在", len(got), "" if same else "（✗ 与要写的不一致）", left or "无", "✓" if ok else "✗"))
    print("（GET %d 次，写 %d 次）" % (COUNTS["GET"], COUNTS["WRITE"]))
    return 0 if ok else 1


def cmd_expire(a):
    global DRY_RUN
    DRY_RUN = bool(a.dry_run)
    c = cfg()
    data, inc = get_all("/v1/builds?filter[app]=%s&filter[version]=%s&fields[builds]=version,processingState,expired,"
                        "preReleaseVersion&include=preReleaseVersion&limit=50" % (c["app_id"], a.build))
    pv = {x["id"]: (x.get("attributes") or {}).get("version") for x in inc if x.get("type") == "preReleaseVersions"}
    rows = []
    for b in data:
        rid = (((b.get("relationships") or {}).get("preReleaseVersion") or {}).get("data") or {}).get("id")
        rows.append((b, pv.get(rid)))
    if a.ver:
        rows = [x for x in rows if x[1] == a.ver]
    if len(rows) != 1:
        print("✗ 构建号 %s 对上 %d 份（%s）—— %s" % (a.build, len(rows), ", ".join(str(v) for _, v in rows) or "无",
                                               "加 --ver 指定版本" if rows else "构建号写错了？"))
        return 1
    b, v = rows[0]
    at = b.get("attributes") or {}
    st = review_state(b["id"])
    in_grp = b["id"] in group_builds()
    print("构建 %s (%s): 处理 %s / 作废 %s / 审核 %s / %s公开组" % (
        v, a.build, at.get("processingState"), "是" if at.get("expired") else "否", st or "未提交", "在" if in_grp else "不在"))
    if at.get("expired"):
        print("已经作废，不用再做")
        return 0
    if in_grp and st == "APPROVED" and not a.force:
        print("✗ 这份已过审且在公开测试组里，作废了公测玩家就装不到它 —— 确定要作废加 --force")
        return 1
    if a.dry_run:
        print("（演练: 会作废这份构建（不可撤回）；GET %d 次，写 0 次）" % COUNTS["GET"])
        return 0
    code, js = call("PATCH", "/v1/builds/%s" % b["id"], {"data": {"type": "builds", "id": b["id"], "attributes": {"expired": True}}})
    print("作废: %s %s" % (code, "ok" if code < 300 else err(js)))
    js2 = get_ok("/v1/builds/%s?fields[builds]=expired" % b["id"])
    ok = bool(((js2.get("data") or {}).get("attributes") or {}).get("expired"))
    print("回读: expired = %s %s" % (ok, "✓" if ok else "✗"))
    return 0 if ok else 1


def cmd_group_remove(a):
    global DRY_RUN
    DRY_RUN = bool(a.dry_run)
    ver = a.version
    R.vtuple(ver)
    grp = group_builds()
    mine = [bid for bid, (v, _) in grp.items() if v == ver]
    print("公开测试组 %d 份构建，其中 %s 有 %d 份: %s" % (len(grp), ver, len(mine), ", ".join(grp[b][1] for b in mine) or "无"))
    if not mine:
        print("不在组里，不用撤")
        return 0
    newer = []
    for bid, (v, n) in grp.items():
        if R.VER_RE.match(v or "") and R.vtuple(v) > R.vtuple(ver) and review_state(bid) == "APPROVED":
            newer.append("%s (%s)" % (v, n))
    print("组里更高版本且已过审的: %s" % (", ".join(newer) or "无"))
    if not newer and not a.force:
        print("✗ 撤了之后公测玩家没有可装的新版 —— 等新版过审再撤（确实要撤加 --force）")
        return 1
    if a.dry_run:
        print("（演练: 会把 %d 份撤出公开测试组；GET %d 次，写 0 次）" % (len(mine), COUNTS["GET"]))
        return 0
    code, js = call("DELETE", "/v1/betaGroups/%s/relationships/builds" % cfg()["public_group"],
                    {"data": [{"type": "builds", "id": b} for b in mine]})
    print("撤出: %s %s" % (code, "ok" if code < 300 else err(js)))
    left = [b for b, (v, _) in group_builds().items() if v == ver]
    print("回读: 组里 %s 还剩 %d 份 %s" % (ver, len(left), "✓" if not left else "✗"))
    return 0 if not left else 1


def main(argv=None):
    R.stdout_utf8()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    x = sp.add_parser("status", help="一版的构建 / 不给版本 ⇒ 公开测试组")
    x.add_argument("version", nargs="?")
    x.set_defaults(fn=cmd_status)
    x = sp.add_parser("submit", help="等 VALID → 进公开组 → 更新内容 → 作废同版本在审旧构建 → 提审")
    x.add_argument("version")
    x.add_argument("--build", help="指定构建号（默认最新）")
    x.add_argument("--notes", help="用这个文件当本次更新内容（默认取 CHANGELOG）")
    x.add_argument("--wait-min", type=int, default=90)
    x.add_argument("--dry-run", action="store_true")
    x.set_defaults(fn=cmd_submit)
    x = sp.add_parser("expire", help="作废一份构建（不可撤回）")
    x.add_argument("build")
    x.add_argument("--ver", help="构建号对上多份时指定版本")
    x.add_argument("--force", action="store_true")
    x.add_argument("--dry-run", action="store_true")
    x.set_defaults(fn=cmd_expire)
    x = sp.add_parser("group-remove", help="把这一版撤出公开测试组")
    x.add_argument("version")
    x.add_argument("--force", action="store_true")
    x.add_argument("--dry-run", action="store_true")
    x.set_defaults(fn=cmd_group_remove)
    a = ap.parse_args(argv)
    try:
        return a.fn(a)
    except (AscError, R.ReleaseError) as e:
        print("✗ %s" % e)
        return 2


if __name__ == "__main__":
    sys.exit(main() or 0)
