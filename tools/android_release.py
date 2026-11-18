# -*- coding: utf-8 -*-
"""tools/android_release.py —— 安卓直装包：正式签名证书 / 版本号 / 出包核对（2026-11-18 · 方案书 docs/plans/20261118b-安卓直装包.md A1 / A2）。

  python tools/android_release.py                 = selftest（纯函数自测，进门禁 run_audit，只认 ALL OK）
  python tools/android_release.py keygen          生成正式签名证书（已有就拒）；放 ~/.config/turtle/secrets/android/，密码不打印
  python tools/android_release.py fingerprint     打印证书 SHA-256 指纹（公开信息）并与 PINNED_SHA256 比对
  python tools/android_release.py gh-secrets      把证书 + 密码加密传进 GitHub Actions Secrets（CI 出包用；只写不读）
  python tools/android_release.py code <版本>      版本名 → versionCode（主×1000000 + 次×1000 + 序号）
  python tools/android_release.py verify <apk> [--version X]
                                                  apksigner 核签名指纹 = PINNED_SHA256；aapt2 核包名 / 版本名 / 版本号；不符退出码 1
  python tools/android_release.py build [--out <apk>]
                                                  本机出正式签名包（Godot --export-release "Android"，证书走环境变量）再 verify

★为什么要正式证书：安卓「覆盖安装更新」要求新旧包同一张证书。调试证书（export_presets.cfg 里那张）谁都能复现，
  第一次对外发就必须是这张正式的，之后换不了。**证书丢了 = 已装的玩家再也收不到能覆盖安装的更新** ⇒
  本机一份 + GitHub Secrets（只能写不能读，不算备份）+ 用户自己另存一份。
★Godot 用环境变量 GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD 覆盖导出预设（Godot 文档「Exporting for Android」），
  证书库密码与密钥密码须相同（PKCS12 本来就只有一个）⇒ 仓库里的预设继续指调试证书，正式证书与密码不进仓库。
★versionCode 由版本名算出来（不依赖 CI 运行号）⇒ 单调递增、重跑不撞号；release.py bump 写进 export_presets.cfg，
  verify_version 守「预设里的 version/code = 这里的算法」。
"""
import json
import os
import re
import secrets
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGE = "com.turtlebattle.realtime"
ALIAS = "turtlearena"
DNAME = "CN=Turtle Arena"
SECRETS_DIR = os.path.join(os.path.expanduser("~"), ".config", "turtle", "secrets", "android")
KEYSTORE = os.path.join(SECRETS_DIR, "release.keystore")
CRED = os.path.join(SECRETS_DIR, "release.json")
## 正式证书的 SHA-256 指纹（小写十六进制、无冒号；证书公开部分，不是秘密）。2026-11-18 01:47 keygen 生成（CN=Turtle Arena,
## RSA 4096, 10000 天）。空 ⇒ verify 一律拒。
PINNED_SHA256 = "32b1fc617f74fc68a9849140fec1ee83131208fa2409e968faa6b2cd94605a2e"

LOCAL_JDK = os.path.join(os.path.expanduser("~"), "tools", "jdk17")
LOCAL_SDK = os.path.join(os.path.expanduser("~"), "tools", "android-sdk")
GODOT_LOCAL = os.environ.get("GODOT", r"C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe")


class AndroidError(Exception):
    pass


# ── 纯函数（selftest 全覆盖）───────────────────────────────────────────────

def version_code(ver):
    """「0.23.5」→ 23005。主 < 2000、次 < 1000、序号 < 1000（安卓 versionCode 上限 2100000000）。"""
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", str(ver).strip())
    if not m:
        raise AndroidError("版本名 %r 不是 主.次.序号" % (ver,))
    a, b, c = (int(x) for x in m.groups())
    if a >= 2000 or b >= 1000 or c >= 1000:
        raise AndroidError("版本名 %r 超出算法范围(主<2000 次<1000 序号<1000)" % (ver,))
    return a * 1000000 + b * 1000 + c


def norm_hex(s):
    return re.sub(r"[^0-9a-f]", "", str(s).lower())


def parse_apksigner(text):
    """`apksigner verify --print-certs` 的输出 → 每个签名者证书的 SHA-256（规范化十六进制）。"""
    ## 「Signer #1 …」或按 SDK 段分组的「Signer (minSdkVersion=24, maxSdkVersion=…) …」两种写法都认; 同一张证书只算一次。
    out = []
    for m in re.finditer(r"(?m)^Signer (?:#\d+|\([^)]*\)) certificate SHA-256 digest:\s*([0-9a-fA-F:]+)\s*$", text):
        h = norm_hex(m.group(1))
        if h not in out:
            out.append(h)
    return out


