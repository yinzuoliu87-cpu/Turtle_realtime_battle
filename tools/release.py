# -*- coding: utf-8 -*-
"""tools/release.py —— 发版的仓库这一侧（2026-11-02 · 方案书 docs/plans/20261102-文件管理与发版流程重整.md §4.2 P1）。

形状照 tools/sb_migrate.py：每一步 = 一条命令 + 前置检查 + 演练（--dry-run）+ 回读。

  bump <版本> --rules same|changed [--dry-run]
        改版本号五处（CLAUDE.md §3）+ CHANGELOG 骨架 + 路线图一行：
          ① project.godot          config/version
          ② CHANGELOG.md           顶部新增 `## x.y.z — 日期` 骨架（已有同名条目 ⇒ 拒）
          ③ export_presets.cfg     iOS     application/short_version
          ④ export_presets.cfg     Android version/name
          ⑤ docs/实时版-路线图与待办.md  上一版那行之前插一行 `- **vX**（日期）……`
        ★--rules 必填（0.22.7 漏升 RULES_VER ⇒ tag 挪位、TestFlight 1401 作废、裁判机重装、对手池重生成）：
          changed ⇒ scripts/gamedata/phase2_config.gd 的 `const RULES_VER := N` +1，上方加一行带日期的注释
          same    ⇒ 列出上个 v* tag 以来动过的 sim 路径文件；非空要再加 --yes-rules-same 才写
        每个文件按字节读写，行尾（仓库 CRLF / LF 混用）原样保留；写完回读五处。
  checklist <版本>
        生成 docs/releases/<版本>.md 发版清单（每步带命令与回读）。已存在 ⇒ 拒（--force 覆盖）。
  tag <版本> [--dry-run]
        前置检查：工作区干净（不算未跟踪）、HEAD == origin/main（先 fetch）、五处 == 版本、
        CHANGELOG / 路线图 / RULES_VER 注释里没有「（待填」、CI tests.yml 在 HEAD 上 success、
        tag 本地与远端都不存在（★已存在的 tag 绝不挪：出下一个补丁号）。
        全过 ⇒ `git tag -a` + 只推这一个 tag（一次推两个会互相覆盖 TestFlight 包，10-08 踩过）→ 回读远端。

--root <目录>：对另一份仓库副本操作（tools/release_selftest.py 用临时目录跑 bump）。
★本工具不碰正式服、不碰苹果；那两步是 tools/asc.py / tools/prod_flags.py / tools/deploy.py。
"""
import argparse
import datetime
import difflib
import fnmatch
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GH_REPO = "yinzuoliu87-cpu/Turtle_realtime_battle"
GH_WORKFLOW = "tests.yml"

F_PROJECT = "project.godot"
F_PRESETS = "export_presets.cfg"
F_CHANGELOG = "CHANGELOG.md"
F_ROADMAP = "docs/实时版-路线图与待办.md"
F_PHASE2 = "scripts/gamedata/phase2_config.gd"
VERSION_FILES = [F_PROJECT, F_PRESETS, F_CHANGELOG, F_ROADMAP, F_PHASE2]

## 导出预设里要改的两项：(平台, 键)。★macOS 预设也有一条 application/short_version（空值），不动它。
PRESET_KEYS = [("iOS", "application/short_version"), ("Android", "version/name")]

## `--rules same` 时要人看一眼的 sim 路径（会改变对局结果的代码 / 数据都在这里）
SIM_GLOBS = [
    "scripts/systems/*",
    "scripts/scenes/RealtimeBattle3DScene.gd",
    "scripts/scenes/battle/*",
    "scripts/gamedata/*",
    "data/*.json",
    "autoload/*",
]

## 骨架里的占位记号：tag / asc.py submit 见到它就拒（没填完的说明不许发出去）
PLACEHOLDER = "（待填"

P1 = "① project.godot config/version"
P2 = "② CHANGELOG.md 首条"
P3 = "③ export_presets.cfg iOS application/short_version"
P4 = "④ export_presets.cfg Android version/name"
P5 = "⑤ 路线图首条"
PLACE_NAMES = [P1, P2, P3, P4, P5]

