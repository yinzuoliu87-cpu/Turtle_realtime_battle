# -*- coding: utf-8 -*-
"""login_screen_audit.py — 量【登录/账号屏】: 参考集分位 + 我们自己的差值表。

═══════════════════════════════════════════════════════════════════════════
★这份脚本存在的理由(2026-09-28 用户原话):

    「登录你也参考人家的看看」「学习几百个游戏的做法」

上一次我说「主菜单是取了 30 款同类好游戏、量出阈值才做对的」——**用户当场戳穿**:
那批截图量的是**战斗场景**(`tools/battle_scene_audit.py`), 菜单类屏幕后来补了
`tools/menu_screen_audit.py`, 而**登录/账号屏从来没有被任何参考量过**。
这个文件是去把那把缺的尺子补上, 并且**不许拿流程当证据** —— 数字必须能指回具体的图。

★★报结论必须连文件末尾的 `LIMITS` 一起报。它**不发合格证**。
═══════════════════════════════════════════════════════════════════════════

用法
────
    python tools/login_screen_audit.py thresholds [<root>]   # 参考分位表 → stdout / thresholds.md
    python tools/login_screen_audit.py diff       [<root>]   # 我们 vs 中位数, 按差距排序
    python tools/login_screen_audit.py census     [<root>]   # 「强不强制登录」那一维的分布
    python tools/login_screen_audit.py recheck    [<root>]   # ★复算 prov=snap 的框, 与标注对账
    python tools/login_screen_audit.py selftest              # ★反向验证: 证明它会 FAIL

<root> 默认 `C:/tmp/loginref`(外部素材, **不进仓库**), 里面:
    annotations.json           ← 人工标注 + 量出的几何(事实源)
    shots/<类别>/*.jpg         ← 参考图(公开界面截图, 只作内部度量参考)
    ours/wall*.png             ← 我们自己的实拍
    sources_gdb*.txt           ← 每张图的游戏名 / 原站分类 / 原图 URL

我们自己那两张怎么来(照抄仓库里**现成的** `tests/_shot_wall.gd`, 没造新轮子):

    NO_SAVE=1 TURTLE_BACKEND=" " TURTLE_SUPABASE=" " APPDATA=<每屏一份私有目录> \
    SHOT_OUT=C:/tmp/loginref/ours/wall.png \
    <godot> --audio-driver Dummy --path . res://tests/_shot_wall.tscn \
            --resolution 1280x720 --position 5000,5000 --quit-after 400

  ★不能加 `--headless`: 无头是 dummy renderer, 截出来是空图**而且不报错**。
  ★`NO_SAVE=1` 不是可选的 —— 截图台真渲染 ⇒ 不是 headless ⇒ 不给它就**写玩家真存档**。
  ★我们那几个矩形**不是从截图量的**, 是 `tests/_probe_wall_hit.gd` 打出来的实测
    (`prov: "probe"`)。参考图没有探针, 只能从像素量 —— 这条不对称写在 LIMITS 里。

═══ 口径 ═══
· 一律用**百分比**(w=%屏宽 / h=%屏高 / cy=中心的%屏高), 因为参考图分辨率从
  499x1080 到 1920x887 都有, 直接比像素毫无意义。
· 换算成 **pt** 时按截图宽高比归类设备(见 `device_class`), 因为 44pt 是**物理尺寸**:
  同样「6% 屏高」, 竖屏手机上是 51pt, 横屏手机上只有 23pt。**不分屏向就会算错一倍多。**
· 本仓 1pt = 81/44 ≈ 1.841px(`TOUCH_MIN = 81px = 44pt`, 见 `top_bar.gd`)。
  720 高的视口 ⇒ 391pt ⇒ 正好对上「横屏手机 390pt」。
"""
import io
import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

DEFAULT_ROOT = "C:/tmp/loginref"
PX_PER_PT = 81.0 / 44.0          # 本仓触控线: TOUCH_MIN = 81px = 44pt
HIG_MIN_PT = 44.0                # iOS HIG 最小触摸靶; 这里只当**刻度**用, 不当及格线


