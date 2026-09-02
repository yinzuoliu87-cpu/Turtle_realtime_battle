#!/usr/bin/env bash
# 800 队快照跑完之后的收尾 —— 严格照方案书 20260902 §7.5 的顺序。
#
# ★为什么做成脚本而不是每次手打: §7.5 里第 ② 步「备份旧池」是**不可逆操作前的最后一道保险**,
#   而它最容易在"我记得刚才备份过了"的时候被跳过。写进脚本就跳不掉。
#
# 跑法:  bash tools/cohort_finish.sh
# 任何一步失败立刻停(set -e), 不会带着半成品往下走。
set -e
cd "$(dirname "$0")/.."

DATE=$(date +%Y%m%d)
ATTIC="docs/plans/attic/ghost_seed-旧池-${DATE}.json"

echo "══════ ① 合并 16 个分片(id 唯一性由脚本自己判) ══════"
python tools/cohort_shard.py --merge-only --shards 16

echo ""
echo "══════ ② 备份旧池(不可逆操作前的保险, 不许跳) ══════"
if [ -f "$ATTIC" ]; then
  echo "  已存在同名备份, 跳过: $ATTIC"
else
  cp -v data/ghost_seed.json "$ATTIC"
fi
python - <<'PY'
import hashlib, io, json, os, sys, glob
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
a = 'data/ghost_seed.json'
b = sorted(glob.glob('docs/plans/attic/ghost_seed-旧池-*.json'))[-1]
ha = hashlib.sha1(open(a, 'rb').read()).hexdigest()
hb = hashlib.sha1(open(b, 'rb').read()).hexdigest()
print("  原 sha1 %s" % ha)
print("  备份    %s" % hb)
assert ha == hb, "★备份与原文件不一致, 停"
d = json.load(io.open(a, encoding='utf-8'))
print("  旧池 %d 档 / %d 条 —— 已安全留档" % (len(d['brackets']), sum(len(v) for v in d['brackets'].values())))
PY

echo ""
echo "══════ ③ dry-run 自检(不过关它自己会拒写) ══════"
python tools/cohort_to_seed.py

echo ""
echo "══════ ④ 真写入 ══════"
python tools/cohort_to_seed.py --write

echo ""
echo "══════ ⑤ 流派验收(四条判据; 已证明在旧池上 FAIL) ══════"
set +e
python tools/cohort_strategy_report.py --pool tools/autoplay/cohort-snapshots.json
RC=$?
set -e
echo "  验收 rc=$RC  (0=四条全过)"

echo ""
echo "══════ ⑥ 全套门禁 ══════"
JOBS=2 bash run-tests.sh