VER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


class ReleaseError(Exception):
    """前置检查没过 —— 不写任何文件。"""


# ── 小工具 ──────────────────────────────────────────────────────
def stdout_utf8():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass


def vtuple(v):
    m = VER_RE.match(v or "")
    if not m:
        raise ReleaseError("版本号要形如 x.y.z（三段数字，不带 v）: %r" % v)
    return tuple(int(x) for x in m.groups())


def next_patch(v):
    a, b, c = vtuple(v)
    return "%d.%d.%d" % (a, b, c + 1)


def rbytes(root, rel):
    p = os.path.join(root, rel)
    if not os.path.exists(p):
        raise ReleaseError("缺文件 %s" % p)
    with open(p, "rb") as f:
        return f.read()


def rtext(root, rel):
    return rbytes(root, rel).decode("utf-8")


def write_atomic(root, rel, data):
    p = os.path.join(root, rel)
    tmp = p + ".release-tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, p)


def line_nl(line):
    """split('\\n') 之后的一行：以 \\r 结尾 ⇒ 这一行原来是 CRLF。"""
    return "\r\n" if line.endswith("\r") else "\n"


def first_line_nl(text):
    i = text.find("\n")
    if i <= 0:
        return "\n"
    return "\r\n" if text[i - 1] == "\r" else "\n"


# ── 导出预设：按 [preset.N] 段找平台，再在 [preset.N.options] 里找键 ──
def preset_lines_for(lines, platform, key):
    plat = {}
    cur = None
    hits = []
    for i, ln in enumerate(lines):
        s = ln.rstrip("\r")
        m = re.match(r"^\[preset\.(\d+)(\.options)?\]\s*$", s)
        if m:
            cur = (m.group(1), m.group(2) is not None)
            continue
        if s.startswith("["):
            cur = None
            continue
        if cur is None:
            continue
        if not cur[1]:
            mp = re.match(r'^platform="([^"]*)"', s)
            if mp:
                plat[cur[0]] = mp.group(1)
        elif s.startswith(key + "="):
            hits.append((cur[0], i))
    return [i for p, i in hits if plat.get(p) == platform]


def preset_value(lines, platform, key):
    idx = preset_lines_for(lines, platform, key)
    if len(idx) != 1:
        return None, idx
    m = re.match(r'^%s="([^"]*)"' % re.escape(key), lines[idx[0]].rstrip("\r"))
    return (m.group(1) if m else None), idx


# ── 五处 ────────────────────────────────────────────────────────
def read_places(root):
    """{处名: 版本串或 None}。"""
    out = {}
    m = re.search(r'^config/version="([^"]*)"', rtext(root, F_PROJECT), re.M)
    out[P1] = m.group(1) if m else None
    m = re.search(r"^##\s+(\d+\.\d+\.\d+)", rtext(root, F_CHANGELOG), re.M)
    out[P2] = m.group(1) if m else None
    lines = rtext(root, F_PRESETS).split("\n")
    out[P3] = preset_value(lines, "iOS", "application/short_version")[0]
    out[P4] = preset_value(lines, "Android", "version/name")[0]
    m = re.search(r"^- \*\*v(\d+\.\d+\.\d+)\*\*", rtext(root, F_ROADMAP), re.M)
    out[P5] = m.group(1) if m else None
    return out


def rules_ver(root):
    ms = re.findall(r"(?m)^const RULES_VER := (\d+)\r?$", rtext(root, F_PHASE2))
    if len(ms) != 1:
        raise ReleaseError("%s 里 `const RULES_VER := N` 要恰好 1 处，实际 %d 处" % (F_PHASE2, len(ms)))
    return int(ms[0])


def changelog_section(text, ver):
    """CHANGELOG 里 `## ver` 那一段（不含标题行）；没有 ⇒ None。"""
    m = re.search(r"(?m)^##\s+%s(?:\s.*)?\r?$" % re.escape(ver), text)
    if not m:
        return None
    rest = text[m.end():]
    n = re.search(r"(?m)^##\s+\d+\.\d+\.\d+", rest)
    return rest[: n.start()] if n else rest


