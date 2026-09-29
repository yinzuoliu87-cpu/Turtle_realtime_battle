# -*- coding: utf-8 -*-
"""ingame_screen_audit.py — 量【对局结算屏 / 商店 / 背包装备】三屏: 参考集分位 + 我们的差值表。

═══════════════════════════════════════════════════════════════════════════
★这份脚本存在的理由(2026-09-29 用户原话):

    「而且这些 ui 很 ai 味啊, 人家商业游戏怎么可能这么做」
    「每场打完后结算界面能下滑吗, 不能啊, 有很多单位看不到啊」

第一句量不到 —— **"好不好看"这里一个数都出不来**(见文件末 LIMITS)。
第二句量得到, 而且量出来的形状比"不能下滑"更具体(见 `diff` 里的滚动那几行)。

这是 `tools/login_screen_audit.py` 的同族第二把尺子。口径、设备归类、pt 换算、
LIMITS 的写法全部沿用它 —— **不另发明一套**(memory [[fb-hand-rolled-copies-drift]])。
═══════════════════════════════════════════════════════════════════════════

用法
────
    python tools/ingame_screen_audit.py thresholds [<root>]   # 三屏各自的参考分位表 → stdout / ingame_thresholds.md
    python tools/ingame_screen_audit.py diff       [<root>]   # 我们 vs 中位, 按**差距倍数**排序
    python tools/ingame_screen_audit.py census     [<root>]   # 「长列表怎么处理」那一维的分布(用户点名的问题)
    python tools/ingame_screen_audit.py selftest              # ★反向验证: 证明它会 FAIL

<root> 默认 `C:/tmp/uiref`(外部素材, **不进仓库**), 里面:
    ingame_annotations.json      ← 人工标注 + 量出的几何(事实源)
    ig_results/ ig_shop/ ig_equip/  ← 参考图(公开界面截图, 只作内部度量参考)
    index.md                     ← 每张图的游戏名 / 原站分类 / 原图 URL / 分辨率
    ours_*.json                  ← 我们三屏的真实控件几何(由 tests/_probe_ig_geom.gd 倒出)

我们那一侧怎么来(★量真控件 `get_global_rect()`, 不读常量):

    IG_MODE=settle IG_UNITS=14 IG_W=1280 IG_H=720 IG_OUT=C:/tmp/uiref/ours_settle_1280.json \\
    APPDATA=<每屏一份私有目录> NO_SAVE=1 SHIP=1 TURTLE_SUPABASE=" " \\
    <godot> --headless --audio-driver Dummy --path . res://tests/_probe_ig_geom.tscn --quit-after 2600

  ★这一屏可以 `--headless`(只量矩形不看像素); 要**截图**才必须去掉 --headless(无头是 dummy renderer)。
  ★`NO_SAVE=1` + `gs.test_mode = true` 不是可选的 —— 商店/背包会写存档。
  ★结算屏必须**自己造一份长名单**: 3v3 教学局根本量不到"列表放不下"那个形状。

═══ 口径 ═══
· 一律用**百分比**(w=%屏宽 / h=%屏高), 因为参考图分辨率从 499x1080 到 1920x887 都有。
· 换算成 **pt** 时按截图宽高比归类设备(`device_class`), 因为 44pt 是**物理尺寸**。
· 本仓 1pt = 81/44 ≈ 1.841px(`TOUCH_MIN = 81px = 44pt`)。720 高视口 ⇒ 391pt。
· `prov` 记每个数**怎么来的**, 三档不许混着报:
    "probe" = 我们这边, 引擎 `get_global_rect()` 真值
    "grid"  = 参考图上铺 5% 网格读边(`_raw/ig_grid.py`), 精度约 ±1%屏
    "eye"   = 数出来的/归类出来的(行数、按钮数、有没有滚动条、价钱贴哪)
"""
import io
import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

DEFAULT_ROOT = "C:/tmp/uiref"
ANN = "ingame_annotations.json"
PX_PER_PT = 81.0 / 44.0
HIG_MIN_PT = 44.0

SCREENS = [("results", "对局结算屏"), ("shop", "商店"), ("equip", "背包/装备")]

