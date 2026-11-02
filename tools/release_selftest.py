# -*- coding: utf-8 -*-
"""tools/release_selftest.py —— tools/release.py 的门禁自测（2026-11-02 · 方案书 20261102-文件管理与发版流程重整 §4.2 P1）。

为什么要有：发版脚本以前每版在会话临时目录里复制一份（bump_02xx.py 9 份），漏改一处只能靠门禁事后抓；
0.22.7 漏升 RULES_VER 代价是 tag 挪位、TestFlight 1401 作废、裁判机重装。脚本进了仓库，就得有人守它。

把仓库里版本号相关的 5 个文件拷进临时目录，用 `release.py --root <临时目录>` 真跑，逐字节量：
  ① 五处都改成新版本；② 没改的字节一个不差，插入 / 改写的那几行行尾跟原文件（CRLF / LF 两种都量：第二轮把行尾全翻过来）
  ③ --rules changed ⇒ RULES_VER 恰好 +1、注释在上一行；--rules same ⇒ phase2_config.gd 一字不动
  ④ 缺 --rules / 版本不升 / 五处本来就不一致 / --rules same 而 sim 文件动过（临时 git 仓库）⇒ 拒，且一个字节都不写
  ⑤ tag 的前置检查（假 facts）：已存在的 tag 拒绝挪动、CI 不绿 / 没推送 / 有占位都拒；全好时不拒（分母）
  ⑥ asc.py 演练里发写请求当场抛异常；CHANGELOG → 更新说明的转换；checklist 步骤齐全有序
成功最后一行 `ALL OK`；任何一条不过退出码非 0。只读仓库，写只发生在临时目录。
"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import release as R  # noqa: E402

DATE = "2099-01-02"
FAILS = []
COUNT = [0]
TMPS = []


def ok(name, cond, detail=""):
    COUNT[0] += 1
    print("  [%s] %s%s" % ("PASS" if cond else "FAIL", name, ("  " + str(detail)) if detail else ""))
    if not cond:
        FAILS.append(name)
    return cond


def run(root, *args):
    # GIT_CEILING_DIRECTORIES: 临时目录要是恰好在某个 git 仓库里，别让 release.py 的 git 往上找到它
    env = dict(os.environ, PYTHONIOENCODING="utf-8", GIT_CEILING_DIRECTORIES=os.path.dirname(root))
    r = subprocess.run([sys.executable, os.path.join(TOOLS, "release.py"), "--root", root] + list(args),
                       capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=120)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def flip_eol(b):
    """主要是 CRLF ⇒ 全改 LF；否则全改 CRLF。"""
    crlf = b.count(b"\r\n")
    if crlf * 2 > b.count(b"\n"):
        return b.replace(b"\r\n", b"\n")
    return b.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def make_root(flip=False):
    d = tempfile.mkdtemp(prefix="release_selftest_")
    TMPS.append(d)
    for rel in R.VERSION_FILES:
        with open(os.path.join(REPO, rel), "rb") as f:
            b = f.read()
        if flip:
            b = flip_eol(b)
        dst = os.path.join(d, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(b)
    return d


def snap(root):
    out = {}
    for rel in R.VERSION_FILES:
        with open(os.path.join(root, rel), "rb") as f:
            out[rel] = f.read()
    return out


def first_nl(b):
    i = b.find(b"\n")
    return b"\r\n" if i > 0 and b[i - 1:i] == b"\r" else b"\n"


def check_bytes(tag, before, after, old, new, rules_changed):
    """独立于 release.py 再算一遍「应该变成什么」，逐字节比。"""
    o, n = old.encode(), new.encode()
    # ① project.godot
    b, a = before[R.F_PROJECT], after[R.F_PROJECT]
    k0, k1 = b'config/version="' + o + b'"', b'config/version="' + n + b'"'
    ok("%s ① project.godot 只改 config/version 那一处" % tag, b.count(k0) == 1 and a == b.replace(k0, k1))
    # ③④ 导出预设
    b, a = before[R.F_PRESETS], after[R.F_PRESETS]
    exp = b
    for key in (b"application/short_version", b"version/name"):
        k0, k1 = key + b'="' + o + b'"', key + b'="' + n + b'"'
        ok("%s 导出预设 %s=\"%s\" 原来恰好 1 处" % (tag, key.decode(), old), b.count(k0) == 1, b.count(k0))
        exp = exp.replace(k0, k1)
    ok("%s ③④ 导出预设只改 iOS / Android 两行，其余字节不变" % tag, a == exp)
    ok("%s macOS 预设空的 short_version 没被碰" % tag,
       a.count(b'application/short_version=""') == b.count(b'application/short_version=""') >= 1)
    # ② CHANGELOG
    b, a = before[R.F_CHANGELOG], after[R.F_CHANGELOG]
    pre = a[: len(a) - len(b)]
    nl = first_nl(b)
    ok("%s ② CHANGELOG 原文整段原样留在后面" % tag, a.endswith(b) and len(pre) > 0)
    ok("%s ② CHANGELOG 新标题 `## %s — 日期`" % (tag, new), pre.startswith(("## %s — %s" % (new, DATE)).encode("utf-8") + nl),
       pre[:40])
    ok("%s ② CHANGELOG 骨架行尾 = 原文件（%s）" % (tag, "CRLF" if nl == b"\r\n" else "LF"),
       (pre.count(b"\n") == pre.count(b"\r\n")) if nl == b"\r\n" else (b"\r" not in pre))
    ok("%s ② CHANGELOG 骨架带占位（tag / submit 会拦）" % tag, R.PLACEHOLDER.encode("utf-8") in pre)
    # ⑤ 路线图
    b, a = before[R.F_ROADMAP], after[R.F_ROADMAP]
    anchor = b"- **v" + o + b"**"
    i = b.find(anchor)
    while i > 0 and b[i - 1:i] != b"\n":
        i = b.find(anchor, i + 1)
    ok("%s ⑤ 路线图有上一版那行（分母）" % tag, i >= 0)
    if i >= 0:
        ins = a[i: i + len(a) - len(b)]
        j = b.find(b"\n", i)
        lnl = b"\r\n" if b[j - 1:j] == b"\r" else b"\n"
        ok("%s ⑤ 路线图只在上一版那行之前插一行" % tag, a == b[:i] + ins + b[i:] and ins.count(b"\n") == 1)
        ok("%s ⑤ 路线图新行 `- **v%s**（%s）` 行尾 = 锚点行（%s）" % (tag, new, DATE, "CRLF" if lnl == b"\r\n" else "LF"),
           ins.startswith(b"- **v" + n + b"**") and ins.endswith(lnl) and (lnl == b"\r\n" or b"\r" not in ins), ins[:60])
    # RULES_VER
    b, a = before[R.F_PHASE2], after[R.F_PHASE2]
    if not rules_changed:
        ok("%s --rules same ⇒ phase2_config.gd 一字不动" % tag, a == b)
        return
    m = re.search(rb"(?m)^const RULES_VER := (\d+)(\r?)$", b)
    ok("%s RULES_VER 原来恰好 1 处（分母）" % tag, m is not None and len(re.findall(rb"(?m)^const RULES_VER := ", b)) == 1)
    if m is None:
        return
    rv, cr = int(m.group(1)), m.group(2)
    j = a.find(b"\n", m.start())
    comment = a[m.start(): j + 1]
    exp = b[: m.start()] + comment + b"const RULES_VER := %d" % (rv + 1) + cr + b[m.end():]
    ok("%s RULES_VER %d → %d，注释单独占上一行，其余字节不变" % (tag, rv, rv + 1), a == exp)
    ok("%s RULES_VER 注释带日期与版本、行尾 = 原文件" % tag,
       comment.startswith(("## ★%s %d → %d(%s)" % (DATE, rv, rv + 1, new)).encode("utf-8"))
       and comment.endswith(cr + b"\n") and comment.count(b"\n") == 1, comment[:50])


def bump_round(tag, flip, rules):
    root = make_root(flip=flip)
    before = snap(root)
    old = R.read_places(root)[R.P1]
    new = R.next_patch(old)
    rv0 = R.rules_ver(root)
    print("— %s（行尾%s，--rules %s）: %s → %s" % (tag, "全翻" if flip else "原样", rules, old, new))
    args = ["bump", new, "--rules", rules, "--date", DATE]
    if rules == "same":
        # 临时目录不是 git 仓库 ⇒ 列不出改动 ⇒ 不带确认必须拒
        rc, out = run(root, *args)
        ok("%s --rules same 列不出改动且没 --yes-rules-same ⇒ 拒" % tag, rc != 0, rc)
        ok("%s 被拒时一个字节都没写" % tag, snap(root) == before)
        args.append("--yes-rules-same")
    rc, out = run(root, *args)
    if not ok("%s bump 退出码 0" % tag, rc == 0, rc):
        print(out[-1500:])
    after = snap(root)
    places = R.read_places(root)
    ok("%s 五处全是 %s" % (tag, new), all(places[k] == new for k in R.PLACE_NAMES), places)
    ok("%s RULES_VER %s" % (tag, "+1" if rules == "changed" else "不变"),
       R.rules_ver(root) == rv0 + (1 if rules == "changed" else 0), "%d → %d" % (rv0, R.rules_ver(root)))
    check_bytes(tag, before, after, old, new, rules == "changed")
    ph = R.find_placeholders(root, new)
    want = [R.F_CHANGELOG, R.F_CHANGELOG, R.F_ROADMAP] + ([R.F_PHASE2] if rules == "changed" else [])
    ok("%s 占位都被认出来（CHANGELOG 两行 / 路线图%s）" % (tag, " / RULES_VER 注释" if rules == "changed" else ""),
       sorted(f for f, _ in ph) == sorted(want), ph)
    rc, out = run(root, "bump", R.next_patch(new), "--rules", "changed", "--date", DATE, "--dry-run")
    ok("%s --dry-run 退出码 0 且一个字节都没写" % tag, rc == 0 and snap(root) == after, rc)
    return root, new


def refusals():
    print("— 该拒的都拒，且不写")
    root = make_root()
    before = snap(root)
    old = R.read_places(root)[R.P1]
    new = R.next_patch(old)
    rc, out = run(root, "bump", new)
    ok("缺 --rules ⇒ 拒", rc != 0 and "--rules" in out, rc)
    ok("缺 --rules 时一个字节都没写", snap(root) == before)
    rc, out = run(root, "bump", old, "--rules", "changed")
    ok("版本不升（%s → %s）⇒ 拒" % (old, old), rc != 0, rc)
    rc, out = run(root, "bump", "1.2", "--rules", "changed")
    ok("版本号不是 x.y.z ⇒ 拒", rc != 0, rc)
    rc, out = run(root, "bump", new, "--rules", "same", "--rules-why", "x")
    ok("--rules-why 配 --rules same ⇒ 拒", rc != 0, rc)
    ok("以上被拒时一个字节都没写", snap(root) == before)
    # 五处本来就不一致
    p = os.path.join(root, R.F_PRESETS)
    b = before[R.F_PRESETS].replace(b'version/name="%s"' % old.encode(), b'version/name="0.0.1"')
    with open(p, "wb") as f:
        f.write(b)
    mid = snap(root)
    rc, out = run(root, "bump", new, "--rules", "changed")
    ok("五处本来就不一致（Android 是 0.0.1）⇒ 拒", rc != 0 and "不一致" in out, rc)
    ok("不一致被拒时一个字节都没写", snap(root) == mid)


def git(root, *args):
    return subprocess.run(["git", "-c", "user.name=selftest", "-c", "user.email=selftest@example.invalid",
                           "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false"]
                          + list(args), cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace")


def git_root(extra_rel):
    root = make_root()
    for args in (("init", "-q"), ("config", "core.autocrlf", "false"), ("add", "-A"), ("commit", "-q", "-m", "base")):
        r = git(root, *args)
        if r.returncode != 0:
            return None, r.stderr
    old = R.read_places(root)[R.P1]
    git(root, "tag", "v" + old)
    p = os.path.join(root, extra_rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write("# selftest\n")
    git(root, "add", "-A")
    r = git(root, "commit", "-q", "-m", "change")
    return (root, None) if r.returncode == 0 else (None, r.stderr)


def rules_same_git():
    print("— --rules same 在真 git 仓库里列 sim 改动")
    root, e = git_root("scripts/systems/selftest_probe_system.gd")
    if not ok("临时 git 仓库建起来（分母）", root is not None, e or ""):
        return
    before = snap(root)
    new = R.next_patch(R.read_places(root)[R.P1])
    rc, out = run(root, "bump", new, "--rules", "same", "--date", DATE)
    ok("上个 tag 以来动过 scripts/systems/ ⇒ 不带 --yes-rules-same 拒", rc != 0, rc)
    ok("拒的时候把那个文件列出来", "scripts/systems/selftest_probe_system.gd" in out)
    ok("拒的时候一个字节都没写", snap(root) == before)
    rc, out = run(root, "bump", new, "--rules", "same", "--yes-rules-same", "--date", DATE)
    ok("加 --yes-rules-same ⇒ 过", rc == 0 and R.read_places(root)[R.P1] == new, rc)
    root, e = git_root("docs/selftest_note.md")
    if not ok("临时 git 仓库（只动 docs）建起来", root is not None, e or ""):
        return
    rc, out = run(root, "bump", new, "--rules", "same", "--date", DATE)
    ok("只动了非 sim 文件 ⇒ --rules same 直接过", rc == 0 and R.read_places(root)[R.P1] == new, out[-300:] if rc else rc)


def tag_checks():
    print("— tag 前置检查（假 facts）")
    ver = "9.8.7"
    good = {"ver": ver, "dirty": [], "fetch_err": None, "head": "a" * 40, "origin": "a" * 40,
            "places": {k: ver for k in R.PLACE_NAMES}, "placeholders": [], "local_tag": None, "remote_tag": None,
            "remote_err": None, "ci": ("completed", "success", "https://example.invalid/run")}
    ok("全好 ⇒ 不拒（分母：检查本身不是恒拒）", R.tag_problems(ver, good) == [], R.tag_problems(ver, good))

    def bad(name, **kw):
        f = dict(good, **kw)
        p = R.tag_problems(ver, f)
        ok(name, len(p) >= 1, p[:1])
        return p
    p = bad("本地已有 tag ⇒ 拒", local_tag="b" * 40)
    ok("已有 tag 的拒绝写明「出 9.8.8」（tag 不挪）", any("已存在" in x and "9.8.8" in x for x in p))
    bad("只有远端有 tag ⇒ 也拒", remote_tag="c" * 40)
    bad("查不到远端 tag ⇒ 拒（不当成没有）", remote_err="ssh: timeout")
    bad("CI 还在跑 ⇒ 拒", ci=("in_progress", None, None))
    bad("CI 红 ⇒ 拒", ci=("completed", "failure", None))
    bad("CI 查不到 ⇒ 拒", ci=("error", None, "HTTP 403"))
    bad("HEAD 没推上去 ⇒ 拒", origin="d" * 40)
    bad("工作区有改动 ⇒ 拒", dirty=[" M project.godot"])
    bad("五处有一处不是这个版本 ⇒ 拒", places=dict(good["places"], **{R.P4: "9.8.6"}))
    bad("还有「（待填」⇒ 拒", placeholders=[("CHANGELOG.md", "- （待填）")])


def asc_checks(bumped_root, bumped_ver):
    print("— asc.py（不联网）")
    import asc as A

    def no_net(*_a, **_k):
        raise RuntimeError("selftest 里不许联网")
    # 守卫万一坏了也不能真发出去：令牌与连接都换成桩（本机有真凭据）
    A.token = lambda: "selftest"
    A._opener = no_net
    A.DRY_RUN = True
    n0 = A.COUNTS["WRITE"]
    for m in ("POST", "PATCH", "DELETE"):
        try:
            A.call(m, "/v1/selftest", {"data": {}})
            got = "没抛"
        except A.DryRunWrite:
            got = "DryRunWrite"
        except Exception as e:  # noqa: BLE001
            got = "%s: %s" % (type(e).__name__, e)
        ok("演练里发 %s ⇒ 当场抛 DryRunWrite（发请求之前）" % m, got == "DryRunWrite", got)
    ok("演练里写计数仍为 0", A.COUNTS["WRITE"] == n0)
    A.DRY_RUN = False
    # 自造一段（不读仓库 CHANGELOG：发版途中它的首条可能正带着占位）
    nl = chr(10)
    sample = nl.join(["## 9.9.8 — 2099-01-01", "", "### 界面", "", "- 甲 **加粗** 与 `代码` 与 [链接](http://x)。",
                      "  - 子条目", "", "### 修复", "", "- 乙" + chr(0x1F422) + "。", "", "## 9.9.7 — 2098-12-31", "",
                      "- 上一版不许混进来", ""])
    notes, warn = A.whats_new_from_changelog("9.9.8", sample)
    want = nl.join(["本版更新（9.9.8）：", "【界面】", "· 甲 加粗 与 代码 与 链接。", "· 子条目", "【修复】", "· 乙。", A.FOOTER])
    ok("CHANGELOG 段 → 更新说明：### 变【】、列表变 ·、去 Markdown、去 emoji、不混进上一版", notes == want, repr(notes[:120]))
    ok("去掉 emoji 时给提醒", any("U+1F422" in w for w in warn), warn)
    try:
        A.whats_new_from_changelog(bumped_ver, R.rtext(bumped_root, R.F_CHANGELOG))
        refused = False
    except A.AscError:
        refused = True
    ok("CHANGELOG 段里还有「（待填」⇒ submit 拒", refused)
    big = "## 9.9.9 — 2099-01-01\n\n### 大\n\n" + "".join("- 第 %d 条很长很长很长很长很长很长很长很长很长很长很长很长。\n" % i for i in range(400))
    notes, warn = A.whats_new_from_changelog("9.9.9", big)
    ok("超过 %d 字 ⇒ 截断到上限以内并提醒" % A.WHATS_NEW_MAX, len(notes) <= A.WHATS_NEW_MAX and warn, len(notes))


def checklist_checks():
    print("— checklist")
    root = make_root()
    ver = "9.8.7"
    rc, out = run(root, "checklist", ver)
    p = os.path.join(root, "docs", "releases", ver + ".md")
    ok("checklist 写出 docs/releases/%s.md" % ver, rc == 0 and os.path.exists(p), out[-300:] if rc else "")
    if not os.path.exists(p):
        return
    with open(p, encoding="utf-8") as f:
        t = f.read()
    steps = ["release.py bump %s" % ver, "run-tests.sh", "git push origin main", "release.py tag %s" % ver,
             "asc.py status %s" % ver, "asc.py submit %s" % ver, "deploy.py %s" % ver, "prod_flags.py show",
             "prod_flags.py force-update %s" % ver, "asc.py group-remove"]
    pos = [t.find(s) for s in steps]
    ok("清单 %d 步都在（分母）" % len(steps), all(x >= 0 for x in pos), [s for s, x in zip(steps, pos) if x < 0])
    ok("清单步骤按发版顺序排", pos == sorted(pos), pos)
    ok("清单每步是复选框（≥ %d 个 `- [ ]`）" % len(steps), t.count("- [ ]") >= len(steps), t.count("- [ ]"))
    rc, out = run(root, "checklist", ver)
    ok("已存在的清单不覆盖（没 --force 拒）", rc != 0, rc)


def cleanup():
    def onerr(func, path, _exc):
        try:
            os.chmod(path, stat.S_IWRITE)
            func(path)
        except OSError:
            pass
    for d in TMPS:
        shutil.rmtree(d, onerror=onerr)


def main():
    R.stdout_utf8()
    print("release_selftest：仓库 %s，现在版本 %s" % (REPO, R.read_places(REPO)[R.P1]))
    try:
        broot, bver = bump_round("A 原文件", False, "changed")
        bump_round("B 行尾全翻", True, "same")
        refusals()
        rules_same_git()
        tag_checks()
        asc_checks(broot, bver)
        checklist_checks()
    finally:
        cleanup()
    print("[分母] 断言 %d 条" % COUNT[0])
    if FAILS or COUNT[0] < 50:
        print("FAIL %d / %d: %s" % (len(FAILS), COUNT[0], "; ".join(FAILS[:8]) or "断言数太少（空检查）"))
        return 1
    print("ALL OK — release.py 五处 / 行尾 / RULES_VER / 拒绝路径 / tag 不挪 / asc 演练只读（%d 条）" % COUNT[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
