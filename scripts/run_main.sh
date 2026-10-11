#!/bin/bash
# 主跑生成：逐片跑官方 inference（只加種子修補），pass@32 標準模式，跳過已完成的分片。
# 可重入：Spot 搶占後 VM 重開，由 startup-script 再叫一次即可續跑。
# 用法：run_main.sh <variant: bf16|kvfp8>
set -uo pipefail
VARIANT=${1:-bf16}
A=$HOME/audit; G=$A/Goedel-Prover-V2; M=$A/models/Goedel-Prover-V2-8B; PY=$A/venv/bin/python
export PATH=$HOME/.elan/bin:$PATH
exec 9>$A/main.lock; flock -n 9 || { echo "main run already active"; exit 1; }
cd $G
[ -f src/inference_seedlog.py ] || bash $A/scripts/make_variants.sh
SCRIPT=src/inference_seedlog.py; [ "$VARIANT" = kvfp8 ] && SCRIPT=src/inference_seedlog_kvfp8.py
SH=$A/shards; [ -f $SH/manifest.json ] || $PY $A/scripts/make_shards.py dataset/minif2f.jsonl $SH 16
R=$A/results/main-$VARIANT; mkdir -p $R
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv > $R/gpu.txt

for f in $SH/shard_*.jsonl; do
  s=$(basename $f .jsonl); out=$R/$s
  [ -f $out/DONE ] && continue
  rm -rf $out; mkdir -p $out
  seed=$((1000 + 10#${s#shard_}))
  t0=$(date +%s)
  AUDIT_SEED=$seed $PY $SCRIPT --input_path $f --model_path $M --output_dir $out --n 32 --gpu 1 \
    --inference_handler dpskcot --correction_round 0 --max_model_len 40960 --temp 1.0 > $out/inference.log 2>&1 &
  pid=$!
  # 看門狗：vLLM 0.8.5 的引擎子程序在 A100 上印完 "Script finished." 後可能不退出
  while kill -0 $pid 2>/dev/null; do
    if grep -q "Script finished." $out/inference.log; then
      echo $(( $(date +%s) - t0 )) > $out/gen_seconds.txt
      sleep 60; pkill -P $pid; kill $pid 2>/dev/null; break
    fi
    sleep 20
  done
  wait $pid; rc=$?
  ok=no; grep -q "Script finished." $out/inference.log && [ -f $out/to_inference_codes.json ] && ok=yes
  echo "rc=$rc ok=$ok gen_seconds=$(cat $out/gen_seconds.txt 2>/dev/null) seed=$seed host=$(hostname) $(date -u +%FT%TZ) $s" >> $R/progress.log
  [ $ok = yes ] && touch $out/DONE
done
ls $R/*/DONE 2>/dev/null | wc -l > $R/done_count.txt
echo MAIN_GEN_FINISHED_PASS >> $R/progress.log
# 全部分片完成就關機（Spot 關機 = 停止，不刪磁碟）；沒完成也關機，下次開機由 startup-script 重試未完成的分片
sudo shutdown -h +2 "main generation pass finished"