# ══════════════════════════════════════════════════════════════════════
# 设备归类(与 login_screen_audit.py 逐字同口径)
# ══════════════════════════════════════════════════════════════════════
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


## ★我们自己的实拍是 1280x720 / 1560x720 —— 前者宽高比 1.778 会被判成"横屏平板"
##   (768pt), 而真机是 iPhone 横屏 390pt ⇒ pt 会被算大一倍。标注里写死 `cls` 就以它为准。
def class_of(s):
    c = s.get("cls")
    if c:
        if c not in DEVICE_PT:
            raise ValueError("未知设备类别 %r(只认 %s)" % (c, "/".join(sorted(DEVICE_PT))))
        return c
    return device_class(s["W"], s["H"])


def pt_of_h(pct, cls):
    return pct / 100.0 * DEVICE_PT[cls]


def pt_of_w(pct, cls):
    ar = {"PP": 390.0 / 844.0, "LP": 844.0 / 390.0,
          "PT": 768.0 / 1024.0, "LT": 1024.0 / 768.0}[cls]
    return pct / 100.0 * DEVICE_PT[cls] * ar


# ══════════════════════════════════════════════════════════════════════
# 指标登记表  (键, 中文, 单位, 适用屏, 说明)
# ══════════════════════════════════════════════════════════════════════
## 「说明」只描述这条量的是什么, **不含"越大越好"** —— 好坏由人看图判, 不由这里判。
ALL = ("results", "shop", "equip")
METRICS = [
    # ── 一屏信息密度 ──
    ("n_text_lines", "文字行数", "行", ALL, "玩家眼里看到的文本行(不含纯数字格)"),
    ("n_numbers", "数字个数", "个", ALL, "独立数值 token(含带单位的)"),
    ("n_tappable", "可点元件数", "个", ALL, "同屏同时可点的按钮/卡/格/页签总数"),
    ("text_lines_per_tappable", "文字行 ÷ 可点元件", "", ALL, "★一屏是「读的」还是「点的」"),
    # ── 长列表怎么处理(★用户点名的那条) ──
    ("list_rows_visible", "列表一屏几行", "行", ALL, "不滚动时完整看得到的行/格数"),
    ("list_rows_total", "列表共几行", "行", ALL, "该屏这份列表一共多少行/格"),
    ("list_visible_ratio", "一屏看得到的比例", "%", ALL, "★看得到 ÷ 全部"),
    ("row_h_pt", "行高", "pt", ALL, "相邻两行中心距(不受描边影响)"),
    ("n_scroll_affordances", "滚动提示手段数", "种", ALL, "滚动条/渐隐/还有N项/分页/箭头 —— 数有几种"),
    ("scrollbar_w_pt", "滚动条宽", "pt", ALL, "有条才有值; 条太细等于没有"),
    ("has_zebra", "斑马纹或分隔线", "0/1", ALL, "行与行之间有没有视觉分隔"),
    ("n_nested_scroll", "嵌套滚动层数", "层", ALL, "★一个手势只能推动一层"),
    # ── 靶子 ──
    ("min_target_pt", "最小靶短边", "pt", ALL, "这一屏最小的那个可点元件的短边"),
    ("med_target_pt", "靶短边中位", "pt", ALL, "同屏所有可点元件短边的中位"),
    ("min_gap_pt", "最小相邻间隙", "pt", ALL, "相邻两靶之间的净空"),
    # ── 结算屏专有 ──
    ("winlose_channels", "胜负表达通道数", "种", ("results",), "字/大图/特效动画/整屏配色 —— 数有几种"),
    ("n_buttons", "按钮数", "个", ("results",), "结算屏上的按钮(不含页签)"),
    ("primary_btn_w_pct", "主按钮占屏宽", "%W", ("results",), "最宽那个按钮"),
    ("stats_table", "有没有逐单位战报表", "0/1", ("results",), "★我们这一屏的主体就是它"),
    # ── 商店专有 ──
    ("shelf_cols", "货架列数", "列", ("shop",), ""),
    ("shelf_rows", "货架行数", "行", ("shop",), ""),
    ("shelf_cell_short_pt", "货架格短边", "pt", ("shop",), ""),
    ("price_on_card", "价钱贴在卡上", "0/1", ("shop",), "0=价钱只在别处(详情/按钮里)"),
    # ── 背包专有 ──
    ("slot_short_pt", "装备格短边", "pt", ("equip",), ""),
    ("synergy_visible", "羁绊/套装可见", "0/1", ("equip",), "屏上有没有把「凑几件」这件事画出来"),
]
METRIC_KEYS = [m[0] for m in METRICS]

