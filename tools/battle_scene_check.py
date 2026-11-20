# -*- coding: utf-8 -*-
"""战场画面的**实拍**门禁 (2026-10-02 建)。

`tools/battle_scene_audit.py` 量得很细, 但它要**手工喂一张图** ——
于是方案书 `20260918-战斗场景美术重做.md` / `20260918b-战斗场景整体重做.md` 里
那几条验收项长年写着「**已达标但无门禁**」。没人跑的量尺 = 画面可以静默退回去,
而本仓已经吃过这一类的亏(memory `fb-zero-caller-is-a-whole-class`)。

这个脚本把「拍 + 量 + 判」接成一条, 进 `run-tests.sh`。

★拍摄口径钉死在下面的 SHOT 里, **不许随手改**: 同一场战斗
  540x960 量出 13.58% / 1280x720 量出 18.74% / 1920x1080 量出 18.40%
  —— 换分辨率就不是同一件事了(台账 `tests/golden/battle_scene_debt.txt` 里有这张表)。

★★本条是【本地专属审计】: 它开真窗口截图(--position 5000,5000 把窗口丢到屏幕外),
  无显示设备的机器(GitHub runner)跑不了, 会干净跳过并返回 0。
  这件事本身由 `tools/ci_deps_audit.py` 的 LOCAL_ONLY 名单守着 ——
  它会**真把本脚本跑一遍**(强制无显示设备), 确认确实干净跳过, 所以这条登记不会是假的。

跑法:
    python tools/battle_scene_check.py
"""
import os
import subprocess
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools"))

GODOT = os.environ.get("GODOT", "C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe")
OUT = os.path.join(os.environ.get("TEMP", "/tmp"), "turtle_battle_scene_check.png")

## ★拍摄口径 —— 改这里之前先读台账里那张「换分辨率就不是同一件事」的表。
SHOT_RES = "1280x720"
SHOT_SEC = "4"        # SELFSHOT: 等 4 秒真实时间, 让战斗跑起来(单位已经在打了)
SHOT_FRAMES = "900"   # --quit-after 是【帧】不是毫秒; 600 帧不够(拍不到), 900 够

## ★★2026-11-20 改成四张正式地图各拍一张、按台账只减不增(方案书 docs/plans/20261120b-删除旧地图.md):
##   原来拍的是开发工具默认那张 = 旧图 V0_BASE(玩家 10-04 起就看不到), 标定目标也是在它身上达成的;
##   旧图删掉、默认换成暗林后第一次量到新图 ⇒ 四张都有项没达到标定目标(暗林中间调 21.4% / 色数 50 …)。
##   那是 10-04 以来就存在的欠账(这条审计一直没量到它们), 不是这次改坏的 ⇒ 记台账、只许变好, 差距每次打印出来,
##   留给「地图整体优化」(用户 11-20 排的下一步)去还; 不调低标定目标。
MAPS = [("V1_DUSK", "dusk"), ("V2_REEF", "reef"), ("V3_SHOAL", "shoal"), ("V4_STORM", "storm")]
METRICS = [("mid", "mid_tone_pct"), ("colors", "eff_colors"), ("sat", "bright_sat_p50"), ("ramp", "ramp_ratio"), ("hf", "edge_mid_pct")]
## 项: (标定目标, 越大越好 hi / 越小越好 lo, 量测抖动容差, 打印格式)。目标 = battle_scene_audit.verdict 那套(不改)。
TARGETS = {
    "mid": (24.0, "hi", 1.5, "%.1f"),
    "colors": (88.0, "hi", 6.0, "%.0f"),
    "sat": (0.60, "lo", 0.05, "%.3f"),
    "ramp": (1.0, "hi", 0.15, "%.2f"),
    "hf": (5.20, "lo", 1.5, "%.2f"),
}
LEDGER = os.path.join(ROOT, "tests", "golden", "battle_scene_maps.json")


def _load_ledger():
    import json
    if not os.path.exists(LEDGER):
        return {}
    d = json.load(open(LEDGER, encoding="utf-8"))
    return d.get("maps", {})


