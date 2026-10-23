# -*- coding: utf-8 -*-
"""iOS 产物核对（只读）。2026-10-20 建，给 .github/workflows/testflight.yml 用。

【为什么判据落在产物上】memory fb-verify-artifact-not-steps：2026-07-29 改竖屏那次，
CI 里中间步骤自检是绿的，而 IPA 里还是旧值 —— xcodebuild 会按 build settings 重新生成 Info.plist。
所以这里分三档，越往后越接近「装到手机上的那个东西」：

  project <导出目录>    Godot 导出的 Xcode 工程：Info.plist 模板 + project.pbxproj 里的 build settings
                        （模板里是 $(MARKETING_VERSION) 这类变量，按 pbxproj 解出来再比）
  app <xxx.app>         xcodebuild 编出来的 .app（Info.plist 已是二进制、变量已展开）
  ipa <xxx.ipa>         签名导出的 IPA（拆 zip 读 Payload/*.app/Info.plist）

断言（三档共用）：
  ① CFBundleShortVersionString == --version（project.godot 的 config/version）
  ② CFBundleVersion == --build（CI 自增构建号，纯数字）
  ③ CFBundleIdentifier == --bundle-id
  ④ ITSAppUsesNonExemptEncryption == false（方案书 §4.4 / §B9 结论）
  ⑤ 最低系统 >= --min-ios（Apple 2026-09-09 起要求 >= 13）
  ⑥ 仅 iPhone（UIDeviceFamily == [1] / TARGETED_DEVICE_FAMILY = "1"）
  ⑦ PrivacyInfo.xcprivacy 能解析、不追踪、收集类型 == 方案书附录 A 六类（全部关联身份、不追踪、App Functionality）
  ⑧ 图标：project 档 1024×1024 PNG 且无 alpha 通道；app/ipa 档有 CFBundlePrimaryIcon + Assets.car

用法：
  python tools/ios_artifact_check.py project build/ios --version 0.21.3 --build 101 --bundle-id com.luckyz.turtlearena
  python tools/ios_artifact_check.py ipa build/ipa/turtle.ipa --version ... --build ... --bundle-id ...
通过打 ALL OK，任一条不过打 [FAIL] 并退出 1。只用标准库（CI 的 macOS runner 上不装 Pillow 也能跑）。
"""
import argparse
import glob
import io
import os
import plistlib
import re
import struct
import sys
import zipfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# ⑦ 的外部尺子：docs/plans/20261020-AppStore上架.md 附录 A（App 隐私问卷草稿）。
#   export_presets.cfg 的 privacy/collected_data/* 必须与它一致 —— 两边不一致就是这里红。
EXPECTED_COLLECTED = {
    "NSPrivacyCollectedDataTypeEmailAddress",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeGameplayContent",
    "NSPrivacyCollectedDataTypeCustomerSupport",
    "NSPrivacyCollectedDataTypeCrashData",
    "NSPrivacyCollectedDataTypeOtherDiagnosticData",
}
PURPOSE_APP = "NSPrivacyCollectedDataTypePurposeAppFunctionality"

fails = []
passes = []


def check(name, ok, detail=""):
    (passes if ok else fails).append(name)
    print(("  [ok]   " if ok else "  [FAIL] ") + name + (("  —— " + detail) if detail else ""))


def ver_tuple(s):
    return tuple(int(x) for x in re.findall(r"\d+", str(s))[:3])


# ---------- PNG 头（不依赖 Pillow） ----------
def png_info(data):
    """返回 (宽, 高, 有无 alpha)。color type 4/6 带 alpha 通道；3(调色板) 带 tRNS 块也算。"""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h, _depth, ctype = struct.unpack(">IIBB", data[16:26])
    alpha = ctype in (4, 6)
    idat = data.find(b"IDAT")
    head = data[:idat] if idat > 0 else data
    if b"tRNS" in head:
        alpha = True
    return w, h, alpha


# ---------- 共用断言 ----------
def check_info(info, a, min_os_key):
    check("① CFBundleShortVersionString == %s" % a.version,
          str(info.get("CFBundleShortVersionString")) == a.version, "实际 %r" % info.get("CFBundleShortVersionString"))
    bv = str(info.get("CFBundleVersion"))
    check("② CFBundleVersion == %s（纯数字）" % a.build, bv == a.build and bv.isdigit(), "实际 %r" % bv)
    check("③ CFBundleIdentifier == %s" % a.bundle_id,
          str(info.get("CFBundleIdentifier")) == a.bundle_id, "实际 %r" % info.get("CFBundleIdentifier"))
    enc = info.get("ITSAppUsesNonExemptEncryption", "<缺>")
    check("④ ITSAppUsesNonExemptEncryption == false", enc is False, "实际 %r" % (enc,))
    mo = info.get(min_os_key)
    check("⑤ 最低系统 >= %s" % a.min_ios, mo is not None and ver_tuple(mo) >= ver_tuple(a.min_ios),
          "%s = %r" % (min_os_key, mo))