## 枚举维(走 census, 不进分位表)
ENUM_DIMS = [
    ("long_list_mode", "长列表怎么处理", {
        "scrollbar": "有可见滚动条",
        "fade": "边缘渐隐/羽化",
        "more_count": "写出「还有 N 项」",
        "pagination": "分页/页签",
        "arrow_hint": "箭头或文字提示「下面还有」",
        "peek_row": "故意露半行当提示",
        "fixed_norows": "固定行数不滚(放不下就不给)",
        "none": "溢出了而没有任何提示",
        "no_list": "这一屏没有长列表",
    }),
    ("winlose_how", "胜负怎么表达", {
        "word": "文字(胜利/VICTORY)",
        "big_art": "大图/徽章/角色立绘",
        "anim": "入场动画/特效",
        "screen_color": "整屏配色变(金/红)",
        "stars": "星级/评分",
        "none": "没有明确胜负表达",
    }),
    ("buy_feedback", "买了之后怎么反馈", {
        "card_state": "卡自己变(变灰/打勾/消失)",
        "toast": "原地飘字/横幅",
        "modal": "弹确认或恭喜框",
        "anim": "飞入背包动画",
        "counter_only": "只有钱数/件数默默变了",
        "unknown": "截图看不出",
    }),
]


# ══════════════════════════════════════════════════════════════════════
# 单屏 → 指标
# ══════════════════════════════════════════════════════════════════════
def measure_screen(s):
    cls = class_of(s)
    cs = s.get("controls") or []          # [{w,h,cy(可选)}] 百分比
    shorts = sorted(min(pt_of_w(c["w"], cls), pt_of_h(c["h"], cls)) for c in cs) if cs else []
    out = {"_key": s["key"], "_game": s.get("game", ""), "_cls": cls,
           "_screen": s["screen"], "_prov": s.get("prov", "eye")}
    for k in METRIC_KEYS:
        out[k] = None
    out["n_text_lines"] = s.get("n_text_lines")
    out["n_numbers"] = s.get("n_numbers")
    out["n_tappable"] = s.get("n_tappable", len(cs) or None)
    if out["n_text_lines"] is not None and out["n_tappable"]:
        out["text_lines_per_tappable"] = round(float(out["n_text_lines"]) / float(out["n_tappable"]), 2)
    rv, rt = s.get("list_rows_visible"), s.get("list_rows_total")
    out["list_rows_visible"] = rv
    out["list_rows_total"] = rt
    if rv is not None and rt:
        out["list_visible_ratio"] = round(100.0 * float(rv) / float(rt), 1)
    if s.get("row_h") is not None:
        out["row_h_pt"] = pt_of_h(s["row_h"], cls)
    modes = s.get("long_list_mode") or []
    if isinstance(modes, str):
        modes = [modes]
    real = [m for m in modes if m not in ("none", "no_list")]
    out["n_scroll_affordances"] = len(real) if modes else None
    if s.get("scrollbar_w") is not None:
        out["scrollbar_w_pt"] = pt_of_w(s["scrollbar_w"], cls)
    out["has_zebra"] = s.get("has_zebra")
    out["n_nested_scroll"] = s.get("n_nested_scroll")
    if shorts:
        out["min_target_pt"] = shorts[0]
        out["med_target_pt"] = _med(shorts)
    if s.get("min_gap") is not None:
        out["min_gap_pt"] = pt_of_h(s["min_gap"], cls)
    # 结算
    wl = s.get("winlose_how") or []
    if isinstance(wl, str):
        wl = [wl]
    if s["screen"] == "results":
        out["winlose_channels"] = len([x for x in wl if x != "none"]) if wl else None
        out["n_buttons"] = s.get("n_buttons")
        out["primary_btn_w_pct"] = s.get("primary_btn_w")
        out["stats_table"] = s.get("stats_table")
    if s["screen"] == "shop":
        out["shelf_cols"] = s.get("shelf_cols")
        out["shelf_rows"] = s.get("shelf_rows")
        if s.get("shelf_cell_w") is not None and s.get("shelf_cell_h") is not None:
            out["shelf_cell_short_pt"] = min(pt_of_w(s["shelf_cell_w"], cls),
                                             pt_of_h(s["shelf_cell_h"], cls))
        out["price_on_card"] = s.get("price_on_card")
    if s["screen"] == "equip":
        if s.get("slot_w") is not None and s.get("slot_h") is not None:
            out["slot_short_pt"] = min(pt_of_w(s["slot_w"], cls), pt_of_h(s["slot_h"], cls))
        out["synergy_visible"] = s.get("synergy_visible")
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
    if isinstance(x, bool):
        return "1" if x else "0"
    if isinstance(x, float):
        return "%.1f" % x
    return str(x)


