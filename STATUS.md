# 進度（2026-10-12 18:20 UTC／台北 10/13 02:20）

## 生成：完成
- Goedel-Prover-V2-8B，miniF2F-test 244 題 × 32 = 7,808 次生成，A100 bf16（官方設定，無 KV 偏離）
- 2026-10-11 18:40 → 2026-10-12 約 17:50 UTC，16/16 片完成，未遇 Spot 搶占
- 各片生成秒數：2940, 3361, 6621, 8362, 4480, 3441, 4481, 5961, 5401, 2100, 4621, 11782, 3841, 4841, 3160,（shard_15 見 VM progress.log）
- 每片結束 vLLM 都會卡住，看門狗處理（rc=143），輸出完整
- A100 VM 已自動停機；磁碟 `a100-boot` 保留

## Lean 檢查：進行中
- VM `lean-cpu`：c3-standard-22（Intel Xeon Platinum 8481C，22 vCPU，88 GB），隨選，開機磁碟 `lean-boot` 由 a100-boot 複製
- c2d-standard-32、n2-standard-32 在 us-central1-a 無容量，n2d 受配額限制 → 改用 c3-standard-22
- 官方 compile.py，PROOF_TIMEOUT 300 秒，**22 workers**（官方 pipeline.sh 為 32；改 22 以免 CPU 超賣讓逾時變多）
- 之後逾時／系統錯誤的證明用 PROOF_TIMEOUT 1200 秒重驗，兩種結果都報

## 接著
1. `scripts/aggregate.py` 彙總，官方 summarize.py 交叉核對
2. 結果拉回本機、凍結雜湊
3. 寫稽核報告
4. 刪除 VM 與磁碟（11/29 前）