def parse_badging(text):
    """`aapt2 dump badging` 第一行 → {name, versionCode, versionName}。"""
    m = re.search(r"(?m)^package: (.*)$", text)
    if not m:
        return {}
    return dict(re.findall(r"(\w+)='([^']*)'", m.group(1)))


def parse_keytool_sha256(text):
    """`keytool -list -v` 输出里证书指纹那一行（「SHA256: AA:BB:…」）。"""
    m = re.search(r"(?m)^\s*SHA256:\s*([0-9A-Fa-f:]+)\s*$", text)
    return norm_hex(m.group(1)) if m else ""


def check_apk(signers, badging, ver, pinned=None):
    """核一个包。返回问题列表（空 = 通过）。"""
    pinned = PINNED_SHA256 if pinned is None else pinned
    probs = []
    if not pinned:
        probs.append("PINNED_SHA256 还没填（先 keygen 再把指纹写进本文件）")
    if len(signers) != 1:
        probs.append("签名者应恰好 1 个，实际 %d 个" % len(signers))
    elif pinned and signers[0] != norm_hex(pinned):
        probs.append("签名证书指纹 %s… ≠ 固定的正式证书 %s…（用错证书：调试证书 / 别的库）" % (signers[0][:16], norm_hex(pinned)[:16]))
    if badging.get("name") != PACKAGE:
        probs.append("包名 %r ≠ %s" % (badging.get("name"), PACKAGE))
    if badging.get("versionName") != ver:
        probs.append("versionName %r ≠ 版本 %s" % (badging.get("versionName"), ver))
    try:
        want = str(version_code(ver))
    except AndroidError as e:
        probs.append(str(e))
        want = None
    if want is not None and badging.get("versionCode") != want:
        probs.append("versionCode %r ≠ %s（= version_code(%s)）" % (badging.get("versionCode"), want, ver))
    return probs


def project_version(root=REPO):
    t = open(os.path.join(root, "project.godot"), encoding="utf-8").read()
    m = re.search(r'(?m)^config/version="([^"]+)"', t)
    if not m:
        raise AndroidError("project.godot 里读不到 config/version")
    return m.group(1)


def preset_android(root=REPO, key="version/code"):
    """export_presets.cfg 里 Android 预设（platform="Android" 那一段的 options）某一项的值；找不到 ⇒ None。"""
    lines = open(os.path.join(root, "export_presets.cfg"), encoding="utf-8").read().split("\n")
    sec, plat, opt_of = None, {}, {}
    for ln in lines:
        s = ln.strip()
        m = re.fullmatch(r"\[preset\.(\d+)(\.options)?\]", s)
        if m:
            sec = (m.group(1), bool(m.group(2)))
            continue
        if sec is None or "=" not in s:
            continue
        k, v = s.split("=", 1)
        if not sec[1] and k == "platform":
            plat[sec[0]] = v.strip('"')
        if sec[1] and k == key:
            opt_of[sec[0]] = v.strip('"')
    ids = [i for i, p in plat.items() if p == "Android"]
    if len(ids) != 1:
        raise AndroidError("export_presets.cfg 里 Android 预设应恰好 1 个，实际 %d 个" % len(ids))
    return opt_of.get(ids[0])


# ── 外部工具 ────────────────────────────────────────────────────────────

def _exe(name):
    return name + (".exe" if os.name == "nt" else "")


def keytool():
    for base in (os.environ.get("JAVA_HOME", ""), LOCAL_JDK):
        if base:
            p = os.path.join(base, "bin", _exe("keytool"))
            if os.path.isfile(p):
                return p
    p = shutil.which("keytool")
    if not p:
        raise AndroidError("找不到 keytool（设 JAVA_HOME，或本机 ~/tools/jdk17）")
    return p


def build_tool(name):
    """Android SDK build-tools 里的 apksigner / aapt2: 环境变量 BUILD_TOOLS 指定版本就用它(CI 固定 36.0.0, 与本机同一版),
    否则取最新版本。"""
    for base in (os.environ.get("ANDROID_HOME", ""), os.environ.get("ANDROID_SDK_ROOT", ""), LOCAL_SDK):
        bt = os.path.join(base, "build-tools") if base else ""
        if bt and os.path.isdir(bt):
            vers = sorted((d for d in os.listdir(bt) if re.fullmatch(r"\d+\.\d+\.\d+", d)),
                          key=lambda d: tuple(int(x) for x in d.split(".")))
            pick = os.environ.get("BUILD_TOOLS", "")
            if pick:
                if pick not in vers:
                    raise AndroidError("BUILD_TOOLS=%s 不在 %s 里(有 %s)" % (pick, bt, vers))
                vers = [pick]
            for v in reversed(vers):
                for cand in ([name + ".bat", name + ".exe", name] if os.name == "nt" else [name]):
                    p = os.path.join(bt, v, cand)
                    if os.path.isfile(p):
                        return p
    raise AndroidError("找不到 Android SDK build-tools 里的 %s（设 ANDROID_HOME，或本机 ~/tools/android-sdk）" % name)