def load(root):
    p = os.path.join(root, ANN)
    if not os.path.exists(p):
        print("找不到 %s —— 参考集是外部素材, 不进仓库。抓法/跑法见文件头。" % p)
        sys.exit(2)
    return json.load(io.open(p, encoding="utf-8"))


def _metrics_for(screen):
    return [m for m in METRICS if screen in m[3]]


# ══════════════════════════════════════════════════════════════════════
# thresholds
# ══════════════════════════════════════════════════════════════════════
def cmd_thresholds(root):
    d = load(root)
    lines = []

    def emit(t=""):
        print(t)
        lines.append(t)

    emit("# 三屏(结算 / 商店 / 背包)参考阈值表")
    emit()
    emit("★★**诚实的边界写在最前面** —— 报结论必须连这段和文件末的 LIMITS 一起报:")
    emit()
    emit("| 这些数怎么来的 | 精度 |")
    emit("|---|---|")
    emit("| `prov=probe` **我们自己那几行** | 引擎 `get_global_rect()` 真值, 像素级 |")
    emit("| `prov=grid` 参考图上的矩形 | 铺 5% 网格读边, 约 ±1% 屏(`_raw/ig_grid.py`) |")
    emit("| `prov=eye` 行数/按钮数/有没有滚动条/价钱贴哪 | **看图数出来的**, 不是像素量的 |")
    emit()
    emit("★参考图是**静态单帧**: 「买了之后怎么反馈」「点了会不会滚」这类**只能从一帧里推**, "
         "推不出来的一律记 `unknown`, 不编。")
    emit()
    for sk, scn in SCREENS:
        rows = [measure_screen(s) for s in d["screens"] if s["screen"] == sk]
        if not rows:
            emit("## %s — **0 张**(分母为 0, 这一屏没有任何结论)" % scn)
            emit()
            continue
        lp = [r for r in rows if r["_cls"] == "LP"]
        games = sorted(set(r["_game"] for r in rows))
        emit("## %s (`%s`) — 逐屏量过 **%d 屏 / %d 款**, 其中横屏手机 %d 屏"
             % (scn, sk, len(rows), len(games), len(lp)))
        emit()
        emit("| 指标 | 单位 | p10 | **中位** | p90 | N | 横屏手机中位 |")
        emit("|---|---|---:|---:|---:|---:|---:|")
        for k, cn, unit, _sc, _why in _metrics_for(sk):
            vs = [r[k] for r in rows if r.get(k) is not None]
            ls = [r[k] for r in lp if r.get(k) is not None]
            if not vs:
                continue
            emit("| %s | %s | %s | **%s** | %s | %d | %s |"
                 % (cn, unit, fmt(_q(vs, 10)), fmt(_med(vs)), fmt(_q(vs, 90)),
                    len(vs), fmt(_med(ls))))
        emit()
        emit("逐屏明细:")
        emit()
        emit("| 游戏 | 设备 | 文字行 | 数字 | 可点 | 列表 可见/共 | 行高pt | 长列表手段 | 最小靶pt |")
        emit("|---|---|---:|---:|---:|---:|---:|---|---:|")
        for r in sorted(rows, key=lambda x: (x["_cls"], x["_game"])):
            src = next(s for s in d["screens"] if s["key"] == r["_key"])
            modes = src.get("long_list_mode") or []
            if isinstance(modes, str):
                modes = [modes]
            emit("| %s | %s | %s | %s | %s | %s/%s | %s | %s | %s |"
                 % (r["_game"], DEVICE_CN[r["_cls"]], fmt(r["n_text_lines"]),
                    fmt(r["n_numbers"]), fmt(r["n_tappable"]),
                    fmt(r["list_rows_visible"]), fmt(r["list_rows_total"]),
                    fmt(r["row_h_pt"]), "+".join(modes) or "—", fmt(r["min_target_pt"])))
        emit()
    emit(LIMITS)
    out = os.path.join(root, "ingame_thresholds.md")
    io.open(out, "w", encoding="utf-8", newline="").write("\n".join(lines) + "\n")
    print("\n[写盘] %s" % out)


