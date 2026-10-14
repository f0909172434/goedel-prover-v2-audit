# 進度（2026-10-12 18:20 UTC／台北 10/13 02:20）

## 生成：完成
- Goedel-Prover-V2-8B，miniF2F-test 244 題 × 32 = 7,808 次生成，A100 bf16（官方設定，無 KV 偏離）
- 2026-10-11 18:40 → 2026-10-12 約 17:50 UTC，16/16 片完成，未遇 Spot 搶占
- 各片生成秒數：2940, 3361, 6621, 8362, 4480, 3441, 4481, 5961, 5401, 2100, 4621, 11782, 3841, 4841, 3160,（shard_15 見 VM progress.log）
- 每片結束 vLLM 都會卡住，看門狗處理（rc=143），輸出完整
- A100 VM 已自動停機；磁碟 `a100-boot` 保留

## Lean 檢查：第一輪完成，逾時重驗（1,200 秒，723 個）進行中
- VM `lean-cpu`：c3-standard-22（Intel Xeon Platinum 8481C，22 vCPU，88 GB），隨選，開機磁碟 `lean-boot` 由 a100-boot 複製
- c2d-standard-32、n2-standard-32 在 us-central1-a 無容量，n2d 受配額限制 → 改用 c3-standard-22
- 官方 compile.py，PROOF_TIMEOUT 300 秒，**22 workers**（官方 pipeline.sh 為 32；改 22 以免 CPU 超賣讓逾時變多）
- 之後逾時／系統錯誤的證明用 PROOF_TIMEOUT 1200 秒重驗，兩種結果都報

## 第一輪結果（官方 PROOF_TIMEOUT 300 秒，22 workers，c3-standard-22）
- **pass@32 = 201/244 = 82.38%**（論文 84.6% ≈ 206/244；issue #8 回報 180/244 = 73.77%）
- pass@1 = 60.77%（4,745/7,808 次生成通過）、pass@8 = 78.68%
- 官方 summarize.py 交叉核對一致（201/244、4,745/7,808）
- 723 次（9.3%）逾時／REPL 系統錯誤；43 題未解中有 40 題至少一次逾時 → 重驗可能改變結果
- 通過的證明中 `native_decide` 0 次
- 本機：`main/round1/`（原始檔不進 git，雜湊見 `main/round1/SHA256SUMS`）

## Lean 中斷紀錄
- 2026-10-13 約 06:00 UTC：`lean-cpu` 撞到 12h max-run-duration 停機，當時 13/16 片完成（shard_11 一片花 7,952 秒）。
  被中斷的分片從頭重跑（compile.py 不續跑片內），不影響結果。
- 前 13 片 6,368 次檢查中有 583 次逾時／系統錯誤（約 9%），重驗（1,200 秒）最壞可能約 10 小時 → 停機把上限改 24h 後續跑。

## 逾時重驗（修訂版，2026-10-14 09:40 UTC 開始）
- 第一次（官方 compile.py 一次 723 個）在 c3-standard-22 上因 OOM 卡在 298/723 約 20 小時，撞 24h 上限停機，無結果（約 US$22 損失）
- 修訂版：見 PLAN.md「預先登記修訂」。380 次（40 題未解題目的系統錯誤生成），每證明獨立 REPL、20G 上限、1200 秒
- VM `lean-big`：n2-highmem-32（256 GB），us-central1-b，開機磁碟 `lean-big-boot`（pd-standard，由快照 `lean-boot-snap` 建立；
  SSD 配額 500 GB 已被 a100-boot + lean-boot 用掉 400 GB），12 workers，`scripts/run_retry.sh`，完成後自動關機，24h 上限
- 結果：VM 上 `~/audit/results/main-bf16/retry_results_t1200_m20G.jsonl`（逐筆、可續跑：重開 VM 再跑 run_retry.sh 即可）
- 測試：mathd_numbertheory_277_g22 → correct 42.6 秒；numbertheory_exk2powkeqapb2mulbpa2_aeq1_g16 在 20G／2G 下都約 780 秒 → lean_error，未卡住

## 斷線保護（2026-10-12 21:35 UTC 設定）
- `lean-cpu` 上跑著 `scripts/finish_lean.sh`：等到 LEAN_ALL_DONE → aggregate.py → 官方 summarize.py →
  打包 `~/main_results.tgz`（+ sha256）→ 5 分鐘後自動關機。就算本機 session 斷線也不會空轉計費。
- 重連後：`gcloud compute instances start lean-cpu --zone us-central1-a`，讀 `~/audit/results/main-bf16/audit_summary.json`，
  `gcloud compute scp lean-cpu:~/main_results.tgz` 拉回本機。VM 另有 12h 上限保險。

## 接著
1. `scripts/aggregate.py` 彙總，官方 summarize.py 交叉核對
2. 結果拉回本機、凍結雜湊
3. 寫稽核報告
4. 刪除 VM 與磁碟（11/29 前）
