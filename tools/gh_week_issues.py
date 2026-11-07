"""gh_week_issues.py —— 建当前里程碑和这周的待办 Issues（2026-11-03，用户「全部事项将在这周完成，周日晚上发新版」）。

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

MILESTONE = {"title": "0.23.0", "due_on": "2026-11-16T23:59:00Z",
             "description": "龟战 × 主站对接, 目标周一 11-16 上线。方案书 docs/plans/20261107-龟战主站对接.md, 准绳 docs/specs/龟战主站整体方案.md。"}

PLAN = "方案书 docs/plans/20261107-龟战主站对接.md "
ISSUES = [
    ("先定四件事: 升级规则 / 拥有限制范围 / 固定阵容带什么 / 龟币提现",
     PLAN + "§5 Q1 ~ Q4。\n\n- [ ] Q1 升级系统怎么升\n- [ ] Q2「拥有 + 限免」管到哪\n- [ ] Q3 固定阵容的装备、大师、小将从哪来\n"
     "- [ ] Q4 主站书面答复龟币能否换真钱或加密货币(不挡开发, 挡 11-16 上线)"),
    ("主站给内测环境: 地址与密钥(最晚 11-12)", PLAN + "§4.7。\n\n- [ ] 内测地址\n- [ ] 内测密钥\n- [ ] 我们回给主站内测 gameServerURL 和播放器地址"),
    ("11-08 假主站按新接口重写, 迁移草稿", PLAN + "§4.7。分支 feat/raid, 决赛日不动正式服。\n\n- [ ] tools/mock_mainsite.py 覆盖方案 §6 全部接口\n- [ ] 迁移过沙盒"),
    ("11-09 记账合 main, 内测服开始 S5", PLAN + "§4.6。\n\n- [ ] econ/ledger 合最新 main\n- [ ] 补命运之轮记账\n- [ ] 内测服跑满到 11-16"),
    ("11-09 账号登录", PLAN + "§4.1。\n\n- [ ] 网关骨架(验签)\n- [ ] 登录码、系统浏览器、轮询\n- [ ] link/info、link/confirm\n- [ ] 删号调 unlinked"),
    ("11-10 固定阵容", PLAN + "§4.2。\n\n- [ ] raid_defense 表与服务器校验\n- [ ] App 设置页\n- [ ] 变化时上报 defense(rating、device)\n- [ ] 换周清装备、保留龟和站位"),
    ("11-11 拥有 + 限免 + 按龟等级 + 升级", PLAN + "§4.3。\n\n- [ ] player 接口与 mainsite_pets\n- [ ] 限免 7 只\n- [ ] 按龟等级 R1\n- [ ] 升级系统与 pet-level\n- [ ] 等级盖章"),
    ("11-12 偷袭任务与网页播放器, 开发完成", PLAN + "§4.4、§4.5。\n\n- [ ] 建任务接口: 验签、幂等、10 秒回包\n- [ ] 裁判 raid 模式\n- [ ] started / settle / void, 发件箱重试\n- [ ] 超时与 expireAt\n- [ ] raid_on 总开关\n- [ ] 网页播放器上内测\n- [ ] App 全页面无龟币金额(门禁)"),
    ("11-13 ~ 11-14 联调, 出 0.23.0", PLAN + "§6。\n\n- [ ] 方案 §8 第 2 步全流程\n- [ ] 合 main\n- [ ] 0.23.0 tag 与提审"),
    ("11-16 上线", PLAN + "§4.7。正式服写入与部署都要用户点头。\n\n- [ ] 正式服迁移\n- [ ] 网关上线\n- [ ] econ_on\n- [ ] 换正式地址和密钥\n- [ ] 过审后强制更新\n- [ ] 主站开总开关"),
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