# ══════════════════════════════════════════════════════════════════════
# diff
# ══════════════════════════════════════════════════════════════════════
def cmd_diff(root):
    d = load(root)
    for sk, scn in SCREENS:
        refs = [measure_screen(s) for s in d["screens"] if s["screen"] == sk]
        lp = [r for r in refs if r["_cls"] == "LP"]
        ours = [o for o in d["ours"] if o["screen"] == sk]
        if not refs:
            print("\n══ %s: 参考 0 屏, 没有可比的中位数 ══" % scn)
            continue
        for o in ours:
            me = measure_screen(o)
            print("")
            print("══ %s · %s ══" % (scn, me["_game"]))
            print("(设备类别 %s; 参考 %d 屏 / 同屏向 %d 屏)"
                  % (DEVICE_CN[me["_cls"]], len(refs), len(lp)))
            tab = []
            for k, cn, unit, _sc, _why in _metrics_for(sk):
                mv = me.get(k)
                med = _med([r[k] for r in refs if r.get(k) is not None])
                lmed = _med([r[k] for r in lp if r.get(k) is not None])
                if mv is None or med is None:
                    continue
                ## ★差距按**中位数的倍数**排, 不按绝对值 ——
                ##   否则「行高差 6pt」永远排在「一屏只看得到 70%」前面。
                base = abs(med) if abs(med) > 1e-6 else 1.0
                rel = (float(mv) - float(med)) / base
                tab.append((abs(rel), cn, unit, mv, med, lmed, rel))
            tab.sort(reverse=True)
            print("| # | 指标 | 单位 | 我们 | 全体中位 | 同屏向中位 | 相对差 |")
            print("|---|---|---|---:|---:|---:|---:|")
            for i, (_a, cn, unit, mv, med, lmed, rel) in enumerate(tab, 1):
                print("| %d | %s | %s | %s | %s | %s | %+.0f%% |"
                      % (i, cn, unit, fmt(mv), fmt(med), fmt(lmed), rel * 100))


