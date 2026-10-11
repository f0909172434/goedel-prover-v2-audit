#!/bin/bash
# 主跑 Lean 檢查（在 CPU VM 上跑，不在 GPU VM 上）。
# 第一輪：官方 compile.py、官方 PROOF_TIMEOUT 300 秒、WORKERS 個 worker（官方 pipeline.sh 用 32）。
# 第二輪：只把第一輪逾時／REPL 系統錯誤的證明，用 PROOF_TIMEOUT=$RETRY_TIMEOUT 重驗。兩輪結果分開存。
# 用法：run_lean_main.sh [WORKERS=32] [RETRY_TIMEOUT=1200]
set -uo pipefail
W=${1:-32}; RT=${2:-1200}
A=$HOME/audit; G=$A/Goedel-Prover-V2; PY=$A/venv/bin/python; R=$A/results/main-bf16
export PATH=$HOME/.elan/bin:$PATH
exec 9>$A/lean.lock; flock -n 9 || { echo "lean run already active"; exit 1; }
cd $G
nproc > $R/lean_host_nproc.txt; lscpu | grep -E "Model name|^CPU\(s\)" > $R/lean_host_cpu.txt

for d in $R/shard_*; do
  [ -f $d/DONE ] || continue
  [ -f $d/LEAN_DONE ] && continue
  t0=$(date +%s)
  PROOF_TIMEOUT=300 $PY src/compile.py --input_path $d/to_inference_codes.json \
    --output_path $d/code_compilation_repl.json --cpu $W > $d/compile.log 2>&1
  rc=$?
  echo "$(basename $d) rc=$rc seconds=$(( $(date +%s) - t0 )) workers=$W" >> $R/lean_progress.log
  [ $rc -eq 0 ] && [ -f $d/code_compilation_repl.json ] && touch $d/LEAN_DONE
done

# 第二輪：收集逾時／系統錯誤的證明重驗
$PY - "$R" <<'EOF'
import json, glob, os, sys
R = sys.argv[1]; todo = []
for d in sorted(glob.glob(f"{R}/shard_*")):
    p = f"{d}/code_compilation_repl.json"
    if not os.path.exists(p): continue
    codes = {c["problem_id"]: c for c in json.load(open(f"{d}/to_inference_codes.json"))}
    for r in json.load(open(p)):
        if r["compilation_result"].get("system_errors"):
            todo.append(codes[r["name"]])
json.dump(todo, open(f"{R}/retry_inputs.json", "w"))
print("retry candidates:", len(todo))
EOF
if [ -s $R/retry_inputs.json ] && [ ! -f $R/RETRY_DONE ]; then
  t0=$(date +%s)
  PROOF_TIMEOUT=$RT $PY src/compile.py --input_path $R/retry_inputs.json \
    --output_path $R/retry_compilation_t${RT}.json --cpu $W > $R/retry_compile.log 2>&1
  echo "retry rc=$? seconds=$(( $(date +%s) - t0 )) timeout=$RT workers=$W" >> $R/lean_progress.log
  touch $R/RETRY_DONE
fi
echo LEAN_ALL_DONE >> $R/lean_progress.log
