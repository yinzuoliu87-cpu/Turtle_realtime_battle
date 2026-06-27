#!/bin/bash
# run-tests.sh — headless 跑 Godot 单测 (自测用, 不依赖编辑器)
# 用法: bash run-tests.sh
# 输出: 每个测试 ✓/✗ + 末尾 ALL PASS (N/N) 或 FAIL 计数
#
# 找不到 Godot 时改 GODOT 变量。--import 首次或新增 class_name 后需先跑 (注册全局 class)。

GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$GODOT" ]; then
  echo "❌ Godot not found at: $GODOT  (set GODOT env var)"
  exit 1
fi

# 跑测试场景 (--quit-after 给足帧数让 await 完成)
# 回合制 test_damage 已随死引擎删除 (死代码清理 Chunk C); 实时版专项测=verify_dot_stacks。
"$GODOT" --headless --path "$DIR" res://tests/verify_dot_stacks.tscn --quit-after 300 2>&1 \
  | grep -E "✓|✗|PASS|FAIL|ALL|期望|SCRIPT ERROR|Parse Error|Cannot|inferred|Failed to"