# ══════════════════════════════════════════════════════════════════════
# 设备归类: 截图宽高比 → (类别, 屏高点数)
# ══════════════════════════════════════════════════════════════════════
## ★为什么非归类不可(这条差点把整份报告算反):
##   Free Fire 的登录按钮 = 5.86% 屏高, Candy Crush 的 Play = 7.41% 屏高 —— 看着差不多。
##   可 Free Fire 是**横屏手机**(屏高 390pt) ⇒ 22.9pt;
##   Candy Crush 是**竖屏手机**(屏高 844pt) ⇒ 62.5pt。**差了 2.7 倍。**
##   只看百分比会得出「大家都差不多」的假结论。
DEVICE_PT = {"PP": 844.0, "LP": 390.0, "PT": 1024.0, "LT": 768.0}
DEVICE_CN = {"PP": "竖屏手机", "LP": "横屏手机", "PT": "竖屏平板", "LT": "横屏平板"}


def device_class(W, H):
    ar = float(W) / float(H)
    if ar < 0.60:
        return "PP"
    if ar < 1.00:
        return "PT"
    if ar <= 1.80:
        return "LT"
    return "LP"


## ★★这条是 selftest 当场照出来的坑, 别删:
##   我们自己的实拍是 **1280x720**(设计分辨率) ⇒ 宽高比 1.778 ⇒ `device_class` 判成
##   **横屏平板(768pt)**。而真机是 **1560x720 的 iPhone 横屏(390pt)** ——
##   按截图推设备会把我们自己的 pt **算大一倍**(44pt 的靶子会被报成 86pt)。
##   ⇒ 标注里允许写死 `"cls"`, 写了就以它为准。凡是「截图分辨率 ≠ 真机视口」的屏都必须写。
def class_of(s):
    c = s.get("cls")
    if c:
        if c not in DEVICE_PT:
            raise ValueError("未知设备类别 %r(只认 %s)" % (c, "/".join(sorted(DEVICE_PT))))
        return c
    return device_class(s["W"], s["H"])


def pt_of_h(pct, cls):
    """把「%屏高」换成 pt。"""
    return pct / 100.0 * DEVICE_PT[cls]


def pt_of_w(pct, cls):
    """把「%屏宽」换成 pt。屏宽点数 = 屏高点数 × 宽高比(按该类的标准机型)。"""
    ar = {"PP": 390.0 / 844.0, "LP": 844.0 / 390.0,
          "PT": 768.0 / 1024.0, "LT": 1024.0 / 768.0}[cls]
    return pct / 100.0 * DEVICE_PT[cls] * ar


# ══════════════════════════════════════════════════════════════════════
# 指标登记表
# ══════════════════════════════════════════════════════════════════════
## 「说明」只描述这条量的是什么, **不含"越大越好"** —— 好坏由人看图判, 不由这里判。
METRICS = [
    ("n_controls", "一屏可点元件数", "个", "同一屏上同时可点的输入框+按钮总数"),
    ("n_text_fields", "一屏文本输入框数", "个", "★最能分开我们和别人的一条"),
    ("n_steps", "分几步", "步", "1=一屏到底"),
    ("h_min_pt", "最小靶短边", "pt", "这一屏最小的那个可点元件的短边"),
    ("h_med_pt", "靶短边中位", "pt", "同屏所有可点元件短边的中位数"),
    ("gap_min_pt", "最小相邻间隙", "pt", "竖向相邻两靶之间的净空; 没有竖向堆叠时为 None"),
    ("gap_med_pt", "相邻间隙中位", "pt", "同上, 取中位"),
    ("pitch_med_pt", "相邻中心距中位", "pt", "★不受描边/边框影响的那条; 见 LIMITS"),
    ("primary_w_pct", "主按钮宽占屏宽", "%W", "这一屏最宽的可点元件"),
    ("explain_lines", "说明文字行数", "行", "靶子之外的解释性文字(不含标题)"),
    ("third_party", "第三方一键登录", "个", "Apple/Facebook/Google/Steam/Kongregate 之类"),
    ("has_exit", "有没有出口", "0/1", "「游客/稍后/先玩」这类能绕过账号的路"),
]
METRIC_KEYS = [m[0] for m in METRICS]


