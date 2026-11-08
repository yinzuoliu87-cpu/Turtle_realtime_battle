#!/bin/bash
# build-web.sh — Web(itch.io) 一键导出 + 产物自检 + 打包
# 用法:  bash build-web.sh          (评审模式, 默认)
#        SHIP=1 bash build-web.sh   (上线模式: 关掉 REVIEW_DEMO, 真实对局/真实等级)
#        bash build-web.sh player   (网页录像播放器 · 2026-11-08: 预设 WebPlayer → build/webplayer/ +
#                                    build/turtle-webplayer-<版本>.zip; 部署 python tools/deploy.py <版本> --only player,
#                                    见 server/player/README.md。★发版用的包必须在 tag 那一提交、工作区干净时打)
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
PY="${PY:-python}"
MODE="${1:-web}"
case "$MODE" in
  web)    PRESET="Web";       OUT="build/web";       ZIP="build/turtle-realtime-web.zip" ;;
  player) PRESET="WebPlayer"; OUT="build/webplayer"
          VER=$(sed -n 's/^config\/version="\(.*\)".*/\1/p' project.godot | head -1)
          ZIP="build/turtle-webplayer-$VER.zip" ;;
  *) echo "用法: bash build-web.sh [web|player]"; exit 2 ;;
esac
LOG="/tmp/${PRESET}_export.log"

[ -f "$GODOT" ] || { echo "❌ 找不到 Godot: $GODOT (可用 GODOT 环境变量指定)"; exit 1; }

TPL="$HOME/AppData/Roaming/Godot/export_templates/4.6.3.stable/web_nothreads_release.zip"
[ -f "$TPL" ] || { echo "❌ 缺少单线程 Web 导出模板: $TPL"; exit 1; }

echo "▸ 清理旧产物"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "▸ 导入资源"
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1 || true

echo "▸ 导出 $PRESET (release)"
"$GODOT" --headless --path "$DIR" --export-release "$PRESET" "$OUT/index.html" > "$LOG" 2>&1
echo "  exit=$?"

# ─── 产物自检 (不只看退出码) ────────────────────────────────
fail=0
chk() { if [ "$2" = "0" ]; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=$((fail+1)); fi; }

echo "▸ 自检"
[ -f "$OUT/index.html" ] && chk "index.html 存在" 0 || chk "index.html 存在" 1
[ -f "$OUT/index.wasm" ] && chk "index.wasm 存在" 0 || chk "index.wasm 存在" 1
[ -f "$OUT/index.pck" ]  && chk "index.pck 存在" 0  || chk "index.pck 存在" 1

# 测试脚本不能进正式包
n=$(grep -c "res://tests/" "$LOG" || true)
[ "$n" = "0" ] && chk "tests/ 未打进包 (exclude_filter 生效)" 0 || chk "tests/ 未打进包 (实际 $n 处)" 1

# 必须是单线程模板
PT=$("$PY" -c "d=open('$OUT/index.wasm','rb').read(); print(sum(d.count(k) for k in (b'pthread_create',b'__pthread',b'wasm_worker',b'emscripten_futex')))")
[ "$PT" = "0" ] && chk "单线程模板 (wasm 内 pthread 符号 = 0)" 0 || chk "单线程模板 (发现 $PT 个 pthread 符号 → 会要求 COOP/COEP 头, iOS 挂)" 1

if [ "$MODE" = "player" ]; then
  # 产物戳: 版本 + 提交(server/player/player_ops.py install 核版本; tools/deploy.py --only player 核提交 = tag)
  SHA=$(git rev-parse HEAD)
  DIRTY=$(git diff --quiet HEAD -- . && echo false || echo true)   # 按内容比(导入会改 .import 的行尾, status 会误报)
  printf '{"version": "%s", "sha": "%s", "dirty": %s, "built_at": "%s", "preset": "WebPlayer"}\n' \
    "$VER" "$SHA" "$DIRTY" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/webplayer.json"
  chk "产物戳 webplayer.json (版本 $VER · 提交 ${SHA:0:8} · 工作区有改动=$DIRTY)" 0
  # 首开要下载多少: wasm / js / html 由 Caddy 现压 gzip, pck 原样(server/player/player.caddy)
  "$PY" - "$OUT" <<'PY'
import gzip, os, sys
d = sys.argv[1]
tot_raw = tot_wire = 0
for f in sorted(os.listdir(d)):
    p = os.path.join(d, f)
    raw = os.path.getsize(p)
    wire = len(gzip.compress(open(p, "rb").read(), 6)) if f.endswith((".wasm", ".js", ".html")) else raw
    tot_raw += raw
    tot_wire += wire
    print("  %-34s %8.1f MB  (wire %6.1f MB)" % (f, raw / 1048576.0, wire / 1048576.0))
print("  [size] total %.1f MB, first open downloads ~%.1f MB" % (tot_raw / 1048576.0, tot_wire / 1048576.0))
PY
fi

echo "▸ 打包 (index.html 必须在 zip 根)"
"$PY" - "$OUT" "$ZIP" <<'PY'
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
if [ "$fail" = "0" ] && [ "$MODE" = "player" ]; then
  echo "✅ 网页录像播放器构建完成: $ZIP"
  echo "   部署: python tools/deploy.py $VER --only player [--env beta]  (server/player/README.md)"
elif [ "$fail" = "0" ]; then
  echo "✅ Web 构建完成: $ZIP"
  echo "   上传 itch.io: 勾选 \"This file will be played in the browser\""
  echo "   ⚠ 上线前确认 REVIEW_DEMO_DEFAULT=false 或用 SHIP=1 构建 (否则玩家打的是沙包假人, 且赛季等级不生效)"
else
  echo "❌ 自检失败 $fail 项"; exit 1
fi
