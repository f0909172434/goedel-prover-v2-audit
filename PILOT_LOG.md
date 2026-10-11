# 試跑紀錄（2026-10-11，只量成本，不當成績）

## 環境（VM prover-pilot，g2-standard-16，1×L4 22.5 GiB，us-central1-a）
- repo `2e9036e118464aa96a8bebaf9f5b9d091aa3585c`；Mathlib fork `2f65ba7f…`；Lean `v4.9.0-rc1`
- 模型 `Goedel-LM/Goedel-Prover-V2-8B` HF revision `dfd02e6271a58375dfbf3ece0175277cf6b6a89a`
- vllm 0.8.5.post1、torch 2.6.0、transformers 4.51.3、triton 3.2.0、xformers 0.0.29.post2（goedelv2.yml 釘選）
- NVIDIA driver 580.178.04
- 抽題：seed 20261011，索引 [9,10,14,71,86,88,91,122,125,126]，含 3 題 IMO（偏難，長度估計可能偏高）

## 環境建置發現
- Mathlib 快取：`lake exe cache get` 回 0，但「No cache files to decompress」——fork commit 沒有快取，必須完整建置（4,652 個檔案）。
- 只照 goedelv2.yml 的 pip 子集安裝會缺：`jload==0.7.1`、`setuptools`、`triton` 執行期需要 Python 標頭檔（apt `python3.10-dev`）。已補進 `scripts/vm_setup.sh`。

## 發現 1：官方設定放不進單張 L4
`max_model_len=40960`、bf16 KV、vLLM 預設 `gpu_memory_utilization=0.9`：
> To serve at least one request with the models's max seq len (40960), (5.62 GiB KV cache is needed, which is larger than the available KV cache memory (2.86 GiB).

官方 inference.py 沒有設 `gpu_memory_utilization`，用 vLLM 預設 0.9（22.03 GiB 的 0.9）。
推算（未實測）：調到 1.0 也只多出 0.1 × 22.03 ≈ 2.2 GiB，KV 約 5.06 GiB，仍小於 5.62 GiB。
所以單張 L4 在 bf16 權重 + bf16 KV 下，無論怎麼調這個參數都放不下官方的 40,960。

## 變體 A：FP8 KV cache（偏離 1：只加 `kv_cache_dtype="fp8"`）
- 可以啟動；vLLM 回報「Maximum concurrency for 40960 tokens per request: 1.11x」
- FP8 KV 不能用 FlashAttention backend（vLLM 自動改用其他 backend）
- 80 次生成（10 題 × 8），推論 5,948 秒（含啟動）；GPU 記憶體峰值 20,576 MiB
- 輸出長度（tokens）：平均 4,972、中位數 2,390、p90 11,860、最大 40,690；>16k 佔 5%、>30k 佔 1.25%；1 次沒抽出程式碼
- 合計輸出速度：全程平均 66.9 tok/s（80 條的長尾拖累）；中段佇列滿時約 150–170 tok/s
- 長尾：最後 10 條花了約一半時間——KV 只容得下約 41k token，長序列一出現併發就掉到 1–2

## 種子
官方 inference.py 用 `random.randint(1, 99999)` 當 vLLM 種子，且不記錄。這次試跑也沒記錄，所以 8/10 這類數字**不可重現**，只能當流程檢查。主跑要先加記錄種子的修補。

## Lean 檢查（官方 compile.py，16 workers，PROOF_TIMEOUT 300 秒）
- 431 秒；逐題 verify_time 合計 3,955 秒，中位數 8 秒
- 5 次 REPL 系統錯誤，皆為 300 秒逾時 → 逾時與硬體速度有關，主跑要記錄並另行重驗
- 結果（僅供確認流程，非成績）：10 題中 8 題至少一次通過；兩題 IMO（1984 P6、2001 P6）0/8
- 通過的證明中沒有 `native_decide`、沒有 `sorry`

## 主跑（244 題 × 32 = 7,808 次生成）成本外推
抽到的題目偏難，長度可能高估。總輸出約 7,808 × 4,972 ≈ 3,880 萬 tokens。

| 情境 | GPU 時數 | g2-standard-16 隨選 US$1.147/h | g2-standard-8 Spot ≈ US$0.487/h |
|---|---|---|---|
| 150 tok/s（試跑中段佇列滿時；主跑約有 100 次 >30k 的長序列會讓併發掉到 1–2，不一定撐得住） | ≈ 72 h | ≈ US$83 | ≈ US$35 |
| 67 tok/s（試跑全程平均，悲觀） | ≈ 161 h | ≈ US$185 | ≈ US$78 |

Lean 檢查：約 7,808 × 49 CPU 秒 ≈ 106 CPU 小時（16 核約 7 小時），可在 CPU 機或本機 M5 跑。
Spot 會被搶占；官方腳本只在每個 chunk 結束時存檔，主跑要分片並記錄每片的種子。

## 本次花費（估）
VM 約 2.5 小時 × US$1.147 ≈ US$3（帳單有延遲，以帳單頁為準），加上 200 GB 磁碟每天約 US$0.66。

## 操作事故（不影響數據）
- 修環境時重啟兩次，造成兩個試跑程序同時佔 GPU；已全部停掉、結果移到 `results_failed/`，`run_pilot.sh` 加了 flock 防重入。

## A100 試跑（2026-10-11 17:55 UTC 起，a2-highgpu-1g Spot，A100-SXM4-40GB，us-central1-a）
開機磁碟從 prover-pilot 複製（同一份 Mathlib、venv、權重）。同 10 題 × 8。
唯一修補：`inference_seedlog.py`，把 vLLM 種子印出來（diff 在 VM `env/patch_seedlog.diff`）。

### bf16 KV（官方設定，可直接啟動）
- vLLM：GPU KV cache 133,248 tokens；Maximum concurrency for 40,960 tokens per request: 3.25x
- 種子 AUDIT_SEED_USED=20202（官方 random 產生，已記錄）
- 生成 16 分 19 秒（979 秒），含啟動 1,213 秒；全程平均輸出 436 tok/s（L4 FP8 為 66.9）
- 輸出長度：合計 427,453、平均 5,343、中位數 2,838、最大 40,689、>30k 1 次
- 顯存峰值 37,012 MiB
- **問題**：印出 "Script finished." 後 vLLM 引擎子程序不退出（掛了 15 分鐘，手動 kill）。
  主跑 `run_main.sh` 加了看門狗：看到 "Script finished." 後等 60 秒仍未退出就結束程序。

### 主跑外推（A100 bf16）
7,808 × 約 5,200 tokens ≈ 4,060 萬 tokens。以 436 tok/s（試跑含長尾）≈ 26 小時；
分片 512 次生成、長尾比例較低，可能更快。Spot a2-highgpu-1g ≈ US$2.20/h → 約 US$57（範圍抓 US$40–75）。
決策規則（上限 US$150、容量拿得到）成立 → **主跑用 A100 bf16，無偏離 1**。