def java_env():
    """apksigner 是 Java 程序: 没设 JAVA_HOME 时用本机 ~/tools/jdk17(CI 上 workflow 自己设)。"""
    env = dict(os.environ)
    if not env.get("JAVA_HOME") and os.path.isdir(LOCAL_JDK):
        env["JAVA_HOME"] = LOCAL_JDK
        env["PATH"] = os.path.join(LOCAL_JDK, "bin") + os.pathsep + env.get("PATH", "")
    return env


def run(cmd, env=None, timeout=600):
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=timeout)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def read_cred():
    if not (os.path.isfile(KEYSTORE) and os.path.isfile(CRED)):
        raise AndroidError("本机没有正式证书（%s）—— 先 keygen" % SECRETS_DIR)
    c = json.load(open(CRED, encoding="utf-8"))
    if c.get("alias") != ALIAS or not c.get("password"):
        raise AndroidError("%s 内容不对（要 alias=%s + password）" % (CRED, ALIAS))
    return c


def keystore_sha256():
    c = read_cred()
    env = dict(os.environ, KS_PASS=c["password"])
    code, out = run([keytool(), "-list", "-v", "-keystore", KEYSTORE, "-alias", ALIAS, "-storepass:env", "KS_PASS"], env=env)
    if code != 0:
        raise AndroidError("keytool -list 失败（退出码 %d）" % code)
    h = parse_keytool_sha256(out)
    if not h:
        raise AndroidError("keytool 输出里没找到 SHA256 指纹")
    return h


# ── 子命令 ──────────────────────────────────────────────────────────────

def cmd_keygen(_a):
    if os.path.exists(KEYSTORE) or os.path.exists(CRED):
        raise AndroidError("已经有正式证书了（%s）—— 绝不覆盖：换证书 = 老玩家再也收不到更新" % SECRETS_DIR)
    os.makedirs(SECRETS_DIR, exist_ok=True)
    pw = secrets.token_urlsafe(24)
    env = dict(os.environ, KS_PASS=pw)
    code, out = run([keytool(), "-genkeypair", "-keystore", KEYSTORE, "-storetype", "PKCS12", "-alias", ALIAS,
                     "-keyalg", "RSA", "-keysize", "4096", "-validity", "10000", "-dname", DNAME,
                     "-storepass:env", "KS_PASS", "-keypass:env", "KS_PASS"], env=env)
    if code != 0 or not os.path.isfile(KEYSTORE):
        raise AndroidError("keytool -genkeypair 失败（退出码 %d）：%s" % (code, out.strip()[-300:]))
    with open(CRED, "w", encoding="utf-8") as f:
        json.dump({"alias": ALIAS, "password": pw}, f)
    print("已生成正式证书：%s（密码在 %s，不打印）" % (KEYSTORE, CRED))
    print("SHA-256 指纹：%s" % keystore_sha256())
    print("下一步：把指纹写进本文件 PINNED_SHA256；证书 + 密码另存一份到用户自己的地方。")


