#!/usr/bin/env bash
# Windows 测试包(用户 2026-07-29「出个 window 测试包，以压缩包的形式放在我的桌面上，exe 运行文件这样就好」)
#
# 用 export_presets.cfg 里【早就存在】的 WinDist 预设(导到 build/windist/斗龟场.exe) —— 别再另起炉灶。
# 出 debug 模板包, 与 iOS 测试包同口径: OS.is_debug_build()=true → 调试场按钮出现; 正常匹配不被劫持。
#
# 产物: 桌面/斗龟场-v<版本>-win.zip  (内含 斗龟场.exe + 斗龟场.pck)
# 跑法: bash build-win.sh

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
OUT="$DIR/build/windist"
DESKTOP="/c/Users/Louis/Desktop"

[ -f "$GODOT" ] || { echo "Godot not found: $GODOT (set GODOT env var)"; exit 1; }

# ★别用 grep -oP: Git Bash 的 grep 在非 UTF-8 locale 下直接拒跑 PCRE("-P supports only unibyte and UTF-8 locales")
VER="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$DIR/project.godot")"
[ -n "$VER" ] || { echo "读不到 project.godot 的 config/version"; exit 1; }
echo "=== 打 Windows 测试包 v$VER ==="

rm -rf "$OUT"; mkdir -p "$OUT"
"$GODOT" --headless --path "$DIR" --export-debug "WinDist" "$OUT/斗龟场.exe"

# ★退出码 0 不等于出了包 —— iOS 那次 Godot 照样吐了个非 ipa 的东西还 rc=0。判据只能是【产物本身】。
[ -f "$OUT/斗龟场.exe" ] || { echo "[FAIL] 没生成 exe"; ls -la "$OUT"; exit 1; }
# WinDist 预设开了 embed_pck → 资源打进 exe 里, 【不会】另外生成 .pck。
# 所以判据不能是"有没有 pck", 而是【资源到底在不在】: 二选一必须成立, 且 exe 不能是光壳(模板 exe 才 ~100MB)。
EXE_SZ=$(stat -c %s "$OUT/斗龟场.exe")
if [ -f "$OUT/斗龟场.pck" ]; then
	echo "  资源形态: 独立 .pck"
elif [ "$EXE_SZ" -gt 150000000 ]; then
	echo "  资源形态: 内嵌进 exe (embed_pck), 单文件 $((EXE_SZ/1024/1024)) MB"
else
	echo "[FAIL] 既没有 .pck, exe 也只有 $((EXE_SZ/1024/1024)) MB —— 像是没打进资源的空壳"; ls -la "$OUT"; exit 1
fi
echo "--- 产物 ---"; ls -la "$OUT"

ZIP="$DESKTOP/斗龟场-v$VER-win.zip"
rm -f "$ZIP"
# ★Git Bash 里没有 zip/unzip —— 借 PowerShell 的 Compress-Archive。
#   (第一版直接写 zip -qr, 报 "zip: command not found")
WOUT="$(cygpath -w "$OUT")"; WZIP="$(cygpath -w "$ZIP")"
powershell -NoProfile -NonInteractive -Command \
	"Compress-Archive -Path '$WOUT\\*' -DestinationPath '$WZIP' -CompressionLevel Optimal -Force"
[ -f "$ZIP" ] || { echo "[FAIL] zip 没生成"; exit 1; }

# ★验的是【解出来的东西】, 不是"命令没报错"。列一遍条目 + 比对解压后大小与源 exe 一致。
echo "--- zip 内容与完整性 ---"
powershell -NoProfile -NonInteractive -Command \
	"Add-Type -A System.IO.Compression.FileSystem; \
	 \$z=[IO.Compression.ZipFile]::OpenRead('$WZIP'); \
	 \$z.Entries | ForEach-Object { '{0,-24} 解压后 {1} 字节' -f \$_.Name, \$_.Length }; \
	 \$z.Dispose()"

echo ""
echo "✅ $ZIP  ($(( $(stat -c %s "$ZIP") / 1024 / 1024 )) MB, 源 exe $((EXE_SZ/1024/1024)) MB)"
