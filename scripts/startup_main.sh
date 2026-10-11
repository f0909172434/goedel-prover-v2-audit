#!/bin/bash
# GCE startup-script：VM 開機（含 Spot 搶占後重開）時自動續跑主跑生成
sudo -u wangzhikai -H bash -c 'nohup bash /home/wangzhikai/audit/scripts/run_main.sh bf16 >> /home/wangzhikai/audit/main.log 2>&1 < /dev/null &'