# ══════════════════════════════════════════════════════════════════════
# 单屏 → 指标
# ══════════════════════════════════════════════════════════════════════
def measure_screen(s):
    cls = class_of(s)
    cs = s["controls"]
    hs = sorted(pt_of_h(c["h"], cls) for c in cs)
    out = {
        "_key": s["key"], "_game": s.get("game", ""), "_cls": cls,
        "n_controls": len(cs),
        "n_text_fields": s.get("n_text_fields", 0),
        "n_steps": s.get("n_steps", 1),
        "h_min_pt": hs[0] if hs else None,
        "h_med_pt": _med(hs),
        "primary_w_pct": max(c["w"] for c in cs) if cs else None,
        "explain_lines": s.get("explain_lines", 0),
        "third_party": s.get("third_party", 0),
        "has_exit": 0 if str(s.get("exit", "none")).lower() in ("none", "") else 1,
    }
    ## 竖向堆叠: `stack` 是控件下标的竖序; 没堆叠(横排)就没有竖向间隙这一说。
    idx = s.get("stack") or []
    gaps, pitches = [], []
    for a, b in zip(idx, idx[1:]):
        ca, cb = cs[a], cs[b]
        top_b = cb["cy"] - cb["h"] / 2.0
        bot_a = ca["cy"] + ca["h"] / 2.0
        gaps.append(pt_of_h(top_b - bot_a, cls))
        pitches.append(pt_of_h(cb["cy"] - ca["cy"], cls))
    out["gap_min_pt"] = min(gaps) if gaps else None
    out["gap_med_pt"] = _med(gaps)
    out["pitch_med_pt"] = _med(pitches)
    return out


def _med(v):
    v = [x for x in v if x is not None]
    if not v:
        return None
    v = sorted(v)
    n = len(v)
    return v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2])


