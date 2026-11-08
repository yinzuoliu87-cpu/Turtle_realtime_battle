# -*- coding: utf-8 -*-
"""tools/web_player_audit.py —— 网页录像播放器的静态检查 + 服务器脚本自测（2026-11-08）。

方案书 docs/plans/20261105c-主站对接偷袭.md §4.7、约定 docs/specs/主站对接约定.md §4.4、部署 server/player/README.md。
运行时那一半（三种错误态、整局从头播到尾、不登录不写数据）在 tests/verify_web_player.gd；这里守「代码里就不许有」的那几样：

  ① 播放器路径（WebPlayerScene.gd / web_player_core.gd / web_player_mode.gd / stream_watch.gd 的 enter_web）
     不引用联网闸、后端、存档写入、文件写入（去掉注释后按正则扫）；屏上的字不出现「主站」「龟币」「金额」。
  ② 开机闸：GameState._ready 里报错上报 / 快照池自愈 / 联网心跳 / 版本墙四样都包在 `if not web_player:` 里，
     停后端在 `if web_player:` 里，存档保护把 web_player 传进去；播放器页 _ready 自己再停一次后端、开存档保护。
  ③ 导出：预设 WebPlayer（Web、单线程、特性 web_player、tests/ 不进包、产物在 build/）且只有它带 web_player；
     project.godot 的 run/main_scene.web_player = WebPlayerMode.SCENE。
  ④ 入口页 server/player/index.html 与 Godot 侧同一套：四句字、手机正则、对局号正则、两条路径逐字相同；
     Caddy 片段 server/player/player.caddy 里有这两条路径。
  ⑤ 服务器脚本自测：server/player/player_ops.py selftest（按版本装 / 清、保留期内的版本不删）、
     server/stream/stream_ops.py purge-selftest（偷袭局 30 天、过期记号）。
"""
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENE_GD = "scripts/scenes/WebPlayerScene.gd"
CORE_GD = "scripts/systems/replay/web_player_core.gd"
MODE_GD = "scripts/util/web_player_mode.gd"
SW_GD = "scripts/systems/replay/stream_watch.gd"
GS_GD = "autoload/GameState.gd"
ENTRY = "server/player/index.html"
CADDY = "server/player/player.caddy"

FORBIDDEN = [
    (r"OnlineGate|online_gate|OnlineWall", "联网闸"),
    (r"\.save\(|save_record|push_save|cloud_payload|save_game", "存档写入"),
    (r"FileAccess\.open|DirAccess|ConfigFile|user://|store_string|store_buffer|store_var", "文件写入"),
    (r"SupabaseNet|supabase\.gd|backend\.gd|referee_net\.gd|remote_pool|\bSB\.|\bBE\.|\bRN\.|ensure_signed_in|ErrorReporter|VersionWall|Uploader",
     "后端 / 登录"),
]
BANNED_WORDS = ("主站", "龟币", "金额")

bad = []
n_checks = 0


def ok(name, cond, detail=""):
    global n_checks
    n_checks += 1
    print("  [%s] %s%s" % ("PASS" if cond else "FAIL", name, ("   " + detail) if detail else ""))
    if not cond:
        bad.append(name)


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n")


def strip_gd_comments(src):
    """去掉 GDScript 注释（# 不在字符串里才算），保留字符串。返回 (代码, 字符串字面量列表)。"""
    out_lines, strs = [], []
    for line in src.split("\n"):
        buf, q, i = [], "", 0
        cur = []
        while i < len(line):
            c = line[i]
            if q:
                if c == "\\" and i + 1 < len(line):
                    cur.append(line[i:i + 2])
                    buf.append(line[i:i + 2])
                    i += 2
                    continue
                if c == q:
                    strs.append("".join(cur))
                    cur = []
                    q = ""
                else:
                    cur.append(c)
                buf.append(c)
            elif c in "\"'":
                q = c
                buf.append(c)
            elif c == "#":
                break
            else:
                buf.append(c)
            i += 1
        out_lines.append("".join(buf))
    return "\n".join(out_lines), strs