def _save_ledger(cur):
    import json
    doc = {"_说明": "tools/battle_scene_check.py 的台账: 四张正式地图实拍读数(1280x720 · SELFSHOT 4 秒)。只许往好的方向改(BSC_UPDATE=1 有图变差就拒写)。"
                   "标定目标见 TARGETS; 没达到的是 10-04 新图上线以来的欠账(11-20 删旧图后才第一次量到), 留给地图整体优化。",
           "maps": cur}
    open(LEDGER, "w", encoding="utf-8", newline="\n").write(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")


SKIP_MARK = "本条为【本地专属审计】: 它开真窗口截图, 无显示设备的机器跑不了"


def _no_display():
    ## ★强制开关给 ci_deps_audit 用 —— 它要在有显示设备的本机上验「跳过这条路真的走得通」。
    if os.environ.get("TURTLE_FORCE_NO_DISPLAY") == "1":
        return True
    if os.name == "nt":
        return False
    return not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def shoot(theme=""):
    if os.path.exists(OUT):
        os.remove(OUT)
    env = dict(os.environ)
    if theme:
        env["ARENA_THEME"] = theme   # 强制这一张(ArenaTheme._check_env 认; 正式对局 / 开发工具都赢)
    ## ★隔离(2026-11-13): 原来继承本机 APPDATA ⇒ 每次预检都用玩家真存档目录开一局战斗、还连正式服对时钟
    ##   (真目录 logs/ 里 06:01 / 06:31 / 08:39 / 08:50 那几条就是它)。存档本体有「命令行指定场景」那道闸挡着,
    ##   但 server_clock.cfg 等别的文件照写。⇒ 一份临时 user:// + 不连服务器, 与 run-tests.sh 的测试同一套。
    ud = tempfile.mkdtemp(prefix="bsc_")
    env.update({
        "APPDATA": ud, "XDG_DATA_HOME": ud,
        "TURTLE_SUPABASE": " ", "TURTLE_BACKEND": " ",
        "SHIP": "1",            # 关 demo 劫持, 否则假人永不死(CLAUDE.md §4)
        "QUIET": "1",           # ★开窗口也必须静音 —— 用户 2026-10-01 点名的那条
        "SELFSHOT": SHOT_SEC,
        "SHOT_OUT": OUT.replace("\\", "/"),
    })
    subprocess.run(
        [GODOT, "--audio-driver", "Dummy", "--path", ROOT,
         "--resolution", SHOT_RES, "--position", "5000,5000",
         "res://scenes/RealtimeBattle3D.tscn", "--quit-after", SHOT_FRAMES],
        env=env, capture_output=True, timeout=180)
    return os.path.exists(OUT)


def main():
    if _no_display():
        print("  [SKIP] " + SKIP_MARK)
        print("  ⚠ 本机没跑到它 —— **推之前必须在本地跑过一次全套门禁**, 这条只有本地能验。")
        ## ★这一行是给 run-tests.sh 的 run_audit 看的: 它判的是输出里有没有【ALL OK】。
        ##   v0.19.499 加这条审计时**漏了它** ⇒ CI 上审计器正确跳过(退出码 0)却被判成 FAIL,
        ##   而我当时没看 CI, 所以连红了 5 次都不知道。现成的 vfx_ingame_check 一直是这么写的。
        print("ALL OK — (已登记跳过)")
        return 0

    if not os.path.exists(GODOT):
        print("  [FAIL] 找不到 Godot: %s (用 GODOT=... 指过来)" % GODOT)
        return 1

    import battle_scene_audit as A
    ledger = _load_ledger()
    update = os.environ.get("BSC_UPDATE") == "1"
    cur = {}
    bad = 0
    gaps = 0
    for th, key in MAPS:
        if not shoot(th):
            ## ★这条不许降级成 SKIP: 拍不到就是没验, 不是"通过"。
            print("  [FAIL] %s 一张都没拍到 —— 战斗场景没跑起来 (期望 %s)" % (key, OUT))
            return 1
        a = A.audit(OUT)
        if a is None:
            print("  [FAIL] %s 量不出来(图读不了?)" % key)
            return 1
        m = {k: a.get(src) for k, src in METRICS}
        cur[key] = m
        print("  [%s] 实拍 %dx%d → 场地区 %dx%d · 采样 %d 点" % (key, a["size"][0], a["size"][1], a["crop"][0], a["crop"][1], a["samples"]))
        base = ledger.get(key)
        for k, _src in METRICS:
            v = m.get(k)
            tgt, better, tol, fmt = TARGETS[k]
            if v is None:
                print("    [FAIL] %-6s 分母不足, 量不出(不判过)" % k)
                bad += 1
                continue
            hit = (v >= tgt) if better == "hi" else (v <= tgt)
            if not hit:
                gaps += 1
            if base is None or base.get(k) is None:
                print("    [FAIL] %-6s 台账里没有这张图 / 这一项(先 BSC_UPDATE=1 建台账)  实测 %s" % (k, fmt % v))
                bad += 1
                continue
            bv = float(base[k])
            ## 达到标定目标的项只守目标(远超目标的正常抖动不拦, 例: 深礁亮坡比 7.21 ↔ 6.99); 没达到的才守台账、不许更差
            worse = (not hit) and ((v < bv - tol) if better == "hi" else (v > bv + tol))
            print("    [%s] %-6s 实测 %s · 台账 %s(容差 %s)· 目标 %s %s%s" % (
                "FAIL" if worse else "PASS", k, fmt % v, fmt % bv, fmt % tol, "≥" if better == "hi" else "≤", fmt % tgt,
                "" if hit else "  ← 未达目标"))
            if worse:
                bad += 1
    print("")
    print("  [分母] %d 张正式地图 × %d 项 · 未达标定目标 %d 项(地图优化欠账, 见 tests/golden/battle_scene_maps.json 头注)" % (len(MAPS), len(METRICS), gaps))
    if update:
        if bad and ledger:
            print("FAILED: 有图比台账变差, 拒写台账(台账只许往好的方向改)")
            return 1
        _save_ledger(cur)
        print("ALL OK — 已写台账 %s" % LEDGER)
        return 0
    if bad:
        print("FAILED: %d 条" % bad)
        return 1
    print("ALL OK — 战场画面实拍: 四张正式地图都不比台账差(%d 项未达标定目标, 是欠账不是新问题)" % gaps)
    return 0


# ★ __main__ 守卫: 别的脚本要 import 本文件复用它的判据函数(不另抄一份口径);
#   没有守卫时 import 会当场跑完审计并 sys.exit, **把调用方静默掐死**。
if __name__ == "__main__":
    sys.exit(main())