def cmd_gh_secrets(_a):
    """把正式证书传进 GitHub Actions Secrets（ANDROID_KEYSTORE_B64 / ANDROID_KEY_PASSWORD），CI 出包用。
    令牌取自 Git 凭据管理器（不打印）；值用仓库公钥 sealed box 加密后上传（GitHub 文档做法）；直连不走系统代理。"""
    import base64
    import urllib.request
    from nacl import encoding, public
    import release as R
    c = read_cred()
    if keystore_sha256() != norm_hex(PINNED_SHA256):
        raise AndroidError("本机证书指纹 ≠ PINNED_SHA256 —— 不上传")
    tok = R.gh_token()
    if not tok:
        raise AndroidError("Git 凭据管理器里拿不到 GitHub 令牌")
    hdr = {"Accept": "application/vnd.github+json", "User-Agent": "turtle-android-release", "Authorization": "Bearer " + tok}
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    base = "https://api.github.com/repos/%s/actions/secrets" % R.GH_REPO
    with op.open(urllib.request.Request(base + "/public-key", headers=hdr), timeout=60) as r:
        pk = json.loads(r.read().decode("utf-8"))
    box = public.SealedBox(public.PublicKey(pk["key"].encode("utf-8"), encoding.Base64Encoder()))
    vals = {"ANDROID_KEYSTORE_B64": base64.b64encode(open(KEYSTORE, "rb").read()).decode("ascii"),
            "ANDROID_KEY_PASSWORD": c["password"]}
    for name, v in vals.items():
        enc = base64.b64encode(box.encrypt(v.encode("utf-8"))).decode("ascii")
        body = json.dumps({"encrypted_value": enc, "key_id": pk["key_id"]}).encode("utf-8")
        req = urllib.request.Request(base + "/" + name, data=body, method="PUT",
                                     headers=dict(hdr, **{"Content-Type": "application/json"}))
        with op.open(req, timeout=60) as r:
            print("%s → HTTP %d" % (name, r.status))
    with op.open(urllib.request.Request(base + "?per_page=100", headers=hdr), timeout=60) as r:
        names = sorted(s["name"] for s in json.loads(r.read().decode("utf-8")).get("secrets", []))
    miss = [n for n in vals if n not in names]
    print("回读：仓库 secrets 里%s" % ("两项都在" if not miss else "缺 %s" % miss))
    return 1 if miss else 0


def cmd_fingerprint(_a):
    h = keystore_sha256()
    print(h)
    if not PINNED_SHA256:
        print("（PINNED_SHA256 还没填）")
        return 1
    if h != norm_hex(PINNED_SHA256):
        print("✗ 本机证书指纹 ≠ PINNED_SHA256")
        return 1
    print("✓ = PINNED_SHA256")
    return 0


def cmd_code(a):
    print(version_code(a.version))
    return 0


def verify_apk(apk, ver):
    if not os.path.isfile(apk):
        raise AndroidError("没有这个包：%s" % apk)
    code, out = run([build_tool("apksigner"), "verify", "--print-certs", apk], env=java_env())
    if code != 0:
        return ["apksigner verify 失败（退出码 %d）：%s" % (code, out.strip()[-300:])]
    code2, out2 = run([build_tool("aapt2"), "dump", "badging", apk])
    if code2 != 0:
        return ["aapt2 dump badging 失败（退出码 %d）" % code2]
    signers, badging = parse_apksigner(out), parse_badging(out2)
    if len(signers) != 1:
        print("── apksigner 原始输出(签名者解析出 %d 个) ──\n%s" % (len(signers), out.strip()[-2500:]))
    print("签名者 %d 个 %s / 包名 %s / versionName %s / versionCode %s / %.1f MB" % (
        len(signers), [s[:16] + "…" for s in signers], badging.get("name"), badging.get("versionName"),
        badging.get("versionCode"), os.path.getsize(apk) / 1048576.0))
    return check_apk(signers, badging, ver)


def cmd_verify(a):
    ver = a.version or project_version()
    probs = verify_apk(a.apk, ver)
    if probs:
        for p in probs:
            print("✗ " + p)
        return 1
    print("✓ 安装包核对通过（%s / 正式证书 / %s / versionCode %d）" % (PACKAGE, ver, version_code(ver)))
    return 0


def cmd_build(a):
    ver = project_version()
    want = str(version_code(ver))
    have = preset_android()
    if have != want:
        raise AndroidError("export_presets.cfg 的 Android version/code = %r，应为 %s（version_code(%s)）—— release.py bump 会写，手工改也行"
                           % (have, want, ver))
    c = read_cred()
    out = os.path.abspath(a.out or os.path.join(REPO, "build", "android", "turtle-arena-%s.apk" % ver))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    env = dict(os.environ, GODOT_ANDROID_KEYSTORE_RELEASE_PATH=KEYSTORE, GODOT_ANDROID_KEYSTORE_RELEASE_USER=ALIAS,
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=c["password"])
    if os.path.isdir(LOCAL_JDK) and "JAVA_HOME" not in os.environ:
        env["JAVA_HOME"] = LOCAL_JDK
    print("出包 %s → %s" % (ver, out))
    code, log = run([GODOT_LOCAL, "--headless", "--path", REPO, "--export-release", "Android", out], env=env, timeout=1800)
    if code != 0 or not os.path.isfile(out):
        print(log[-1500:])
        raise AndroidError("Godot 导出失败（退出码 %d）" % code)
    probs = verify_apk(out, ver)
    if probs:
        for p in probs:
            print("✗ " + p)
        return 1
    print("✓ 出包并核对通过：%s" % out)
    return 0


# ── 自测 ───────────────────────────────────────────────────────────────