def func_body(src, name):
    m = re.search(r"^(static )?func %s\(.*?$" % re.escape(name), src, re.M)
    if not m:
        return ""
    rest = src[m.end():]
    end = re.search(r"^\S", rest, re.M)
    return src[m.start():m.end() + (end.start() if end else len(rest))]


def guarded_by(lines, idx, cond):
    """lines[idx] 往上找第一行缩进更小的非空行, 它是不是 `if <cond>:`。"""
    ind = len(lines[idx]) - len(lines[idx].lstrip("\t"))
    for j in range(idx - 1, -1, -1):
        s = lines[j]
        if not s.strip() or s.strip().startswith("#"):
            continue
        if len(s) - len(s.lstrip("\t")) < ind:
            return s.strip() == "if %s:" % cond
    return False


def main():
    # ① 播放器路径
    print("== ① 播放器路径不连网、不写数据")
    parts = {SCENE_GD: read(SCENE_GD), CORE_GD: read(CORE_GD), MODE_GD: read(MODE_GD)}
    ew = func_body(read(SW_GD), "enter_web")
    ok("分母 · stream_watch.gd 里找到 enter_web", ew.count("\n") > 10, "%d 行" % ew.count("\n"))
    parts[SW_GD + "::enter_web"] = ew
    all_strs = []
    for name, src in parts.items():
        code, strs = strip_gd_comments(src)
        all_strs += strs
        hits = []
        for pat, what in FORBIDDEN:
            for m in re.finditer(pat, code):
                ln = code[:m.start()].count("\n") + 1
                hits.append("%s:%d %s「%s」" % (name, ln, what, m.group(0)))
        ok("%s 不引用联网闸 / 后端 / 存档 / 文件写入（%d 行代码）" % (name, code.count("\n") + 1), not hits, "; ".join(hits[:4]))
    words = [s for s in all_strs if any(w in s for w in BANNED_WORDS)]
    ok("屏上的字不出现「主站」「龟币」「金额」（%d 个字符串）" % len(all_strs), not words and len(all_strs) > 20, str(words[:3]))

    # ② 开机闸
    print("== ② 开机闸")
    gs_code, _ = strip_gd_comments(func_body(read(GS_GD), "_ready"))
    lines = gs_code.split("\n")
    ok("分母 · GameState._ready 读到 WebPlayerMode.active()", any("var web_player := WebPlayerMode.active()" in l for l in lines))
    for call in ("WebPlayerMode.silence_backend()", "ErrorReporter.install(", "heal_pool_cache()", "_start_net_keepalive()", "VersionWall.install("):
        idx = [i for i, l in enumerate(lines) if call in l]
        want = "web_player" if call.startswith("WebPlayerMode") else "not web_player"
        ok("GameState._ready 的 %s 包在 `if %s:` 里" % (call, want), len(idx) == 1 and guarded_by(lines, idx[0], want),
           "出现 %d 次" % len(idx))
    ok("GameState._ready 把 web_player 传给存档保护", re.search(r"apply_save_guard\((.|\n)*?web_player\)", gs_code) is not None)
    sc_ready, _ = strip_gd_comments(func_body(parts[SCENE_GD], "_ready"))
    ok("播放器页 _ready 自己再停一次后端、开存档保护",
       "WebPlayerMode.silence_backend()" in sc_ready and re.search(r"test_mode\s*=\s*true", sc_ready) is not None)
    mode = parts[MODE_GD]
    ok("停后端 = TURTLE_SUPABASE 与 TURTLE_BACKEND 设成空白串（与裁判入口同一个开关）",
       'OS.set_environment("TURTLE_SUPABASE", " ")' in mode and 'OS.set_environment("TURTLE_BACKEND", " ")' in mode)

    # ③ 导出
    print("== ③ 导出预设与主场景")
    presets = read("export_presets.cfg")
    secs = re.split(r"^\[preset\.(\d+)\]\s*$", presets, flags=re.M)
    by_name = {}
    for i in range(1, len(secs) - 1, 2):
        body = secs[i + 1]          # 到下一个 [preset.N] 为止, 含本预设的 [preset.N.options] 段
        m = re.search(r'^name="(.*)"', body, re.M)
        if m:
            by_name[m.group(1)] = body
    wp = by_name.get("WebPlayer", "")
    ok("分母 · 读到 %d 个导出预设、其中有 WebPlayer" % len(by_name), len(by_name) >= 8 and wp != "")
    ok("WebPlayer = Web 平台、单线程模板、特性 web_player、tests/ 不进包、产物在 build/",
       'platform="Web"' in wp and "variant/thread_support=false" in wp and 'custom_features="web_player"' in wp
       and "tests/*" in wp and 'export_path="build/' in wp)
    others = [n for n, b in by_name.items() if n != "WebPlayer" and "web_player" in b]
    ok("别的预设都不带 web_player（正式包开机不会进播放器模式）", not others, str(others))
    scene_const = re.search(r'const SCENE := "(.*)"', mode).group(1)
    pg = read("project.godot")
    ok("project.godot: 带 web_player 的导出主场景 = WebPlayerMode.SCENE（%s）" % scene_const,
       ('run/main_scene.web_player="%s"' % scene_const) in pg and os.path.isfile(os.path.join(ROOT, scene_const[len("res://"):])))

    # ④ 入口页 / Caddy 与 Godot 侧一致
    print("== ④ 入口页 / Caddy 片段与 Godot 侧同一套")
    core = parts[CORE_GD]
    entry = read(ENTRY)
    entry_vis = re.sub(r"<!--(.|\n)*?-->", "", entry)
    for k in ("TXT_MOBILE", "TXT_EXPIRED", "TXT_NOT_FOUND", "TXT_OFFLINE", "TXT_LOADING"):
        g = re.search(r'const %s := "(.*)"' % k, core)
        j = re.search(r'var %s = "(.*)";' % k, entry)
        ok("入口页与 Godot 侧的 %s 逐字相同（%s）" % (k, g.group(1) if g else "?"), g is not None and j is not None and g.group(1) == j.group(1))
    gm = re.search(r'const MOBILE_RE := "\(\?i\)(.*)"', core)
    jm = re.search(r"var MOBILE_RE = /(.*)/i;", entry)
    ok("手机 UA 正则逐字相同", gm is not None and jm is not None and gm.group(1) == jm.group(1))
    gu = re.search(r'const UUID_RE := "(.*)"', core)
    ju = re.search(r"var UUID_RE = /(.*)/;", entry)
    ok("对局号正则逐字相同", gu is not None and ju is not None and gu.group(1) == ju.group(1))
    caddy = read(CADDY)
    for k in ("STREAMS_PATH", "EXPIRED_PATH"):
        path = re.search(r'const %s := "(.*)"' % k, core).group(1)
        ok("%s（%s）入口页与 Caddy 片段里都有" % (k, path), ('"%s/' % path) in entry and ("^%s/" % path) in caddy)
    ok("入口页的字不出现「主站」「龟币」「金额」", not any(w in entry_vis for w in BANNED_WORDS))

    # ⑤ 服务器脚本自测
    print("== ⑤ 服务器脚本自测")
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    for script, arg in (("server/player/player_ops.py", "selftest"), ("server/stream/stream_ops.py", "purge-selftest")):
        r = subprocess.run([sys.executable, os.path.join(ROOT, script), arg], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", env=env, timeout=120)
        tail = [l for l in r.stdout.splitlines() if "[FAIL]" in l] or r.stdout.splitlines()[-1:] or [r.stderr[-200:]]
        ok("%s %s" % (script, arg), r.returncode == 0 and "ALL OK" in r.stdout, "; ".join(tail)[:300])

    print("\n检查 %d 条" % n_checks)
    print("ALL OK" if not bad else "FAILED %d: %s" % (len(bad), "; ".join(bad)))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
