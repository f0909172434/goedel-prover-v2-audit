#!/bin/bash
# 本機監看主跑：有分片完成、VM 停止（必要時自動重開）、出錯或全部完成時印一行並結束。
export PATH="$HOME/google-cloud-sdk/bin:$PATH"; export CLOUDSDK_ACTIVE_CONFIG_NAME=prover-audit
Z=us-central1-a; VM=a100-pilot
q() { gcloud compute ssh $VM --zone $Z --quiet --command "$1" 2>/dev/null; }
start_done=""
while true; do
  st=$(gcloud compute instances describe $VM --zone $Z --format="value(status)" 2>/dev/null)
  if [ "$st" = RUNNING ]; then
    d=$(q 'ls ~/audit/results/main-bf16/*/DONE 2>/dev/null | wc -l')
    err=$(q 'cd ~/audit/results/main-bf16 && grep -l -E "Traceback|OutOfMemory" */inference.log 2>/dev/null | head -3 | tr "\n" " "')
    [ -z "$start_done" ] && [ -n "$d" ] && start_done=$d
    if [ -n "$err" ]; then echo "$(date -u +%H:%MZ) ERROR in: $err (done=$d/16)"; exit 0; fi
    if [ -n "$d" ] && [ "$d" != "$start_done" ]; then
      echo "$(date -u +%H:%MZ) shard completed: done=$d/16"; q 'tail -1 ~/audit/results/main-bf16/progress.log'; exit 0
    fi
  elif [ "$st" = TERMINATED ]; then
    # 停止：可能是跑完一輪自動關機、Spot 搶占或 40h 上限。開機後 startup-script 會跳過已完成分片續跑；
    # 若已全部完成，開機只會再關機一次，所以先開機讀 DONE 數。
    gcloud compute instances start $VM --zone $Z --quiet >/dev/null 2>&1
    sleep 90
    d=$(q 'ls ~/audit/results/main-bf16/*/DONE 2>/dev/null | wc -l')
    if [ "$d" = "16" ]; then
      echo "$(date -u +%H:%MZ) ALL 16 shards DONE (VM restarted only to read state; it will shut itself down)"; exit 0
    fi
    echo "$(date -u +%H:%MZ) VM was stopped; restarted to resume (done=$d/16)"; exit 0
  fi
  sleep 300
done
