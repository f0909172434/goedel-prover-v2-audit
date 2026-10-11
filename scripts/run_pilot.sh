#!/bin/bash
# 10 題 × 8 次試跑。先用官方設定（bf16、max_model_len 40960）；放不下才跑 FP8 KV 變體，各自一個目錄。
set -uo pipefail
A=$HOME/audit; G=$A/Goedel-Prover-V2; M=$A/models/Goedel-Prover-V2-8B; PY=$A/venv/bin/python
export PATH=$HOME/.elan/bin:$PATH
# 同一時間只能有一個試跑佔用 GPU
exec 9>$A/pilot.lock; flock -n 9 || { echo "another pilot is running"; exit 1; }
cd $G
$PY $A/scripts/select_pilot.py dataset/minif2f.jsonl $A/pilot.jsonl

run() {  # $1 名稱, $2 inference 腳本
  local out=$A/results/$1; mkdir -p $out
  nvidia-smi --query-gpu=memory.used --format=csv -lms 2000 > $out/gpu_mem.csv & local smi=$!
  local t0=$(date +%s)
  $PY $2 --input_path $A/pilot.jsonl --model_path $M --output_dir $out --n 8 --gpu 1 \
    --inference_handler dpskcot --correction_round 0 --max_model_len 40960 --temp 1.0 > $out/inference.log 2>&1
  local rc=$?; local t1=$(date +%s); kill $smi
  echo "rc=$rc seconds=$((t1-t0))" > $out/inference_status.txt
  [ $rc -ne 0 ] && return $rc
  # 生成與 Mathlib 建置並行；Lean 檢查要等環境建好
  until [ -f $A/env/setup_status.txt ]; do sleep 30; done
  local c0=$(date +%s)
  $PY src/compile.py --input_path $out/to_inference_codes.json --output_path $out/code_compilation_repl.json --cpu 16 > $out/compile.log 2>&1
  echo "compile_rc=$? compile_seconds=$(( $(date +%s) - c0 ))" >> $out/inference_status.txt
  $PY $A/scripts/pilot_metrics.py $out $M $((t1-t0)) > $out/metrics_stdout.txt 2>&1
}

run pilot-official src/inference.py
if [ $? -ne 0 ]; then
  # 變體：只加 kv_cache_dtype="fp8"，其他照官方；官方檔案不改
  sed 's/max_model_len=args.max_model_len, tensor_parallel_size=args.gpu)/max_model_len=args.max_model_len, tensor_parallel_size=args.gpu, kv_cache_dtype="fp8")/' \
    src/inference.py > src/inference_kvfp8.py
  grep -q 'kv_cache_dtype="fp8"' src/inference_kvfp8.py && run pilot-kvfp8 src/inference_kvfp8.py
fi
echo PILOT_DONE > $A/pilot_status.txt
