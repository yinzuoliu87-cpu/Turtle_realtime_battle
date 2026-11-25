"""turtle_ref_gate.py —— 斗龟场「点名参考就必须先做参考研究」的拦截钩子(2026-11-25, 方案书 docs/plans/20261125r-项目规则与文档整理.md 4.1)

用户 11-25:「我有的时候会让你参考，有的时候不会让你参考。但问题是，如果我让你参考了，你就必须按照规则去参考，
找到来源，然后一帧帧去看，然后去分析」。规矩只写在文档 / 记忆里拦不住(同一条违反了三次), 所以改成程序拦:

  prompt  (UserPromptSubmit): 用户消息里出现「参考」⇒ 记一条待办(时间 + 原话摘录), 并把规矩注入上下文。
  pre     (PreToolUse):       有没结清的待办时, 拒绝 PixelLab 出图 / 出动画 / 特效工作台, 拒绝 Edit/Write 特效代码与美术素材。
  命令行:
    python turtle_ref_gate.py status                      看待办
    python turtle_ref_gate.py resolve <id> <研究文件>      研究文件合格(来源 / ≥8 行逐帧表 / 分析 / 用户看过参考)才结清
    python turtle_ref_gate.py dismiss <id> <理由>          这次「参考」不是美术参考(如「参考方案书」); 理由写进日志, 不能悄悄关
    python turtle_ref_gate.py add <摘录>                  手动补一条(钩子装上之前用户点名的)

只在斗龟场仓库(往上找得到含「斗龟场」的 project.godot)里生效; 别的项目一律放行。
状态与日志: ~/.claude/turtle_ref_state/{pending.json, log.txt}
"""
import io, json, os, re, sys, time

STATE = os.path.join(os.path.expanduser("~"), ".claude", "turtle_ref_state")
PEND = os.path.join(STATE, "pending.json")
LOG = os.path.join(STATE, "log.txt")

ART_PATH = re.compile(r"(_vfx\.gd$|[\\/]assets[\\/]sprites[\\/]|[\\/]tools[\\/]assetgen[\\/])", re.I)
PIXELLAB_READONLY = ("get_", "list_", "search_", "wait_for_jobs", "agent_list", "agent_inspect", "get_balance")


def _load():
    try:
        return json.load(open(PEND, encoding="utf-8"))
    except Exception:
        return []


def _save(p):
    os.makedirs(STATE, exist_ok=True)
    json.dump(p, open(PEND, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def _log(line):
    os.makedirs(STATE, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S") + "  " + line + "\n")


def _in_turtle(path):
    d = os.path.abspath(path or ".")
    if os.path.isfile(d):
        d = os.path.dirname(d)
    for _ in range(12):
        pg = os.path.join(d, "project.godot")
        if os.path.isfile(pg):
            try:
                return "斗龟场" in open(pg, encoding="utf-8", errors="ignore").read()
            except Exception:
                return False
        nd = os.path.dirname(d)
        if nd == d:
            break
        d = nd
    return False


def _open_items():
    return [x for x in _load() if x.get("state") == "open"]


def _out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=True))


def hook_prompt(data):
    prompt = str(data.get("prompt", ""))
    if "参考" not in prompt or not _in_turtle(data.get("cwd", ".")):
        return
    p = _load()
    i = prompt.index("参考")
    ex = prompt[max(0, i - 40): i + 60].replace("\n", " ")
    pid = "r%d" % (len(p) + 1)
    p.append({"id": pid, "t": time.strftime("%Y-%m-%d %H:%M"), "excerpt": ex, "state": "open"})
    _save(p)
    _log("open %s  %s" % (pid, ex))
    _out({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext":
        "[参考钩子] 用户这条消息里有「参考」(待办 %s: …%s…)。若是美术 / 特效参考: 先找到来源(原版素材 / 演示视频), 逐帧看, "
        "写参考研究(docs/studies, 含来源 / ≥8 行逐帧表 / 分析 / 「用户看过参考: 日期 原话」), 给用户看过再动手; "
        "结清前 PixelLab 出图和改特效代码 / 美术素材会被拒。若不是美术参考: python ~/.claude/hooks/turtle_ref_gate.py dismiss %s <理由>(进日志)。"
        "没看过参考绝不写「照 X / 参考 X」。" % (pid, ex, pid)}})


