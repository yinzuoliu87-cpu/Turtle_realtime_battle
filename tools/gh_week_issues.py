"""gh_week_issues.py —— 建「0.22.8」里程碑和这周的待办 Issues（2026-11-03，用户「全部事项将在这周完成，周日晚上发新版」）。

待办只留一处（方案书 docs/plans/20261102-文件管理与发版流程重整.md Q1，用户 11-02 同意搬到 GitHub Issues）。
令牌取自 Git 凭据管理器（不打印）；绕开本机代理（代理会改写 POST body）。已存在同名里程碑 / 同标题 Issue 就跳过（可重跑）。
  python tools/gh_week_issues.py            # 只列计划
  python tools/gh_week_issues.py --apply    # 真建
"""
import json, os, subprocess, sys, urllib.request
sys.stdout.reconfigure(encoding="utf-8")
REPO = "yinzuoliu87-cpu/Turtle_realtime_battle"
API = "https://api.github.com/repos/" + REPO
APPLY = "--apply" in sys.argv

MILESTONE = {"title": "0.22.8", "due_on": "2026-11-08T23:59:00Z",
             "description": "周日 11-08 晚发版（冠军杯 19:00 UTC 打完之后）。用户 11-03「全部事项将在这周完成，周日晚上发新版」。"}

ISSUES = [
    ("积分赛成绩对账稳定后关掉客户端写成绩（ranked_client_write = false）",
     "方案书 docs/plans/20261101c-积分赛服务器裁判.md V9。\n\n"
     "- [ ] 周二~周四每天对一次：`referee_backlog()`、真人局等待时长、`ranked_records` 与 `ghosts` 逐格对账\n"
     "- [ ] 连续两天 0 失败 / 0 对不上 ⇒ `python tools/prod_flags.py set ranked_client_write false --yes-prod`，回读\n"
     "- [ ] 方案书 V9 回填\n\n11-03 第一天：1154 局 0 失败，平均 36.5 s、最长 117 s。"),
    ("周六 11-07 闯关赛开局一小时实测（陪练号铺号 / 1 分钟兜底 / 补格子号配上即下线）",
     "方案书 docs/plans/20261031b-闯关赛开局铺号与早兜底.md §10.6 第 4 条、§11。\n\n"
     "- [ ] 00:00~01:00 UTC 看调度器日志「拉 … fill」之后 12 秒内进队、配上、几秒内退出\n"
     "- [ ] 真人兜底等待时长、深格子有没有号\n"
     "- [ ] `client_errors` 没有带 /bot 的 unclean_exit 新增\n- [ ] 方案书回填"),
    ("参考《黑箱：无限构筑》学 AI 开发方式（美术 / 技能 / 数值 / 音效 / 特效）",
     "方案书 docs/plans/20261102b-参考黑箱学AI开发方式.md（截止从 11-09 提前到 11-08 随 0.22.8）。\n\n"
     "- [ ] S1 预告片逐帧研究 3~5 个技能演出（docs/studies/，frame_study_audit 守）\n"
     "- [ ] S2 Steam 免费 Demo 实玩 15 分钟录屏（用户 11-02 已同意装）\n- [ ] S3 音效实机录音\n"
     "- [ ] S4 五块对照表 → 用户拍板 A1~A5 做哪几条\n- [ ] 拍板的那几条落地，各有门禁并反向验证会红"),
    ("RULES_VER 门禁：对局结果变了而 RULES_VER 没升就红",
     "方案书 docs/plans/20261102-文件管理与发版流程重整.md R1。半成品在本机 `.out/wip-rules-fingerprint/`。\n\n"
     "- [ ] `verify_rules_fingerprint` 覆盖 28 龟 / 全部装备 / 训龟大师 / 顶档羁绊 / 召唤物，3 次跑指纹相同\n"
     "- [ ] `tools/rules_fingerprint.py --update` 只在 RULES_VER 比上个 tag 大时才许刷新\n"
     "- [ ] 反向验证：把 0.22.7 三处改动（训龟大师免疫 / 盾冲击波 / 触手）逐个改回去，都要红"),
    ("播服务器状态流时信息面板龟能偶尔差 1",
     "11-03 修信息面板属性（951f4185）时门禁 verify_stream_panels_parity 发现：52 个面板里 1 个龟能 9 vs 8（当前放宽 ±1）。\n\n"
     "- [ ] 探针查清是采样时刻（原生在渲染步之后拍）还是数据缺字段\n- [ ] 修好后去掉门禁里的 ±1 放宽"),
    ("0.22.8 发版（周日 11-08 晚，冠军杯打完后）",
     "按 CLAUDE.md §3 发版流水，全部用仓库里的命令：\n\n"
     "- [ ] `tools/release.py bump 0.22.8 --rules same|changed`（这周有没有改对局结果要如实答）\n"
     "- [ ] 本机完整门禁 → push → CI 绿 → `tools/release.py tag 0.22.8`\n"
     "- [ ] TestFlight 上传成功 → `tools/asc.py submit 0.22.8`\n"
     "- [ ] `tools/deploy.py 0.22.8 --allow-weekend`（用户点名周日晚发）\n"
     "- [ ] 苹果过审后 `tools/prod_flags.py force-update 0.22.8 --yes-prod` + `asc.py group-remove 0.22.7`\n"
     "- [ ] `finals_version` 周一再改"),
]


def token():
    p = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n", capture_output=True, text=True,
                       env={**os.environ, "GCM_INTERACTIVE": "Never"})
    return [l.split("=", 1)[1] for l in p.stdout.splitlines() if l.startswith("password=")][0]


op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
TOK = token()


def call(method, path, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    rq = urllib.request.Request(API + path, data=data, method=method,
                                headers={"Authorization": "Bearer " + TOK, "Accept": "application/vnd.github+json",
                                         "Content-Type": "application/json; charset=utf-8"})
    with op.open(rq, timeout=30) as r:
        return r.status, json.loads(r.read().decode("utf-8") or "null")


_, ms = call("GET", "/milestones?state=all&per_page=100")
m = next((x for x in ms if x["title"] == MILESTONE["title"]), None)
if m is None:
    print("里程碑 %s：要建" % MILESTONE["title"])
    if APPLY:
        _, m = call("POST", "/milestones", MILESTONE)
        print("  已建 #%d" % m["number"])
else:
    print("里程碑 %s：已有 #%d" % (m["title"], m["number"]))
_, existing = call("GET", "/issues?state=all&per_page=100")
titles = {x["title"] for x in existing}
for title, body in ISSUES:
    if title in titles:
        print("跳过（已有）：" + title)
        continue
    print("要建：" + title)
    if APPLY and m is not None:
        st, it = call("POST", "/issues", {"title": title, "body": body + "\n\n（由 tools/gh_week_issues.py 建）", "milestone": m["number"]})
        print("  已建 #%d %s" % (it["number"], it["html_url"]))
