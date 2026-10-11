#!/bin/bash
# A100 試跑：同 10 題 × 8。先 bf16 KV（官方設定），再 FP8 KV，最後兩組各自 Lean 檢查。
set -uo pipefail
A=$HOME/audit; G=$A/Goedel-Prover-V2; M=$A/models/Goedel-Prover-V2-8B; PY=$A/venv/bin/python
export PATH=$HOME/.elan/bin:$PATH
exec 9>$A/pilot.lock; flock -n 9 || { echo "another pilot is running"; exit 1; }
cd $G
bash $A/scripts/make_variants.sh
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv > $A/env/gpu_a100.txt

gen() {  # $1 名稱, $2 inference 腳本
  local out=$A/results/$1; mkdir -p $out
  nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv -lms 5000 > $out/gpu_mem.csv & local smi=$!
  local t0=$(date +%s)
  $PY $2 --input_path $A/pilot.jsonl --model_path $M --output_dir $out --n 8 --gpu 1 \
    --inference_handler dpskcot --correction_round 0 --max_model_len 40960 --temp 1.0 > $out/inference.log 2>&1
  local rc=$?; local t1=$(date +%s); kill $smi
  echo "rc=$rc seconds=$((t1-t0))" > $out/inference_status.txt
  echo $((t1-t0)) > $out/wall_seconds.txt
}
lean() {
  local out=$A/results/$1; [ -f $out/to_inference_codes.json ] || return
  local c0=$(date +%s)
  $PY src/compile.py --input_path $out/to_inference_codes.json --output_path $out/code_compilation_repl.json --cpu 12 > $out/compile.log 2>&1
  echo "compile_rc=$? compile_seconds=$(( $(date +%s) - c0 ))" >> $out/inference_status.txt
  $PY $A/scripts/pilot_metrics.py $out $M $(cat $out/wall_seconds.txt) > $out/metrics_stdout.txt 2>&1
}

gen a100-bf16 src/inference_seedlog.py
gen a100-kvfp8 src/inference_seedlog_kvfp8.py
lean a100-bf16
lean a100-kvfp8
echo A100_PILOT_DONE > $A/a100_pilot_status.txt
