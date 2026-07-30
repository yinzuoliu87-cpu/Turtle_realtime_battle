#!/usr/bin/env bash
# 训龟大师 A/B 对照实验 (2026-07-30)
#
# 为什么要这个: 第五轮同时做了两件事 —— ①关掉训龟大师 ②改了 11 项数值 + 小将。
#   两者混在一起, 从"第四轮 vs 第五轮"的差里【分不出】哪部分是大师造成的。
#   要量出大师的影响只有一个干净办法: **同一份代码、同一个种子, 只切换大师开/关**。
#
# 做法: 跑同一批对子两遍(NO_TRAINER 环境变量控制), 比较每只龟的胜率差。
#   NO_TRAINER 是 _spawn_trainers() 认的环境变量 —— 但 _duel.gd 里写死了 RB.NO_TRAINER = true,
#   所以 A 组(有大师)要用 TRAINER_AB_ON=1 让 _duel.gd 跳过那行(见下面的 sed 临时改法)。
#
# 跑法: bash run-trainer-ab.sh          # 默认每组 240 对
#       PAIRS=480 bash run-trainer-ab.sh
#
# ⚠ 它会临时改 tests/_duel.gd 再改回来 —— 跑之前确认没有未提交的改动在那个文件里。

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
PAIRS="${PAIRS:-240}"
SHARDS="${SHARDS:-12}"
SEED="${SEED:-20260728}"
DUEL="$DIR/tests/_duel.gd"

[ -f "$GODOT" ] || { echo "Godot not found: $GODOT"; exit 1; }

# ★动 _duel.gd 之前先确认它是干净的 —— 否则 trap 还原会把别人的改动一起冲掉
if ! git -C "$DIR" diff --quiet -- tests/_duel.gd; then
	echo "[FAIL] tests/_duel.gd 有未提交改动 —— 本脚本要临时改它, 先提交或 stash"
	exit 1
fi
cp "$DUEL" "$DUEL.abbak"
restore() { [ -f "$DUEL.abbak" ] && mv -f "$DUEL.abbak" "$DUEL"; }
trap restore EXIT INT TERM

run_group() {
	local tag="$1" want_trainer="$2"
	local out="tools/duelab-$tag"
	rm -rf "$DIR/$out" "$DIR/$out-log"; mkdir -p "$DIR/$out" "$DIR/$out-log"
	# A 组要【有】大师 → 把 _duel.gd 里那行关大师改成 false, 并把首场体检的 quit 去掉
	if [ "$want_trainer" = "1" ]; then
		sed -i 's|RB.NO_TRAINER = true|RB.NO_TRAINER = false|' "$DUEL"
		sed -i 's|^\t\tget_tree().quit(1)$|\t\tpass|' "$DUEL"
	else
		cp "$DUEL.abbak" "$DUEL"
	fi
	echo "── 组 $tag (训龟大师: $([ "$want_trainer" = 1 ] && echo 开 || echo 关)) · 每组 $PAIRS 对 ──"
	local pids=()
	for i in $(seq 0 $((SHARDS - 1))); do
		SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED="$SEED" DUEL_LEVEL=5 DUEL_LIMIT=$((PAIRS / SHARDS)) \
			DUEL_SHARD="$i" DUEL_SHARDS="$SHARDS" DUEL_OUT="res://$out" \
			"$GODOT" --headless --audio-driver Dummy --path "$DIR" res://tests/_duel.tscn \
			> "$DIR/$out-log/s$i.log" 2>&1 &
		pids+=($!)
	done
	for p in "${pids[@]}"; do wait "$p" || true; done
	local n; n=$(ls "$DIR/$out"/duel-*.csv 2>/dev/null | wc -l)
	local tr; tr=$(grep -h "训龟大师在场" "$DIR/$out-log"/*.log 2>/dev/null | grep -oE "在场 [0-9]+ 个" | sort | uniq -c | tr '\n' ' ')
	echo "   CSV $n/$SHARDS · 体检: $tr"
}

run_group "on" 1
run_group "off" 0
restore

echo ""
echo "=== 对照 (只有训龟大师这一个变量) ==="
python "$DIR/tools/duel_compare.py" --old tools/duelab-on --new tools/duelab-off