# ══════════════════════════════════════════════════════════════════════
# census — ★用户点名的那条: 长列表大家怎么处理
# ══════════════════════════════════════════════════════════════════════
def cmd_census(root):
    d = load(root)
    for dim, cn, labels in ENUM_DIMS:
        print("")
        print("══════ %s ══════" % cn)
        for sk, scn in SCREENS:
            rows = [s for s in d["screens"] if s["screen"] == sk]
            ours = [o for o in d["ours"] if o["screen"] == sk]
            vals = {}
            n_screen = 0
            for s in rows:
                v = s.get(dim)
                if v is None:
                    continue
                if isinstance(v, str):
                    v = [v]
                n_screen += 1
                for x in v:
                    vals.setdefault(x, []).append(s.get("game", s["key"]))
            if n_screen == 0:
                continue
            print("")
            print("  ── %s ── 有这一维标注的 %d 屏 / %d 款"
                  % (scn, n_screen, len(set(s.get("game") for s in rows))))
            for k in sorted(vals, key=lambda x: -len(vals[x])):
                gs = vals[k]
                print("    %-12s %-22s %3d 屏 %5.1f%%   %s"
                      % (k, labels.get(k, "?"), len(gs), 100.0 * len(gs) / n_screen,
                         "、".join(sorted(set(gs))[:6]) + (" …" if len(set(gs)) > 6 else "")))
            for o in ours:
                v = o.get(dim)
                if v is None:
                    continue
                if isinstance(v, str):
                    v = [v]
                print("    ★我们(%s): %s" % (o.get("game", "?"), "+".join(v) or "—"))
    ## 另外单列一条硬计数: 有几屏在"溢出了却没有任何提示"
    print("")
    print("══════ 硬计数: 列表溢出时**一点提示都没有**的屏 ══════")
    for sk, scn in SCREENS:
        rows = [s for s in d["screens"] if s["screen"] == sk]
        base = [s for s in rows if (s.get("long_list_mode") or ["no_list"]) != ["no_list"]]
        bad = [s for s in base
               if (s.get("long_list_mode") or []) == ["none"]]
        print("  %s: %d / %d 屏(有列表的屏里)" % (scn, len(bad), len(base)))
        if bad:
            print("     %s" % "、".join(s.get("game", s["key"]) for s in bad))


# ══════════════════════════════════════════════════════════════════════
# selftest — ★先证明这把尺子会 FAIL, 再拿它报结论
# ══════════════════════════════════════════════════════════════════════
def cmd_selftest(root):
    n = bad = 0

    def ck(name, cond, det=""):
        nonlocal n, bad
        n += 1
        if cond:
            print("  [PASS] %s %s" % (name, det))
        else:
            bad += 1
            print("  [FAIL] %s %s" % (name, det))

    ## ① pt 换算必须分屏向 —— 不分就会把横屏的靶子算大一倍多
    ck("① 同样 6%%屏高: 竖屏手机 %.1fpt ≠ 横屏手机 %.1fpt(差 >2 倍)"
       % (pt_of_h(6, "PP"), pt_of_h(6, "LP")),
       pt_of_h(6, "PP") / pt_of_h(6, "LP") > 2.0)
    ## ② 写死 cls 必须被采纳(我们 1280x720 会被误判成横屏平板)
    ck("② 标注写死 cls=LP 时不按宽高比推(1280x720 否则判成 LT)",
       class_of({"W": 1280, "H": 720, "cls": "LP"}) == "LP"
       and device_class(1280, 720) == "LT")
    ## ③ 未知 cls 必须炸, 不许默默当成某一类
    try:
        class_of({"W": 1, "H": 1, "cls": "ZZ"})
        ck("③ 未知 cls 会报错", False, "居然没报错")
    except ValueError:
        ck("③ 未知 cls 会报错", True)
    ## ④ 变异测试: 把一屏的"可见行数"改坏, `list_visible_ratio` 必须跟着变
    base = {"key": "t", "screen": "results", "cls": "LP", "W": 1560, "H": 720,
            "list_rows_visible": 10, "list_rows_total": 20}
    a = measure_screen(base)["list_visible_ratio"]
    base2 = dict(base); base2["list_rows_visible"] = 5
    b = measure_screen(base2)["list_visible_ratio"]
    ck("④ 变异: 可见行 10→5, 比例 %.1f%%→%.1f%%" % (a, b), abs(a - 50.0) < 0.01 and abs(b - 25.0) < 0.01)
    ## ⑤ 分母必须打出来: rows_total 缺失时 ratio 必须是 None, 不许当 100%
    base3 = {"key": "t", "screen": "results", "cls": "LP", "W": 1560, "H": 720,
             "list_rows_visible": 10}
    ck("⑤ 缺 rows_total 时比例是 None(不许把空检查报成 100%)",
       measure_screen(base3)["list_visible_ratio"] is None)
    ## ⑥ 真数据在位: annotations 里三屏都得有东西, 且每屏 ≥8
    p = os.path.join(root, ANN)
    if os.path.exists(p):
        d = json.load(io.open(p, encoding="utf-8"))
        for sk, scn in SCREENS:
            rs = [s for s in d["screens"] if s["screen"] == sk]
            gs = set(s.get("game") for s in rs)
            ck("⑥ %s: 逐屏量过 %d 屏 / %d 款(要求 ≥8 屏)" % (scn, len(rs), len(gs)),
               len(rs) >= 8)
    else:
        ck("⑥ annotations 在位", False, p)
    print("\n  %d 条, %d 条 FAIL" % (n, bad))
    return 1 if bad else 0