def selftest():
    n = [0]
    bad = []

    def ok(name, cond):
        n[0] += 1
        if not cond:
            bad.append(name)

    ok("0.23.5 → 23005", version_code("0.23.5") == 23005)
    ok("单调: 0.23.10 > 0.23.9", version_code("0.23.10") > version_code("0.23.9"))
    ok("单调: 0.24.0 > 0.23.999", version_code("0.24.0") > version_code("0.23.999"))
    ok("单调: 1.0.0 > 0.999.999", version_code("1.0.0") > version_code("0.999.999"))
    ok("大于旧预设里的 12", version_code("0.23.5") > 12)
    for badv in ("0.23", "0.23.5-wip", "0.1000.0", "0.23.1000", "v0.23.5", ""):
        try:
            version_code(badv)
            ok("拒 %r" % badv, False)
        except AndroidError:
            ok("拒 %r" % badv, True)
    pin = "ab" * 32
    signer_txt = "Signer #1 certificate DN: CN=Turtle Arena\nSigner #1 certificate SHA-256 digest: %s\nSigner #1 certificate SHA-1 digest: 00\n" % pin
    ok("apksigner 解析", parse_apksigner(signer_txt) == [pin])
    ok("apksigner 冒号写法也认", parse_apksigner("Signer #1 certificate SHA-256 digest: AB:AB\n") == ["abab"])
    ok("apksigner 按 SDK 段分组的写法也认、同一张证书只算一次", parse_apksigner(
        "Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: %s\n"
        "Signer (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: %s\n" % (pin, pin)) == [pin])
    bad_txt = "package: name='%s' versionCode='23005' versionName='0.23.5' platformBuildVersionName='14'\nsdkVersion:'24'\n" % PACKAGE
    bd = parse_badging(bad_txt)
    ok("badging 解析", bd.get("name") == PACKAGE and bd.get("versionCode") == "23005" and bd.get("versionName") == "0.23.5")
    ok("keytool 指纹解析", parse_keytool_sha256("Certificate fingerprints:\n\t SHA1: 00:11\n\t SHA256: AB:CD:EF\n") == "abcdef")
    ok("全对 ⇒ 通过", check_apk([pin], bd, "0.23.5", pinned=pin) == [])
    ok("调试证书 ⇒ 拒", any("指纹" in p for p in check_apk(["cd" * 32], bd, "0.23.5", pinned=pin)))
    ok("没固定指纹 ⇒ 拒", any("PINNED" in p for p in check_apk([pin], bd, "0.23.5", pinned="")))
    ok("两个签名者 ⇒ 拒", check_apk([pin, pin], bd, "0.23.5", pinned=pin) != [])
    ok("版本名不符(tag 指错提交) ⇒ 拒", any("versionName" in p for p in check_apk([pin], bd, "0.23.6", pinned=pin)))
    bd2 = dict(bd, versionCode="12")
    ok("versionCode 没跟着改 ⇒ 拒", any("versionCode" in p for p in check_apk([pin], bd2, "0.23.5", pinned=pin)))
    bd3 = dict(bd, name="com.example.other")
    ok("包名不符 ⇒ 拒", any("包名" in p for p in check_apk([pin], bd3, "0.23.5", pinned=pin)))
    ## 仓库现状: Android 预设的 version/code = 版本算法（release.py bump 维护；verify_version 也守）
    try:
        ver = project_version()
        ok("仓库: export_presets Android version/code = version_code(%s)" % ver, preset_android() == str(version_code(ver)))
    except AndroidError as e:
        ok("仓库读预设: %s" % e, False)
    ok("PINNED_SHA256 已固定且是 64 位十六进制", len(norm_hex(PINNED_SHA256)) == 64)
    print("分母 %d 条" % n[0])
    if bad:
        for b in bad:
            print("FAIL " + b)
        return 1
    print("ALL OK — android_release 自测 %d 条" % n[0])
    return 0


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd")
    sp.add_parser("selftest")
    sp.add_parser("keygen")
    sp.add_parser("fingerprint")
    sp.add_parser("gh-secrets")
    x = sp.add_parser("code")
    x.add_argument("version")
    x = sp.add_parser("verify")
    x.add_argument("apk")
    x.add_argument("--version")
    x = sp.add_parser("build")
    x.add_argument("--out")
    a = ap.parse_args(argv)
    try:
        if a.cmd in (None, "selftest"):
            return selftest()
        return {"keygen": cmd_keygen, "fingerprint": cmd_fingerprint, "gh-secrets": cmd_gh_secrets, "code": cmd_code,
                "verify": cmd_verify, "build": cmd_build}[a.cmd](a) or 0
    except AndroidError as e:
        print("✗ " + str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