def find_placeholders(root, ver):
    """发出去之前不许还留着骨架占位。返回 [(在哪, 那一行)]。"""
    out = []
    sec = changelog_section(rtext(root, F_CHANGELOG), ver)
    if sec is None:
        out.append((F_CHANGELOG, "没有 ## %s 这一段" % ver))
    else:
        for ln in sec.split("\n"):
            if PLACEHOLDER in ln:
                out.append((F_CHANGELOG, ln.strip()))
    for ln in rtext(root, F_ROADMAP).split("\n"):
        if ln.startswith("- **v%s**" % ver) and PLACEHOLDER in ln:
            out.append((F_ROADMAP, ln.strip()[:80]))
    for ln in rtext(root, F_PHASE2).split("\n"):
        if PLACEHOLDER in ln:   # RULES_VER 上方那行注释本身不含「RULES_VER」字样 —— 整个文件里有占位就算
            out.append((F_PHASE2, ln.strip()[:80]))
    return out


# ── git ─────────────────────────────────────────────────────────
def git(root, *args, check=True, timeout=120):
    r = subprocess.run(["git", "-c", "core.quotepath=off"] + list(args), cwd=root,
                       capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    if check and r.returncode != 0:
        raise ReleaseError("git %s 失败: %s" % (" ".join(args), (r.stderr or r.stdout).strip()[:400]))
    return r


def sim_changes(root):
    """上个 v* tag 以来（含工作区未提交、未跟踪）动过的 sim 路径文件。返回 (tag, [文件], 错误或 None)。"""
    try:
        tag = git(root, "describe", "--tags", "--match", "v*", "--abbrev=0").stdout.strip()
        names = set(git(root, "diff", "--name-only", tag).stdout.split("\n"))
        names |= set(git(root, "ls-files", "--others", "--exclude-standard").stdout.split("\n"))
    except (ReleaseError, OSError, subprocess.SubprocessError) as e:
        return None, [], str(e)
    hit = sorted(n for n in names if n and any(fnmatch.fnmatchcase(n, g) for g in SIM_GLOBS))
    return tag, hit, None


# ── bump ────────────────────────────────────────────────────────
def plan_bump(root, new, rules, date, why=None):
    """算出每个文件的新字节（不写）。返回 ({相对路径: 新字节}, 旧版本, (旧 RULES_VER, 新 RULES_VER))。"""
    vtuple(new)
    cur = read_places(root)
    old = cur[P1]
    if old is None:
        raise ReleaseError("project.godot 里读不到 config/version")
    bad = ["%s = %s" % (k, cur[k]) for k in PLACE_NAMES if cur[k] != old]
    if bad:
        raise ReleaseError("五处版本号现在就不一致（以 project.godot 的 %s 为准）—— 先手工对齐再升:\n    %s"
                           % (old, "\n    ".join(bad)))
    if vtuple(new) <= vtuple(old):
        raise ReleaseError("新版本 %s 不大于现在的 %s" % (new, old))
    out = {}

    # ① project.godot
    b = rbytes(root, F_PROJECT)
    o, w = ('config/version="%s"' % old).encode(), ('config/version="%s"' % new).encode()
    if b.count(o) != 1:
        raise ReleaseError("%s 里 %s 要恰好 1 处，实际 %d 处" % (F_PROJECT, o.decode(), b.count(o)))
    out[F_PROJECT] = b.replace(o, w)

    # ③④ 导出预设（只改那一行里的值，行尾原样）
    lines = rtext(root, F_PRESETS).split("\n")
    for plat, key in PRESET_KEYS:
        val, idx = preset_value(lines, plat, key)
        if len(idx) != 1 or val != old:
            raise ReleaseError("%s 里 %s 预设的 %s 要恰好 1 条且 = %s，实际 %d 条 / 值 %r" % (
                F_PRESETS, plat, key, old, len(idx), val))
        lines[idx[0]] = lines[idx[0]].replace('%s="%s"' % (key, old), '%s="%s"' % (key, new), 1)
    out[F_PRESETS] = "\n".join(lines).encode("utf-8")

    # ② CHANGELOG 骨架（换行跟文件走）
    t = rtext(root, F_CHANGELOG)
    if re.search(r"(?m)^##\s+%s(\s|$)" % re.escape(new), t):
        raise ReleaseError("CHANGELOG.md 里已经有 ## %s 这一条（同一版写两遍 verify_version 会红）" % new)
    nl = first_line_nl(t)
    skel = nl.join([
        "## %s — %s" % (new, date),
        "",
        "### %s：分类小标题，如「界面」「修复」）" % PLACEHOLDER,
        "",
        "- %s：玩家看得懂的一句话，照下面已有条目的写法）" % PLACEHOLDER,
        "",
        "",
    ])
    out[F_CHANGELOG] = (skel + t).encode("utf-8")

    # ⑤ 路线图：插在上一版那行之前，行尾跟那一行走
    t = rtext(root, F_ROADMAP)
    if re.search(r"(?m)^- \*\*v%s\*\*" % re.escape(new), t):
        raise ReleaseError("路线图里已经有 - **v%s** 这一行" % new)
    m = re.search(r"(?m)^- \*\*v%s\*\*" % re.escape(old), t)
    if not m:
        raise ReleaseError("路线图里找不到上一版那行 `- **v%s**`（新行插在它前面）" % old)
    eol = t.find("\n", m.start())
    nl = "\r\n" if eol > 0 and t[eol - 1] == "\r" else "\n"
    road = "- **v%s**（%s）……%s：本版要点 / 方案书 / 门禁）%s" % (new, date, PLACEHOLDER, nl)
    out[F_ROADMAP] = (t[: m.start()] + road + t[m.start():]).encode("utf-8")

    # RULES_VER
    rv = (None, None)
    if rules == "changed":
        t = rtext(root, F_PHASE2)
        ms = list(re.finditer(r"(?m)^const RULES_VER := (\d+)(\r?)$", t))
        if len(ms) != 1:
            raise ReleaseError("%s 里 `const RULES_VER := N` 要恰好 1 处，实际 %d 处" % (F_PHASE2, len(ms)))
        m = ms[0]
        n = int(m.group(1))
        cr = m.group(2)
        reason = why or "%s：哪些改动改变了对局结果）" % PLACEHOLDER
        if "\n" in reason or "\r" in reason:
            raise ReleaseError("--rules-why 只能一行")
        comment = "## ★%s %d → %d(%s): %s" % (date, n, n + 1, new, reason)
        t2 = t[: m.start()] + comment + cr + "\n" + "const RULES_VER := %d" % (n + 1) + cr + t[m.end():]
        out[F_PHASE2] = t2.encode("utf-8")
        rv = (n, n + 1)
    return out, old, rv


def print_diff(root, rel, new_bytes):
    a = rtext(root, rel).split("\n")
    b = new_bytes.decode("utf-8").split("\n")
    n = 0
    for ln in difflib.unified_diff(a, b, lineterm="", n=0):
        if ln.startswith(("---", "+++", "@@")):
            continue
        s = ln.rstrip("\r")
        print("      %s%s" % (s[:150], " …" if len(s) > 150 else ""))
        n += 1
    return n


def cmd_bump(a):
    root = os.path.abspath(a.root)
    new = a.version
    vtuple(new)
    date = a.date or datetime.date.today().isoformat()
    if a.rules_why and a.rules != "changed":
        raise ReleaseError("--rules-why 只配 --rules changed")
    print("仓库: %s" % root)
    if a.rules == "same":
        tag, files, err = sim_changes(root)
        if err:
            print("  ⚠ 列不出上个 tag 以来的改动: %s" % err)
        else:
            print("  上个 tag %s 以来动过的 sim 路径文件 %d 个（分母: %s）:" % (tag, len(files), " ".join(SIM_GLOBS)))
            for f in files:
                print("    · %s" % f)
        if (err or files) and not a.yes_rules_same:
            print("✗ --rules same 但%s —— 逐个确认这些改动不改变对局结果后加 --yes-rules-same；"
                  "改变了就用 --rules changed" % ("列不出改动" if err else "上面这些 sim 文件动过"))
            return 1
    edits, old, rv = plan_bump(root, new, a.rules, date, a.rules_why)
    print("版本 %s → %s（%s）; RULES_VER %s" % (old, new, date,
          "%d → %d" % rv if a.rules == "changed" else "不动（--rules same）"))
    for rel in VERSION_FILES:
        if rel in edits:
            print("  %s:" % rel)
            print_diff(root, rel, edits[rel])
    if a.dry_run:
        print("（演练: 没有写任何文件）")
        return 0
    for rel, data in edits.items():
        write_atomic(root, rel, data)
    # 回读
    cur = read_places(root)
    bad = ["%s = %s" % (k, cur[k]) for k in PLACE_NAMES if cur[k] != new]
    for rel, data in edits.items():
        if rbytes(root, rel) != data:
            bad.append("%s 回读字节与写入不同" % rel)
    if a.rules == "changed" and rules_ver(root) != rv[1]:
        bad.append("RULES_VER 回读 %d ≠ %d" % (rules_ver(root), rv[1]))
    if bad:
        print("✗ 回读不一致:\n    " + "\n    ".join(bad))
        return 1
    print("回读: 五处 = %s%s" % (new, "；RULES_VER = %d" % rv[1] if rv[1] is not None else ""))
    print("下一步: 填 CHANGELOG / 路线图%s里的「%s」→ python tools/release.py checklist %s" % (
        " / RULES_VER 注释" if a.rules == "changed" and not a.rules_why else "", PLACEHOLDER, new))
    return 0


# ── checklist ───────────────────────────────────────────────────
CHECKLIST = """# 发版清单 · v{ver}

生成：{date}（`python tools/release.py checklist {ver}`）　上一版：v{prev}　下一个补丁号：{nxt}
按顺序做，每步回读对上了才打勾；哪步不过就停在那一步。tag 打出去就不再挪：出了问题出 {nxt}。

## 1. 版本号

- [ ] `python tools/release.py bump {ver} --rules same|changed --dry-run` 看改动，再去掉 `--dry-run` 真跑
  - `--rules changed`：这一版改了会改变对局结果的东西（龟 / 装备数值、技能、羁绊、sim 步进、确定性数学）⇒ `RULES_VER` +1，第 6 步**必须**强制更新
  - `--rules same`：会列出上个 tag 以来动过的 sim 路径文件；非空时逐个看过再加 `--yes-rules-same`
  - 回读：末尾一行「回读: 五处 = {ver}」
- [ ] 填 CHANGELOG.md 的 `## {ver}` 段、路线图 `- **v{ver}**` 那一行（`--rules changed` 时还有 RULES_VER 上方的注释），删掉所有「{ph}」
  - 回读：`tag` 与 `asc.py submit` 见到「{ph}」会拒

## 2. 门禁与推送

- [ ] 本机完整门禁 `bash run-tests.sh`
  - 回读：末尾汇总 0 FAIL、致命报错 0
- [ ] 提交（版本号与 CHANGELOG 单独一个提交：`release: {ver} —— …`）→ `git push origin main`
- [ ] CI `tests.yml` 在这个提交上绿
  - 回读：`python tools/release.py tag {ver} --dry-run` 的「CI」一行是 completed / success

## 3. tag 与 TestFlight

- [ ] `python tools/release.py tag {ver} --dry-run` 全部 ✓
- [ ] `python tools/release.py tag {ver}` —— 只推 `v{ver}` 这一个 tag，触发 `testflight.yml`
  - 回读：末尾「远端 refs/tags/v{ver} → <提交>」= HEAD
- [ ] Actions 里这次 `iOS TestFlight` 跑绿
- [ ] `python tools/asc.py status {ver}`
  - 回读：新构建 processingState = VALID、expired = False

## 4. 提审（公开测试组）

- [ ] `python tools/asc.py submit {ver} --dry-run` —— 看「本次更新内容」全文、要作废的同版本在审旧构建
- [ ] `python tools/asc.py submit {ver}`
  - 回读：betaReviewState = WAITING_FOR_REVIEW（或 IN_REVIEW / APPROVED）、在公开测试组里
  - v{prev} 先留在组里：v{ver} 过审之前公测玩家还要有包可装

## 5. 服务器（裁判机 / 陪练号 / 对手池）

- [ ] `python tools/deploy.py {ver}`（先 `--dry-run`）
- [ ] `python tools/prod_flags.py show`
  - 回读：referee_versions 有 {ver}、enabled、rules_ver = 本版 RULES_VER；gauntlet_bot_pool 这个 rules_ver 2052 行；ranked_pool seed 396 / bot 186

## 6. 苹果审核通过之后

- [ ] `python tools/asc.py status {ver}`
  - 回读：betaReviewState = APPROVED
- [ ] `python tools/prod_flags.py force-update {ver}`（不带 `--yes-prod` 先看计划；用户点头后加 `--yes-prod`）
  - `RULES_VER` 变了 ⇒ **必须**做（旧包与新包打不出同一局）；没变 ⇒ 按需
  - 回读：service_status.min_client_version = {ver}
- [ ] `python tools/asc.py group-remove {prev}`（先 `--dry-run`）
  - 回读：`python tools/asc.py status {prev}` 那一列「公开组」= 否

## 7. 收尾

- [ ] 相关方案书回填上线记录；本清单全部打勾后随下一个提交进仓库
"""


def prev_tag_version(root, ver):
    try:
        tags = git(root, "tag", "-l", "v*").stdout.split()
    except ReleaseError:
        return None
    vs = []
    for t in tags:
        m = VER_RE.match(t[1:])
        if m and vtuple(t[1:]) < vtuple(ver):
            vs.append(t[1:])
    return max(vs, key=vtuple) if vs else None


def cmd_checklist(a):
    root = os.path.abspath(a.root)
    ver = a.version
    vtuple(ver)
    rel = "docs/releases/%s.md" % ver
    p = os.path.join(root, rel)
    if os.path.exists(p) and not a.force:
        print("✗ %s 已存在（打过的勾不覆盖；真要重来加 --force）" % rel)
        return 1
    text = CHECKLIST.format(ver=ver, prev=prev_tag_version(root, ver) or "<上一版>", nxt=next_patch(ver),
                            date=datetime.date.today().isoformat(), ph=PLACEHOLDER)
    if a.dry_run:
        print(text)
        print("（演练: 没有写 %s）" % rel)
        return 0
    os.makedirs(os.path.dirname(p), exist_ok=True)
    write_atomic(root, rel, text.encode("utf-8"))
    n = sum(1 for ln in rbytes(root, rel).decode("utf-8").split("\n") if ln.startswith("- [ ]"))
    print("写好 %s（%d 步）" % (rel, n))
    return 0


# ── tag ─────────────────────────────────────────────────────────
_DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def gh_token():
    """Git 凭据管理器里的 GitHub 令牌（CLAUDE.md §7）。拿不到 ⇒ None（公开仓库匿名也能读，只是限额低）。绝不打印。"""
    env = dict(os.environ, GCM_INTERACTIVE="Never", GIT_TERMINAL_PROMPT="0")
    try:
        r = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                           capture_output=True, text=True, timeout=30, env=env)
    except (OSError, subprocess.SubprocessError):
        return None
    for ln in r.stdout.splitlines():
        if ln.startswith("password="):
            return ln[len("password="):].strip() or None
    return None