def check_privacy(data, where):
    try:
        p = plistlib.loads(data)
    except Exception as e:  # noqa: BLE001
        check("⑦ PrivacyInfo.xcprivacy 能解析（%s）" % where, False, str(e))
        return
    check("⑦ PrivacyInfo.xcprivacy 能解析（%s）" % where, True)
    check("⑦ NSPrivacyTracking == false", p.get("NSPrivacyTracking") is False, "实际 %r" % p.get("NSPrivacyTracking"))
    types = p.get("NSPrivacyCollectedDataTypes") or []
    got = {t.get("NSPrivacyCollectedDataType") for t in types}
    check("⑦ 收集类型 == 附录 A 六类", got == EXPECTED_COLLECTED,
          "多 %s / 少 %s" % (sorted(got - EXPECTED_COLLECTED), sorted(EXPECTED_COLLECTED - got)))
    bad = [t.get("NSPrivacyCollectedDataType") for t in types
           if t.get("NSPrivacyCollectedDataTypeLinked") is not True
           or t.get("NSPrivacyCollectedDataTypeTracking") is not False
           or PURPOSE_APP not in (t.get("NSPrivacyCollectedDataTypePurposes") or [])]
    check("⑦ 每类都是 关联身份 / 不追踪 / App Functionality", not bad, "不符: %s" % bad)
    api = p.get("NSPrivacyAccessedAPITypes") or []
    check("⑦ Required Reason API 有声明（>=1 类且每类有理由）",
          len(api) >= 1 and all(x.get("NSPrivacyAccessedAPITypeReasons") for x in api), "%d 类" % len(api))


def check_bundle_icon(info, names):
    icons = info.get("CFBundleIcons") or {}
    prim = icons.get("CFBundlePrimaryIcon") or {}
    check("⑧ CFBundleIcons.CFBundlePrimaryIcon 存在", bool(prim), "实际 %r" % (icons,))
    check("⑧ .app 里有 Assets.car", any(n.endswith("Assets.car") for n in names))
    check("⑧ .app 里有 AppIcon*.png", any(re.search(r"AppIcon[^/]*\.png$", n) for n in names))


def check_device_family(fam):
    check("⑥ UIDeviceFamily == [1]（仅 iPhone）", list(fam or []) == [1], "实际 %r" % (fam,))


# ---------- 三档 ----------
def mode_project(a):
    root = a.path
    projs = glob.glob(os.path.join(root, "*.xcodeproj"))
    check("找到 *.xcodeproj（分母）", len(projs) == 1, "%r" % projs)
    if len(projs) != 1:
        return
    name = os.path.basename(projs[0])[:-len(".xcodeproj")]
    pbx = open(os.path.join(projs[0], "project.pbxproj"), encoding="utf-8").read()
    # 只看 App 目标的 Release 配置块：带 PRODUCT_BUNDLE_IDENTIFIER 且 CODE_SIGN_IDENTITY 是 Distribution 那一块
    blocks = re.findall(r"buildSettings = \{(.*?)\n\t\t\t\};", pbx, re.S)
    rel = [b for b in blocks if "PRODUCT_BUNDLE_IDENTIFIER" in b and "Apple Distribution" in b]
    check("pbxproj 里找到 App 目标的 Release 配置（分母）", len(rel) == 1, "找到 %d 块" % len(rel))
    if len(rel) != 1:
        return
    bs = {}
    for k, v in re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*) = (.*?);\s*$", rel[0], re.M):
        bs[k] = v.strip().strip('"')
    bs.setdefault("PRODUCT_NAME", name)
    plist_path = os.path.join(root, bs.get("INFOPLIST_FILE", "%s/%s-Info.plist" % (name, name)))
    raw = open(plist_path, "rb").read()
    info = plistlib.loads(raw)

    def expand(v):
        if not isinstance(v, str):
            return v
        return re.sub(r"\$\(([A-Za-z0-9_]+)\)", lambda m: bs.get(m.group(1), m.group(0)), v)

    info = {k: expand(v) for k, v in info.items()}
    info["_MinOS"] = bs.get("IPHONEOS_DEPLOYMENT_TARGET")
    print("  解出的 build settings: MARKETING_VERSION=%s CURRENT_PROJECT_VERSION=%s IPHONEOS_DEPLOYMENT_TARGET=%s TARGETED_DEVICE_FAMILY=%s"
          % (bs.get("MARKETING_VERSION"), bs.get("CURRENT_PROJECT_VERSION"),
             bs.get("IPHONEOS_DEPLOYMENT_TARGET"), bs.get("TARGETED_DEVICE_FAMILY")))
    check_info(info, a, "_MinOS")
    check("⑥ TARGETED_DEVICE_FAMILY = 1（仅 iPhone）", bs.get("TARGETED_DEVICE_FAMILY") == "1",
          "实际 %r" % bs.get("TARGETED_DEVICE_FAMILY"))
    pv = os.path.join(root, "PrivacyInfo.xcprivacy")
    check("⑦ PrivacyInfo.xcprivacy 存在", os.path.isfile(pv))
    if os.path.isfile(pv):
        check_privacy(open(pv, "rb").read(), "工程")
    check("⑦ PrivacyInfo.xcprivacy 已挂进 Resources 构建阶段", "PrivacyInfo.xcprivacy in Resources" in pbx)
    icon = os.path.join(root, name, "Images.xcassets", "AppIcon.appiconset", "Icon-1024.png")
    check("⑧ Icon-1024.png 存在", os.path.isfile(icon))
    if os.path.isfile(icon):
        pi = png_info(open(icon, "rb").read())
        check("⑧ Icon-1024.png 是 1024×1024 PNG", bool(pi) and pi[:2] == (1024, 1024), "实际 %r" % (pi,))
        check("⑧ Icon-1024.png 无 alpha 通道（App Store 拒带 alpha 的大图标）", bool(pi) and not pi[2])
    if a.icon_source:
        same = os.path.isfile(icon) and open(icon, "rb").read() == open(a.icon_source, "rb").read()
        pi2 = png_info(open(a.icon_source, "rb").read())
        # Godot 可能重新编码；逐字节不同不算错，只要尺寸 / 无 alpha 同样成立
        check("⑧ 源图 %s 是 1024×1024 且无 alpha" % a.icon_source, bool(pi2) and pi2 == (1024, 1024, False),
              "实际 %r%s" % (pi2, "（与工程里逐字节相同）" if same else ""))


