#!/bin/bash
# Lean 全部完成後：彙總、官方 summarize 交叉核對、打包，然後關機（停止，不刪磁碟）
R=$HOME/audit/results/main-bf16; G=$HOME/audit/Goedel-Prover-V2; PY=$HOME/audit/venv/bin/python
until grep -q LEAN_ALL_DONE $R/lean_progress.log 2>/dev/null; do sleep 60; done
cd $G
$PY $HOME/audit/scripts/aggregate.py $R $R/retry_compilation_t1200.json > $R/aggregate_stdout.txt 2>&1
$PY src/summarize.py --input_path $R/combined_compilation.json --full_record_path $R/combined_full_records.json \
  --output_dir $R/official_summarize > $R/official_summarize.log 2>&1
cd $HOME/audit && tar czf /home/wangzhikai/main_results.tgz results/main-bf16 shards env && sha256sum /home/wangzhikai/main_results.tgz > /home/wangzhikai/main_results.tgz.sha256
echo FINISH_DONE > $R/finish_status.txt
sudo shutdown -h +5 "lean checking finished"
