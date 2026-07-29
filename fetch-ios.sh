#!/usr/bin/env bash
# 从 GitHub Release「ios-latest」下 unsigned IPA 到桌面, 并【拆开验产物】。
#
# 为什么要拆开验: 2026-07-29 memory「产物才是判据不是中间步骤」——
#   CI 那步自检绿 ≠ 产物对。iOS 方向声明那次连栽两轮: 改在 xcodebuild 之前被重新生成覆盖,
#   工作流全绿、装到手机上功能是死的。只有读 IPA 里的 Info.plist 才算数。
#   curl 大文件 rc=0 也可能截断 → 必须验 zip 完整性。
#
# 跑法: bash fetch-ios.sh
#
# 注: Windows 做不出 .ipa(要 xcodebuild+codesign, 只有 macOS 有) → 只能走 CI。
#     Release 资产【公开可下载·不需 token】, artifact 则需要认证 —— 所以走 Release。

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-yinzuoliu87-cpu/Turtle_realtime_battle}"
DESKTOP="${DESKTOP:-/c/Users/Louis/Desktop}"
URL="https://github.com/$REPO/releases/download/ios-latest/turtle-ios-unsigned.ipa"

VER="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$DIR/project.godot")"
OUT="$DESKTOP/斗龟场-v$VER-unsigned.ipa"

echo "=== 取 iOS 包 v$VER ==="
echo "  源  $URL"
echo "  目标 $OUT"
rm -f "$OUT"
curl -fL --retry 3 -o "$OUT" "$URL" || { echo "[FAIL] 下载失败"; exit 1; }

SZ=$(stat -c %s "$OUT")
echo "  大小 $((SZ / 1024 / 1024)) MB"
[ "$SZ" -gt 50000000 ] || { echo "[FAIL] 只有 $((SZ/1024/1024)) MB —— 像是截断或错误页"; exit 1; }

echo ""
echo "--- ① zip 完整性(curl rc=0 也可能截断) ---"
WOUT="$(cygpath -w "$OUT")"
powershell -NoProfile -NonInteractive -Command \
  "Add-Type -A System.IO.Compression.FileSystem; \
   try { \$z=[IO.Compression.ZipFile]::OpenRead('$WOUT'); \
         '  条目 {0} 个, 解压后 {1} MB' -f \$z.Entries.Count, [math]::Round((\$z.Entries | Measure-Object Length -Sum).Sum/1MB,1); \
         \$z.Dispose(); '  zip OK' } \
   catch { '  [FAIL] zip 损坏: ' + \$_.Exception.Message; exit 1 }" || exit 1

echo ""
echo "--- ② 拆开读 Info.plist(唯一算数的判据) ---"
TMP="$(mktemp -d)"
powershell -NoProfile -NonInteractive -Command \
  "Add-Type -A System.IO.Compression.FileSystem; \
   \$z=[IO.Compression.ZipFile]::OpenRead('$WOUT'); \
   \$e=\$z.Entries | Where-Object { \$_.FullName -match '^Payload/[^/]+\.app/Info\.plist$' } | Select-Object -First 1; \
   if (-not \$e) { '  [FAIL] IPA 里没有 Payload/*.app/Info.plist'; \$z.Dispose(); exit 1 }; \
   [IO.Compression.ZipFileExtensions]::ExtractToFile(\$e, '$(cygpath -w "$TMP")\Info.plist', \$true); \
   \$z.Dispose(); '  取出 ' + \$e.FullName" || { rm -rf "$TMP"; exit 1; }

python - "$TMP/Info.plist" <<'PY'
# -*- coding: utf-8 -*-
import io, sys, plistlib
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
p = plistlib.load(io.open(sys.argv[1], 'rb'))
ver = p.get('CFBundleShortVersionString')
ori = p.get('UISupportedInterfaceOrientations', [])
print('  包内版本      %s' % ver)
print('  Bundle ID     %s' % p.get('CFBundleIdentifier'))
print('  方向声明      %s' % ori)
bad = []
if not ver:
    bad.append('读不到版本号')
if not any('Landscape' in str(o) for o in ori):
    bad.append('方向声明里没有横屏 —— 装上去会竖屏启动')
if any('Portrait' in str(o) for o in ori):
    bad.append('方向声明里有竖屏 —— 本项目应锁横屏')
print('')
print('  %s' % ('★产物体检通过' if not bad else '[FAIL] ' + ' / '.join(bad)))
sys.exit(1 if bad else 0)
PY
RC=$?
rm -rf "$TMP"
[ $RC -eq 0 ] || exit 1

echo ""
echo "--- ③ 包内版本 vs project.godot ---"
echo "  (上面「包内版本」应等于 $VER; 不等说明 Release 上还是旧包, CI 没跑完或失败了)"
echo ""
echo "✅ $OUT"