def mode_app(a):
    app = a.path.rstrip("/\\")
    info = plistlib.load(open(os.path.join(app, "Info.plist"), "rb"))
    names = []
    for dp, _dn, fn in os.walk(app):
        names += [os.path.relpath(os.path.join(dp, f), app).replace("\\", "/") for f in fn]
    _common_bundle(a, info, names, lambda n: open(os.path.join(app, n), "rb").read())


def mode_ipa(a):
    z = zipfile.ZipFile(a.path)
    bad = z.testzip()
    check("IPA zip 完整（testzip）", bad is None, "坏条目 %r" % bad)
    apps = sorted({m.group(1) for n in z.namelist() for m in [re.match(r"(Payload/[^/]+\.app)/", n)] if m})
    check("IPA 里恰有一个 Payload/*.app（分母）", len(apps) == 1, "%r" % apps)
    if len(apps) != 1:
        return
    pre = apps[0] + "/"
    info = plistlib.loads(z.read(pre + "Info.plist"))
    names = [n[len(pre):] for n in z.namelist() if n.startswith(pre)]
    _common_bundle(a, info, names, lambda n: z.read(pre + n))


def _common_bundle(a, info, names, read):
    print("  Info.plist: %s (%s) %s MinimumOSVersion=%s"
          % (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"),
             info.get("CFBundleIdentifier"), info.get("MinimumOSVersion")))
    check_info(info, a, "MinimumOSVersion")
    check_device_family(info.get("UIDeviceFamily"))
    check("⑦ .app 根目录有 PrivacyInfo.xcprivacy", "PrivacyInfo.xcprivacy" in names)
    if "PrivacyInfo.xcprivacy" in names:
        check_privacy(read("PrivacyInfo.xcprivacy"), ".app")
    check_bundle_icon(info, names)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["project", "app", "ipa"])
    ap.add_argument("path")
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--min-ios", default="13.0")
    ap.add_argument("--icon-source", default="")
    a = ap.parse_args()
    print("iOS 产物核对 · %s · %s" % (a.mode, a.path))
    if not os.path.exists(a.path):
        print("[FAIL] 路径不存在: %s" % a.path)
        sys.exit(1)
    {"project": mode_project, "app": mode_app, "ipa": mode_ipa}[a.mode](a)
    print("  [分母] 断言 %d 条 · 通过 %d · 失败 %d" % (len(passes) + len(fails), len(passes), len(fails)))
    if fails or len(passes) < 10:
        print("[FAIL] %s" % ("; ".join(fails) if fails else "断言太少（%d 条），检查本身没跑起来" % len(passes)))
        sys.exit(1)
    print("ALL OK")


if __name__ == "__main__":
    main()
