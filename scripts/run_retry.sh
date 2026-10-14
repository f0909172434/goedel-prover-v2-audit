#!/bin/bash
# 正式重驗：12 workers、每證明 20G、PROOF_TIMEOUT 1200；完成後 5 分鐘自動關機
cd ~/audit; R=$HOME/audit/results/main-bf16
nproc > $R/retry_host_nproc.txt; lscpu | grep "Model name" > $R/retry_host_cpu.txt; free -g > $R/retry_host_mem.txt
~/audit/venv/bin/python scripts/retry_driver.py $R 12 20G 1200 >> retry_main.log 2>&1
echo "RETRY_FINISHED $(date -u +%FT%TZ)" >> retry_main.log
sudo shutdown -h +5 "retry finished"