def _q(v, p):
    v = sorted(x for x in v if x is not None)
    if not v:
        return None
    if len(v) == 1:
        return v[0]
    i = p / 100.0 * (len(v) - 1)
    lo, hi = int(i), min(int(i) + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (i - lo)


def fmt(x):
    if x is None:
        return "—"
    if isinstance(x, float):
        return "%.1f" % x
    return str(x)


# ══════════════════════════════════════════════════════════════════════
# 载入
# ══════════════════════════════════════════════════════════════════════
def load(root):
    p = os.path.join(root, "annotations.json")
    if not os.path.exists(p):
        print("找不到 %s —— 参考集是外部素材, 不进仓库。抓法见文件头。" % p)
        sys.exit(2)
    return json.load(io.open(p, encoding="utf-8"))


# ══════════════════════════════════════════════════════════════════════
# 命令
# ══════════════════════════════════════════════════════════════════════
def cmd_thresholds(root):
    d = load(root)
    rows = [measure_screen(s) for s in d["screens"]]
    lp = [r for r in rows if r["_cls"] == "LP"]
    lines = []

    def emit(t):
        print(t)
        lines.append(t)

    emit("# 登录/账号屏参考阈值表")
    emit("")
    emit("★**分母**: 参考屏 %d 张(来自 %d 款游戏), 其中与我们同屏向(横屏手机)的 %d 张。"
         % (len(rows), len(set(r["_game"] for r in rows)), len(lp)))
    emit("★这不是「几百款游戏的做法」。首屏那一维的分母是 224 款(见 `census`), "
         "但**逐像素量过的只有这 %d 屏**。" % len(rows))
    emit("")
    emit("| 指标 | 单位 | p10 | 中位 | p90 | N | 同为横屏手机的中位 |")
    emit("|---|---|---|---|---|---|---|")
    for k, cn, unit, _why in METRICS:
        vs = [r[k] for r in rows if r.get(k) is not None]
        ls = [r[k] for r in lp if r.get(k) is not None]
        emit("| %s | %s | %s | %s | %s | %d | %s |"
             % (cn, unit, fmt(_q(vs, 10)), fmt(_med(vs)), fmt(_q(vs, 90)), len(vs), fmt(_med(ls))))
    emit("")
    emit("逐屏明细:")
    emit("")
    emit("| 屏 | 设备 | 元件 | 输入框 | 最小靶pt | 最小间隙pt | 中心距pt | 主钮%W | 出口 |")
    emit("|---|---|---|---|---|---|---|---|---|")
    for r in sorted(rows, key=lambda x: (x["_cls"], x["_game"])):
        emit("| %s | %s | %d | %d | %s | %s | %s | %s | %s |"
             % (r["_game"], DEVICE_CN[r["_cls"]], r["n_controls"], r["n_text_fields"],
                fmt(r["h_min_pt"]), fmt(r["gap_min_pt"]), fmt(r["pitch_med_pt"]),
                fmt(r["primary_w_pct"]), "有" if r["has_exit"] else "无"))
    emit("")
    emit(LIMITS)
    out = os.path.join(root, "thresholds.md")
    io.open(out, "w", encoding="utf-8", newline="").write("\n".join(lines) + "\n")
    print("\n[写盘] %s" % out)


def cmd_diff(root):
    d = load(root)
    refs = [measure_screen(s) for s in d["screens"]]
    lp = [r for r in refs if r["_cls"] == "LP"]
    for o in d["ours"]:
        me = measure_screen(o)
        print("")
        print("══ %s ══" % me["_game"])
        print("(设备类别 %s; 与我们同屏向的参考 %d 屏)" % (DEVICE_CN[me["_cls"]], len(lp)))
        tab = []
        for k, cn, unit, _why in METRICS:
            mv = me.get(k)
            med = _med([r[k] for r in refs if r.get(k) is not None])
            lmed = _med([r[k] for r in lp if r.get(k) is not None])
            if mv is None or med is None:
                continue
            ## 差距按**中位数的倍数**排, 不按绝对值 —— 否则「间隙差 15pt」永远排在
            ## 「输入框多 2 个」前面, 而后者才是量级上的差别。
            base = abs(med) if abs(med) > 1e-6 else 1.0
            rel = (mv - med) / base
            tab.append((abs(rel), cn, unit, mv, med, lmed, rel))
        tab.sort(reverse=True)
        print("| # | 指标 | 单位 | 我们 | 全体中位 | 横屏手机中位 | 相对差 |")
        print("|---|---|---|---|---|---|---|")
        for i, (_a, cn, unit, mv, med, lmed, rel) in enumerate(tab, 1):
            print("| %d | %s | %s | %s | %s | %s | %+.0f%% |"
                  % (i, cn, unit, fmt(mv), fmt(med), fmt(lmed), rel * 100))


def cmd_census(root):
    d = load(root)
    c = d["census_first_screen"]
    n = c["_n_games"]
    print("══ 首屏这一维: %d 张截图 / %d 款手机游戏(来源 %s) ══" % (c["_n_images"], n, c["_source"]))
    print("")
    order = [("forced_wall", "① 强制凭据墙(关不掉·必须填才能进)"),
             ("account_screen_with_guest", "② 专门的账号屏, 但有游客/跳过"),
             ("silent_auto_signin", "③ 静默自动登录(玩家不动手)"),
             ("account_as_secondary", "④ 账号是 Play 旁边的次要控件"),
             ("no_account_ui", "⑤ 首屏根本没有账号相关元件")]
    for k, cn in order:
        v = c[k]
        print("  %-34s %3d 款  %5.1f%%" % (cn, v["n"], 100.0 * v["n"] / n))
        if v.get("games"):
            print("       %s" % "、".join(v["games"][:8]) + (" …" if len(v["games"]) > 8 else ""))
    print("")
    ne = d["census_name_entry"]
    print("══ 取名屏这一维: %d 张 / %d 款(来源 %s) ══" % (ne["_n_images"], ne["_n_games"], ne["_source"]))
    print("  同屏 1 个输入框            %3d 张" % ne["fields_1"]["n_images"])
    print("  同屏 2 个及以上            %3d 张  — %s" % (ne["fields_2plus"]["n_images"], ne["fields_2plus"]["note"]))
    print("  同屏 3 个及以上的凭据表单  %3d 张" % ne["fields_3plus_credentials"]["n_images"])
    print("")
    for o in d["ours"]:
        print("  我们(%s): 输入框 %d 个 / 出口 %s"
              % (o["game"], o["n_text_fields"], o.get("exit", "none")))


def cmd_recheck(root):
    """★复算 prov=snap 的框, 与标注对账 —— 防止标注被手改后悄悄漂。"""
    try:
        import numpy as np
        from scipy import ndimage
        from PIL import Image
    except ImportError:
        print("recheck 需要 numpy/scipy/pillow: pip install numpy scipy pillow")
        return
    sys.path.insert(0, os.path.join(root, "_raw"))
    try:
        from snap import load as sload, snap_best
    except ImportError:
        print("找不到 %s/_raw/snap.py(种子点→框的实现)。" % root)
        return
    d = load(root)
    bad = tot = 0
    for s in d["screens"]:
        p = os.path.join(root, "shots", s["key"])
        img = None
        for c in s["controls"]:
            if c.get("prov") != "snap":
                continue
            tot += 1
            if img is None:
                img = sload(p)
            H, W = img.shape[:2]
            sx, sy = int(W * c["seed"][0] / 100.0), int(H * c["seed"][1] / 100.0)
            r, _n = snap_best(img, sx, sy)
            if r is None:
                print("[FAIL] %s / %s → 量不出来" % (s["game"], c["name"]))
                bad += 1
                continue
            h = 100.0 * r[3] / H
            w = 100.0 * r[2] / W
            if abs(h - c["h"]) > 0.35 or abs(w - c["w"]) > 0.8:
                print("[FAIL] %s / %s → 复算 %.2f%%W x %.2f%%H, 标注 %.2f x %.2f"
                      % (s["game"], c["name"], w, h, c["w"], c["h"]))
                bad += 1
    print("复算 %d 个 snap 框, 不一致 %d 个。" % (tot, bad))
    if tot == 0:
        print("★N=0 —— 这是空检查, 不是通过。")


# ══════════════════════════════════════════════════════════════════════
# 反向验证: 证明它会 FAIL
# ══════════════════════════════════════════════════════════════════════
def selftest():
    """★报「量完了」之前先证明这把尺子会红(CLAUDE.md §7)。"""
    ok = True

    def chk(name, cond):
        nonlocal ok
        print("  %-46s %s" % (name, "PASS" if cond else "**FAIL**"))
        ok = ok and cond

    print("── ① 设备归类: 同样 6% 屏高, 横屏/竖屏必须算出不同的 pt ──")
    chk("499x1080 判成竖屏手机", device_class(499, 1080) == "PP")
    chk("1920x887 判成横屏手机", device_class(1920, 887) == "LP")
    chk("810x1080 判成竖屏平板", device_class(810, 1080) == "PT")
    chk("1440x1080 判成横屏平板", device_class(1440, 1080) == "LT")
    chk("6%屏高: 竖屏手机 ≈ 50.6pt", abs(pt_of_h(6, "PP") - 50.64) < 0.1)
    chk("6%屏高: 横屏手机 ≈ 23.4pt", abs(pt_of_h(6, "LP") - 23.40) < 0.1)
    chk("两者差 ≥2 倍(不分屏向就会算错)", pt_of_h(6, "PP") / pt_of_h(6, "LP") > 2.0)

    print("── ② 本仓换算: 720px 视口 = 391pt, 81px = 44pt ──")
    chk("81px == 44pt", abs(81.0 / PX_PER_PT - 44.0) < 0.01)
    chk("720px ≈ 391pt(对得上横屏手机 390)", abs(720.0 / PX_PER_PT - 390.0) < 2.0)

    print("── ③ 间隙/中心距: 拿手算的例子对 ──")
    syn = {"key": "syn", "game": "syn", "W": 1280, "H": 720, "cls": "LP", "n_text_fields": 0,
           "controls": [{"name": "a", "w": 30, "h": 10, "cy": 30},
                        {"name": "b", "w": 30, "h": 10, "cy": 45}],
           "stack": [0, 1], "exit": "none"}
    m = measure_screen(syn)
    # 中心距 15%H, 两个各高 10%H ⇒ 净空 5%H; 横屏手机 390pt ⇒ 58.5 / 19.5
    chk("中心距 15%%H → 58.5pt", abs(m["pitch_med_pt"] - 58.5) < 0.1)
    chk("间隙 5%%H → 19.5pt", abs(m["gap_min_pt"] - 19.5) < 0.1)

    print("── ③b 1280x720 这个陷阱: 按宽高比会判成平板, 必须能写死覆盖 ──")
    chk("裸 device_class(1280,720) 确实判成平板(这就是坑)", device_class(1280, 720) == "LT")
    chk("写了 cls 就以 cls 为准", class_of(syn) == "LP")
    syn_nocls = json.loads(json.dumps(syn)); syn_nocls.pop("cls")
    chk("不写 cls 会算出 ~1.97 倍的假 pt", abs(measure_screen(syn_nocls)["pitch_med_pt"]
                                          / measure_screen(syn)["pitch_med_pt"] - 768.0 / 390.0) < 0.01)
    bad = json.loads(json.dumps(syn)); bad["cls"] = "XX"
    try:
        class_of(bad); chk("乱写 cls 必须报错", False)
    except ValueError:
        chk("乱写 cls 必须报错", True)

    print("── ④ 变异: 把间隙改小一半, 指标必须跟着变 ──")
    syn2 = json.loads(json.dumps(syn))
    syn2["controls"][1]["cy"] = 42.5          # 中心距 12.5%H ⇒ 净空 2.5%H
    m2 = measure_screen(syn2)
    chk("改了输入, 间隙指标真的变了", abs(m2["gap_min_pt"] - m["gap_min_pt"]) > 5.0)
    chk("变小之后确实更小", m2["gap_min_pt"] < m["gap_min_pt"])

    print("── ⑤ 没有竖向堆叠时不许瞎编间隙 ──")
    syn3 = json.loads(json.dumps(syn))
    syn3["stack"] = []
    chk("横排屏的 gap 是 None 而不是 0", measure_screen(syn3)["gap_min_pt"] is None)

    print("── ⑥ 分位数: 拿已知答案的数列对 ──")
    chk("_med([1,2,3,4]) == 2.5", abs(_med([1, 2, 3, 4]) - 2.5) < 1e-9)
    chk("_q([0..10],10) == 1", abs(_q(list(range(11)), 10) - 1.0) < 1e-9)
    chk("_q([0..10],90) == 9", abs(_q(list(range(11)), 90) - 9.0) < 1e-9)
    chk("空数列回 None 而不是 0", _med([]) is None)

    print("")
    print("selftest: %s" % ("ALL PASS" if ok else "**有 FAIL**"))
    return 0 if ok else 1


# ══════════════════════════════════════════════════════════════════════
LIMITS = u"""
★★这把尺子量不到什么 —— 报结论必须连这段一起报

它**量得到**的只有【数得出来的东西】:
  一屏几个可点元件 / 几个输入框 / 分几步 / 靶子短边多少 pt / 相邻间隙与中心距 /
  主按钮宽占屏宽 / 说明文字几行 / 有没有第三方登录 / 有没有游客出口。

它**量不到**(而这些往往才是决定成败的):
  ① 好不好用 —— 「这一屏让人愿不愿意填」一个字都量不到。间隙合格的屏照样可以让人放弃。
  ② 玩家愿不愿意给邮箱 —— 那取决于他**已经玩到多喜欢**, 而不是这一屏长什么样。
     这恰恰是「先玩后绑 vs 开局就绑」的全部差别, 而这把尺子只看静态单帧。
  ③ 文案 —— 「绑定邮箱才能开始」和「保存进度(可跳过)」在像素上一模一样。
  ④ 流程 —— 截图看不到「点了发验证码之后会发生什么」「收不到码怎么办」。
     真机上「点了没反应」的 bug 这把尺子永远抓不到。
  ⑤ 美术 —— 边框是精致像素雕花还是我随手画的方框, 这里一个数都不差。
  ⑥ 转化率 —— 没有任何一条能告诉你会流失多少人。

★为什么「阈值都在区间内」≠ 做对了:
  · 参考中位数是 13 屏不同游戏拍平出来的。谁都不长成那个中位数, 往中位数靠 = 往"平均脸"靠。
  · 这些量可以**用错误的方式满足**: 把三个输入框都撑到 44pt、间隙拉到 20pt, 指标全绿,
    而那仍然是一堵关不掉的墙 —— 上一轮我就是拿「0 个圆角盒」当"全清了"报的。
  · 区间是 p10~p90, 按定义就有 20% 的**好参考**落在区间外。踩线不等于错。

★这把尺子自己的三条硬伤(别忽略):
  · **我们和参考不是同一种量法。** 我们的矩形来自探针(`prov: "probe"`, 像素级真值),
    参考只能从截图量(`snap`/`grid`)。实测同一屏两种量法: 探针 440x42, 像素量 414x32
    —— **像素量把描边算在外面, 短边低估约 25%**。⇒ 靶子高度这条**对参考不利**,
    比较时要记得参考的真值只会更大, 不会更小。**中心距不受影响**, 那是唯一干净的一条。
  · **「首屏」是用 Title Screen 截图代理的。** 我没有一台一台装游戏看首启,
    所以「0 款强制」严格说是「224 款的首屏截图里没有一张是凭据墙」。
    旁证: gameuidatabase 的 186 个分类里**根本没有 login/sign-in 这一类**。
  · **样本有偏。** gameuidatabase 收的是"界面做得好"的游戏, 偏欧美/偏独立;
    国服氪金手游那一挂(强制实名、强制手机号)这里几乎没有。
    ⇒ 「几乎没人强制」这个结论**只对这个样本成立**, 不是全行业。

⇒ 正确用法只有一个: **当探照灯用, 不当合格证用。**
"""


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "thresholds"
    root = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_ROOT
    if cmd == "selftest":
        return selftest()
    if cmd == "thresholds":
        cmd_thresholds(root)
    elif cmd == "diff":
        cmd_diff(root)
    elif cmd == "census":
        cmd_census(root)
    elif cmd == "recheck":
        cmd_recheck(root)
    elif cmd == "limits":
        print(LIMITS)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
