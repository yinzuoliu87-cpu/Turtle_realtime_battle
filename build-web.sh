#!/bin/bash
# build-web.sh — Web(itch.io) 一键导出 + 产物自检 + 打包
# 用法:  bash build-web.sh          (评审模式, 默认)
#        SHIP=1 bash build-web.sh   (上线模式: 关掉 REVIEW_DEMO, 真实对局/真实等级)
#
# 关键事实(2026-07-10 实测, 别再靠记忆):
#  · 单线程模板 web_nothreads_release.zip → 不需要 SAB / COOP-COEP 头, iOS Safari 能跑
#    验证方式: 导出的 index.wasm 里 pthread_create / __pthread / wasm_worker / emscripten_futex 全为 0 次
#  · index.html 必须在 zip 【根目录】(itch 要求)
#  · PowerShell 的 Compress-Archive 会因 index.pck 被占用而失败 → 用 python zipfile(共享读)
#  · 所有 400 个 .png.import 都是 compress/mode=0 (无损/VRAM未压缩) →
#    export_presets 里的 vram_texture_compression/for_desktop 其实【不生效】, 不是 bug
#  · python 读不了 Git Bash 的 /c/... 路径 → 脚本里一律 cd 到项目根后用相对路径
set -e

GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
# ★python 读不了 Git Bash 的 /c/... 路径 (FileNotFoundError) → 一律用【相对路径】喂 python
OUT="build/web"
ZIP="build/turtle-realtime-web.zip"

[ -f "$GODOT" ] || { echo "❌ 找不到 Godot: $GODOT (可用 GODOT 环境变量指定)"; exit 1; }

TPL="$HOME/AppData/Roaming/Godot/export_templates/4.6.3.stable/web_nothreads_release.zip"
[ -f "$TPL" ] || { echo "❌ 缺少单线程 Web 导出模板: $TPL"; exit 1; }

echo "▸ 清理旧产物"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "▸ 导入资源"
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1 || true

echo "▸ 导出 Web (release)"
"$GODOT" --headless --path "$DIR" --export-release "Web" "$OUT/index.html" > /tmp/web_export.log 2>&1
echo "  exit=$?"

# ─── 产物自检 (不只看退出码) ────────────────────────────────
fail=0
chk() { if [ "$2" = "0" ]; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=$((fail+1)); fi; }

echo "▸ 自检"
[ -f "$OUT/index.html" ] && chk "index.html 存在" 0 || chk "index.html 存在" 1
[ -f "$OUT/index.wasm" ] && chk "index.wasm 存在" 0 || chk "index.wasm 存在" 1
[ -f "$OUT/index.pck" ]  && chk "index.pck 存在" 0  || chk "index.pck 存在" 1

# 测试脚本不能进正式包
n=$(grep -c "res://tests/" /tmp/web_export.log || true)
[ "$n" = "0" ] && chk "tests/ 未打进包 (exclude_filter 生效)" 0 || chk "tests/ 未打进包 (实际 $n 处)" 1

# 必须是单线程模板
PT=$(python -c "d=open('$OUT/index.wasm','rb').read(); print(sum(d.count(k) for k in (b'pthread_create',b'__pthread',b'wasm_worker',b'emscripten_futex')))")
[ "$PT" = "0" ] && chk "单线程模板 (wasm 内 pthread 符号 = 0)" 0 || chk "单线程模板 (发现 $PT 个 pthread 符号 → 会要求 COOP/COEP 头, iOS 挂)" 1

echo "▸ 打包 (index.html 必须在 zip 根)"
python - "$OUT" "$ZIP" <<'PY'
import zipfile, os, sys
src, dst = sys.argv[1], sys.argv[2]
if os.path.exists(dst): os.remove(dst)
z = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=6)
for f in sorted(os.listdir(src)):
    p = os.path.join(src, f)
    if os.path.isfile(p):
        z.write(p, arcname=f)          # arcname = 纯文件名, 无子目录前缀
z.close()
zz = zipfile.ZipFile(dst)
names = zz.namelist()
assert "index.html" in names, "index.html 不在 zip 根!"
assert not any("/" in n for n in names), "zip 里有子目录前缀!"
assert zz.testzip() is None, "zip 损坏"
print("  [OK] zip self-check: %d entries, %.1f MB" % (len(names), os.path.getsize(dst) / 1048576.0))   # 纯ASCII: Windows GBK 控制台打不出 U+2713
PY

echo
if [ "$fail" = "0" ]; then
  echo "✅ Web 构建完成: $ZIP"
  echo "   上传 itch.io: 勾选 \"This file will be played in the browser\""
  echo "   ⚠ 上线前确认 REVIEW_DEMO_DEFAULT=false 或用 SHIP=1 构建 (否则玩家打的是沙包假人, 且赛季等级不生效)"
else
  echo "❌ 自检失败 $fail 项"; exit 1
fi