LIMITS = u"""
★★这把尺子量不到什么 —— 报结论必须连这段一起报

用户那句话是「**这些 ui 很 ai 味啊**」。**"ai 味"这里一个数都出不来。**
这份表量得到的只有【形状】:
  一屏几行字/几个数/几个可点元件 / 列表一屏露几行占几成 / 行高与靶子多少 pt /
  长列表用了哪几种提示 / 胜负用了几种通道 / 货架几列几行 / 价钱贴在哪。

它**量不到**(而这些往往才是"ai 味"的真出处):
  ① 字长得好不好看、边框是精致像素雕花还是我随手画的方框 —— 这里一个数都不差。
  ② 文案的语气。「摊子还没摆开」和「商店未开: 本大轮打完第一场后开店」在像素上一样。
  ③ 版式的"手感": 同样 3 列 5 行, 排得像货架还是排得像后台表格, 数值分不开。
  ④ 动起来是什么样。参考图是**静态单帧**, 我们的数据是**无头单帧**, 两边都没有时间轴。
  ⑤ 玩家看完这一屏想不想再打一场 —— 没有任何一条能告诉你。

★为什么「阈值都在区间内」≠ 做对了(上一轮栽过, 逐字抄过来):
  · 中位数是不同游戏拍平出来的。谁都不长成那个中位数, 往中位数靠 = 往"平均脸"靠。
  · 这些量可以**用错误的方式满足**: 把行高撑到 44pt、给列表加一根滚动条, 指标全绿,
    而那一屏仍然是一张后台报表。
  · 区间是 p10~p90, 按定义就有 20% 的**好参考**落在区间外。踩线不等于错。
  · **别拿"门禁绿了"当"变好看了"。**

★这把尺子自己的硬伤(别忽略):
  · **我们和参考不是同一种量法。** 我们的矩形来自引擎(`prov=probe`, 像素级真值),
    参考只能从截图读(`grid`, ±1%屏)或数出来(`eye`)。登录屏那轮实测同一屏两种量法:
    探针 440x42 / 像素量 414x32 —— **像素量把描边算在外面, 短边低估约 25%**。
    ⇒ 靶子高度这条**对参考不利**, 参考的真值只会更大。行高(中心距)不受影响。
  · **参考是一帧, 我们是一次**。参考图那一屏当时列表里有几项是别人存档的偶然,
    我们这边是我**故意塞满**的(长名单)。所以"列表一屏露几成"两侧不是同一个问句:
    参考回答的是"他们那一刻有多少", 我们回答的是"塞满时会怎样"。**这条差别很大。**
  · **样本有偏。** gameuidatabase 收的是"界面做得好"的游戏, 偏欧美/独立;
    云顶之弈 / 金铲铲 / 小冰冰传奇 / 剑与远征这些国服自走棋**一款都没有**。
    ⇒ 所有中位数只对这个样本成立, 不是全行业。
  · **屏型对不齐。** 该站没有"对局结算 + 逐单位战报表"这个分类, 我用
    Results Screen / Post-Game Menu / Level Complete 三类代理。它们大多是
    单人关卡结算(星级 + 分数), 只有少数几款真的有"一队单位的逐行战报" ——
    **那少数几款才是真正可比的**, 中位数里混着一堆比我们简单得多的屏。

⇒ 正确用法只有一个: **当探照灯用, 不当合格证用。**
"""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_ROOT
    if cmd == "thresholds":
        cmd_thresholds(root); return 0
    if cmd == "diff":
        cmd_diff(root); return 0
    if cmd == "census":
        cmd_census(root); return 0
    if cmd == "selftest":
        return cmd_selftest(root)
    print("未知子命令 %r —— 只认 thresholds / diff / census / selftest" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main())