def hook_pre(data):
    name = str(data.get("tool_name", ""))
    ti = data.get("tool_input", {}) or {}
    if name.startswith("mcp__pixellab__"):
        short = name[len("mcp__pixellab__"):]
        if short.startswith(PIXELLAB_READONLY):
            return
        where = data.get("cwd", ".")
        what = "PixelLab " + short
    elif name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        fp = str(ti.get("file_path", "") or ti.get("notebook_path", ""))
        if not ART_PATH.search(fp):
            return
        where = fp
        what = "改美术 / 特效文件 " + fp
    else:
        return
    if not _in_turtle(where):
        return
    items = _open_items()
    if not items:
        return
    lines = "; ".join("%s(%s)…%s…" % (x["id"], x["t"], x["excerpt"][:50]) for x in items)
    reason = ("[参考钩子] 拒绝: %s。还有用户点名的参考没做完: %s。先做参考研究(来源 / 逐帧 / 分析 / 用户看过), 然后 "
              "python ~/.claude/hooks/turtle_ref_gate.py resolve <id> <研究文件>; 不是美术参考就 dismiss <id> <理由>。" % (what, lines))
    _log("deny  %s  (open: %s)" % (what, ",".join(x["id"] for x in items)))
    _out({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}})


def _check_study(path):
    if not os.path.isfile(path):
        return ["文件不存在"]
    t = open(path, encoding="utf-8", errors="ignore").read()
    bad = []
    if not re.search(r"来源", t) or not re.search(r"(https?://|communitydragon)", t, re.I):
        bad.append("缺「来源」(要有链接 / CommunityDragon 路径)")
    rows = re.findall(r"^\|\s*\d+\s*\|", t, re.M)
    if len(rows) < 8:
        bad.append("逐帧表只有 %d 行(要 ≥ 8 行, 每行以帧号开头)" % len(rows))
    if not re.search(r"(分析|拆解|分层)", t):
        bad.append("缺分析 / 拆解")
    m = re.search(r"用户看过参考[:：]\s*(\S.{4,})", t)
    if not m:
        bad.append("缺一行「用户看过参考: 日期 + 用户原话」(给用户看过才能写)")
    return bad


def cli(argv):
    if not argv or argv[0] == "status":
        p = _load()
        for x in p:
            print("%s  %-8s %s  …%s…  %s" % (x["id"], x["state"], x["t"], x["excerpt"][:60], x.get("note", "")))
        print("未结清 %d 条" % len(_open_items()))
        return 0
    cmd = argv[0]
    p = _load()
    if cmd == "add":
        pid = "r%d" % (len(p) + 1)
        p.append({"id": pid, "t": time.strftime("%Y-%m-%d %H:%M"), "excerpt": " ".join(argv[1:]), "state": "open"})
        _save(p)
        _log("open %s  (手动) %s" % (pid, " ".join(argv[1:])))
        print("已加", pid)
        return 0
    if cmd in ("resolve", "dismiss") and len(argv) >= 3:
        x = next((y for y in p if y["id"] == argv[1]), None)
        if x is None:
            print("没有", argv[1]); return 1
        if cmd == "resolve":
            bad = _check_study(argv[2])
            if bad:
                print("不合格, 不结清:\n  - " + "\n  - ".join(bad)); return 1
            x["state"], x["note"] = "resolved", argv[2]
            _log("resolve %s  %s" % (x["id"], argv[2]))
        else:
            x["state"], x["note"] = "dismissed", " ".join(argv[2:])
            _log("dismiss %s  理由: %s" % (x["id"], " ".join(argv[2:])))
        _save(p)
        print(x["id"], x["state"])
        return 0
    print(__doc__)
    return 1


def main():
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode in ("prompt", "pre"):
        try:
            data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
        except Exception:
            return 0
        (hook_prompt if mode == "prompt" else hook_pre)(data)
        return 0
    return cli(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