def gh_get(path):
    hdr = {"Accept": "application/vnd.github+json", "User-Agent": "turtle-release"}
    tok = gh_token()
    if tok:
        hdr["Authorization"] = "Bearer " + tok
    req = urllib.request.Request("https://api.github.com" + path, headers=hdr)
    try:
        with _DIRECT.open(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError:
        raise
    except urllib.error.URLError:
        # 直连不通再走系统代理（只读 GET；代理改写的是 POST body，见 memory fb-local-proxy-corrupts-post-body）
        with urllib.request.build_opener().open(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8"))


def ci_status(sha):
    """tests.yml 在这个提交上最新一次 run 的 (status, conclusion, 链接)；没有 run ⇒ ('none', None, None)。"""
    js = gh_get("/repos/%s/actions/workflows/%s/runs?head_sha=%s&per_page=20" % (GH_REPO, GH_WORKFLOW, sha))
    runs = [r for r in js.get("workflow_runs", []) if r.get("head_sha") == sha]
    if not runs:
        return ("none", None, None)
    r = max(runs, key=lambda x: (x.get("created_at") or "", x.get("id") or 0))
    return (r.get("status"), r.get("conclusion"), r.get("html_url"))


def gather_tag_facts(root, ver):
    f = {"ver": ver}
    f["dirty"] = [ln for ln in git(root, "status", "--porcelain", "--untracked-files=no").stdout.split("\n") if ln.strip()]
    fr = git(root, "fetch", "--quiet", "origin", "main", check=False, timeout=180)
    f["fetch_err"] = None if fr.returncode == 0 else (fr.stderr or fr.stdout).strip()[:300]
    f["head"] = git(root, "rev-parse", "HEAD").stdout.strip()
    f["origin"] = git(root, "rev-parse", "origin/main", check=False).stdout.strip() or None
    f["places"] = read_places(root)
    f["placeholders"] = find_placeholders(root, ver)
    lt = git(root, "rev-parse", "-q", "--verify", "refs/tags/v%s" % ver, check=False)
    f["local_tag"] = lt.stdout.strip() or None
    rt = git(root, "ls-remote", "--tags", "origin", "refs/tags/v%s" % ver, check=False, timeout=120)
    f["remote_err"] = None if rt.returncode == 0 else (rt.stderr or rt.stdout).strip()[:300]
    f["remote_tag"] = rt.stdout.split()[0] if rt.stdout.strip() else None
    try:
        f["ci"] = ci_status(f["head"])
    except Exception as e:  # noqa: BLE001 —— 网络 / 限额 / JSON，一律记成问题而不是放行
        f["ci"] = ("error", None, str(e)[:300])
    return f


def tag_problems(ver, f):
    """纯函数（tools/release_selftest.py 用假的 facts 量它）：返回 [问题]；空 = 可以打。"""
    probs = []
    if f.get("local_tag") or f.get("remote_tag"):
        probs.append("★tag v%s 已存在（本地 %s / 远端 %s）—— tag 打出去就不再挪"
                     "（0.22.7 挪过一次：TestFlight 1401 作废、裁判机重装）⇒ 出 %s" % (
                         ver, (f.get("local_tag") or "无")[:10], (f.get("remote_tag") or "无")[:10], next_patch(ver)))
    if f.get("remote_err"):
        probs.append("查不到远端 tag: %s" % f["remote_err"])
    if f.get("dirty"):
        probs.append("工作区有未提交的改动 %d 处（未跟踪的不算）: %s" % (len(f["dirty"]), "; ".join(f["dirty"][:5])))
    if f.get("fetch_err"):
        probs.append("git fetch origin main 失败: %s" % f["fetch_err"])
    if not f.get("origin") or f.get("head") != f.get("origin"):
        probs.append("HEAD %s ≠ origin/main %s —— 先推送（tag 要打在 CI 跑过的那个提交上）" % (
            (f.get("head") or "?")[:10], (f.get("origin") or "无")[:10]))
    places = f.get("places") or {}
    bad = ["%s = %s" % (k, places.get(k)) for k in PLACE_NAMES if places.get(k) != ver]
    if bad:
        probs.append("五处版本号不全是 %s: %s" % (ver, "; ".join(bad)))
    if f.get("placeholders"):
        probs.append("还有没填的「%s」%d 处: %s" % (PLACEHOLDER, len(f["placeholders"]),
                                                "; ".join("%s: %s" % x for x in f["placeholders"][:4])))
    st, concl, url = f.get("ci") or ("none", None, None)
    if not (st == "completed" and concl == "success"):
        probs.append("CI %s 在 HEAD 上不是绿的: status=%s conclusion=%s %s" % (GH_WORKFLOW, st, concl, url or ""))
    return probs


def cmd_tag(a):
    root = os.path.abspath(a.root)
    ver = a.version
    vtuple(ver)
    f = gather_tag_facts(root, ver)
    st, concl, url = f["ci"]
    print("tag v%s 前置检查（仓库 %s）" % (ver, root))
    print("  HEAD %s / origin/main %s" % (f["head"][:10], (f["origin"] or "无")[:10]))
    for k in PLACE_NAMES:
        print("  %s %s = %s" % ("✓" if f["places"].get(k) == ver else "✗", k, f["places"].get(k)))
    print("  %s 工作区（不算未跟踪）: %s" % ("✓" if not f["dirty"] else "✗", "干净" if not f["dirty"] else "%d 处改动" % len(f["dirty"])))
    print("  %s 「%s」: %d 处" % ("✓" if not f["placeholders"] else "✗", PLACEHOLDER, len(f["placeholders"])))
    print("  %s 本地 tag: %s / 远端 tag: %s" % ("✓" if not (f["local_tag"] or f["remote_tag"]) else "✗",
                                             f["local_tag"] or "无", f["remote_tag"] or "无"))
    print("  %s CI %s: status=%s conclusion=%s %s" % ("✓" if (st, concl) == ("completed", "success") else "✗",
                                                     GH_WORKFLOW, st, concl, url or ""))
    probs = tag_problems(ver, f)
    for p in probs:
        print("✗ " + p)
    if probs:
        print("✗ 不打 tag（%d 个问题）" % len(probs))
        return 1
    if a.dry_run:
        print("✓ 前置检查全过（演练: 没有打 tag、没有推）")
        return 0
    git(root, "tag", "-a", "v%s" % ver, "-m", "斗龟场 %s" % ver, "HEAD")
    obj = git(root, "rev-parse", "refs/tags/v%s" % ver).stdout.strip()
    git(root, "push", "origin", "refs/tags/v%s" % ver, timeout=300)
    rt = git(root, "ls-remote", "--tags", "origin", "refs/tags/v%s" % ver, "refs/tags/v%s^{}" % ver).stdout
    got = dict((ln.split()[1], ln.split()[0]) for ln in rt.strip().split("\n") if ln.strip())
    ok = got.get("refs/tags/v%s" % ver) == obj and got.get("refs/tags/v%s^{}" % ver) == f["head"]
    print("远端 refs/tags/v%s → %s（期望提交 %s）%s" % (ver, (got.get("refs/tags/v%s^{}" % ver) or "无")[:10],
                                                  f["head"][:10], "✓" if ok else "✗"))
    if not ok:
        return 1
    print("下一步: Actions 里看 iOS TestFlight 跑完 → python tools/asc.py status %s" % ver)
    return 0


# ── main ────────────────────────────────────────────────────────
def main(argv=None):
    stdout_utf8()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=REPO, help="仓库根目录（默认本仓库；自测用临时目录）")
    sp = ap.add_subparsers(dest="cmd", required=True)
    x = sp.add_parser("bump", help="改版本号五处 + CHANGELOG 骨架 + 路线图一行（+ RULES_VER）")
    x.add_argument("version")
    x.add_argument("--rules", required=True, choices=["same", "changed"],
                   help="这一版改没改变对局结果：changed ⇒ RULES_VER +1")
    x.add_argument("--yes-rules-same", action="store_true", help="--rules same 且上个 tag 以来动过 sim 文件时的确认")
    x.add_argument("--rules-why", help="--rules changed 时 RULES_VER 上方注释的理由（一行）；不给 ⇒ 写占位")
    x.add_argument("--date", help="日期 YYYY-MM-DD（默认今天）")
    x.add_argument("--dry-run", action="store_true")
    x.set_defaults(fn=cmd_bump)
    x = sp.add_parser("checklist", help="生成 docs/releases/<版本>.md")
    x.add_argument("version")
    x.add_argument("--force", action="store_true")
    x.add_argument("--dry-run", action="store_true")
    x.set_defaults(fn=cmd_checklist)
    x = sp.add_parser("tag", help="前置检查 → 打 tag → 只推这一个")
    x.add_argument("version")
    x.add_argument("--dry-run", action="store_true")
    x.set_defaults(fn=cmd_tag)
    a = ap.parse_args(argv)
    try:
        return a.fn(a)
    except ReleaseError as e:
        print("✗ %s" % e)
        return 2


if __name__ == "__main__":
    sys.exit(main() or 0)
