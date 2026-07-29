#!/usr/bin/env bash
# 龟×技能 胜率全循环赛跑批器 (第四轮起固化成脚本; 前三轮是手敲命令行)
#
# 84 组合(28龟 × 3选1主动技)全循环 = 3486 对, 每组合 83 场。8 分片并行。
#
# ★种子必须与上一轮相同, 否则两轮不可比 —— 唯一变量应该是平衡改动本身。
#   前三轮都用 20260728, 这里默认沿用。
#
# 跑法:
#   bash run-duel.sh            # 默认输出 tools/duel4
#   OUT=duel5 bash run-duel.sh  # 换目录
#   SHARDS=4 bash run-duel.sh   # 少开几个进程(这台机器跑重载 Godot 有过 BSOD 记录)
#
# 出报表:
#   python tools/duel_report.py --dir tools/duel4

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
OUT="${OUT:-duel4}"
SHARDS="${SHARDS:-8}"
SEED="${SEED:-20260728}"
LEVEL="${LEVEL:-5}"

[ -f "$GODOT" ] || { echo "Godot not found: $GODOT"; exit 1; }

echo "=== 胜率全循环赛 ==="
echo "  输出   tools/$OUT"
echo "  分片   $SHARDS"
echo "  种子   $SEED   (★与上一轮相同才可比)"
echo "  等级   Lv$LEVEL / 无装备 / 关训龟大师"
echo ""

rm -rf "$DIR/tools/$OUT"; mkdir -p "$DIR/tools/$OUT"
mkdir -p "$DIR/tools/$OUT-log"

pids=()
for i in $(seq 0 $((SHARDS - 1))); do
	SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED="$SEED" DUEL_LEVEL="$LEVEL" \
		DUEL_SHARD="$i" DUEL_SHARDS="$SHARDS" DUEL_OUT="res://tools/$OUT" \
		"$GODOT" --headless --audio-driver Dummy --path "$DIR" res://tests/_duel.tscn \
		> "$DIR/tools/$OUT-log/shard-$i.log" 2>&1 &
	pids+=($!)
	echo "  分片 $i 已启动 (pid ${pids[-1]})"
done

echo ""
echo "  等 $SHARDS 个分片跑完(上一轮 8 分片约 2.8 小时墙钟)…"
fail=0
for p in "${pids[@]}"; do
	wait "$p" || fail=$((fail + 1))
done

echo ""
echo "=== 产物体检 ==="
# ★判据是【产物】不是退出码 —— 分片可能 rc=0 却没写出 CSV。
n_csv=$(ls "$DIR/tools/$OUT"/duel-*.csv 2>/dev/null | wc -l)
echo "  CSV 文件数: $n_csv / $SHARDS"
rows=0
for f in "$DIR/tools/$OUT"/duel-*.csv; do
	[ -f "$f" ] || continue
	r=$(($(wc -l < "$f") - 1))   # 减表头
	rows=$((rows + r))
	printf "    %-14s %5d 场\n" "$(basename "$f")" "$r"
done
echo "  总场次: $rows  (期望 3486)"
echo "  非零退出的分片: $fail"

if [ "$n_csv" -ne "$SHARDS" ] || [ "$rows" -lt 3400 ]; then
	echo ""
	echo "[FAIL] 产物不完整 —— 看 tools/$OUT-log/shard-*.log"
	exit 1
fi

echo ""
python "$DIR/tools/duel_report.py" --dir "tools/$OUT"
