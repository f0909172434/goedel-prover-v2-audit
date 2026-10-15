# Prover Audit — 計畫與已知事實（2026-10-11）

## 稽核問題
Goedel-Prover-V2-8B 論文（arXiv 2508.03613 表 4）報告 miniF2F-test pass@32 = 84.6%。
GitHub issue Goedel-LM/Goedel-Prover-V2#8 有人回報重現只得 73.77%（180/244），維護者未回覆。
HF 模型卡寫 83.0%，與論文不一致。本稽核用官方 pipeline 在單張 L4 上重跑，記錄每個偏離。

## GCP
- 專案：`prover-audit-2026-zk`（gcloud 設定名 `prover-audit`，不動 Kaggle 的 default 設定）
- 帳單帳戶 [billing account redacted]（TWD，付費帳戶；抵免額 2026-11-29 到期，之後扣卡）
- 配額：GPUS_ALL_REGIONS 1（2026-10-11 申請核准）、us-central1 L4 1、CPUS_ALL_REGIONS 32
- 預算警示：TWD 6,500（約 US$200），排除抵免額計算，門檻 25/50/75/90/100%
- **11/22 收尾，11/29 前刪除所有資源**

## 官方 pipeline（repo commit 2e9036e1，2025-08-27）
- Mathlib：`xinhjBrant/mathlib4` @ `2f65ba7f1a9144b20c8e7358513548e317d26de1`（submodule）
- 資料：`dataset/minif2f.jsonl`，244 題，全部 split=test
- `scripts/pipeline.sh` 預設：handler `dpskcot`、temperature 1.0、top_p 0.95（寫死）、
  max_model_len 40960、max_tokens = max_model_len、NUM_SAMPLES_INITIAL 8、修正 2 輪
- 種子：`random.randint(1, 99999)`，未記錄 → 我們要固定並記錄（只為可追溯，屬偏離）
- 論文 pass@32 為標準模式（無修正）；自我修正模式另報 86.7%

## 單張 L4 的記憶體問題（待試跑確認）
Qwen3-8B 架構推算 KV ≈ 144 KB/token（36 層 × 8 KV 頭 × 128 維 × K/V × bf16）。
權重 16.4 GB 後，L4 剩約 3–4 GB KV，可能放不下一條 40,960 token 的序列。
候選做法（皆為偏離，需記錄）：FP8 KV cache；或縮短 max_model_len。

## 10 題試跑目的
只量成本，不算成績：輸出長度分布、吞吐量（tokens/s）、Lean 檢查時間、記憶體是否放得下。

## 主跑的預先登記（草案，主跑前定稿）
- 標準模式：`NUM_SAMPLES_INITIAL=32`、`MAX_CORRECTION_ROUNDS=0`（論文 84.6% 是標準模式，不是腳本預設的 8 + 2 輪修正）
- 偏離 1：FP8 KV cache（單張 L4 要保留 40,960 上限又不量化權重，只剩這個做法）；是否加 bf16-KV 對照組待使用者決定
- 偏離 2：Lean 逾時。試跑 16 workers 下 5/80 次撞到 300 秒上限。主跑收集所有逾時，另外用更長上限重驗，兩種通過率都報告
- 每個分片記錄 vLLM 種子；分片可在 Spot 被搶占後重跑
- 試跑的 10 題也在 244 題裡，主跑照常重跑，不沿用試跑結果

## 預先登記修訂：逾時重驗（2026-10-14，正式重驗之前寫定）
起因：用官方 compile.py 一次重驗全部 723 個逾時，在 c3-standard-22（88 GB）上因 OOM 卡在 298/723 約 20 小時
（官方 scheduler 在 REPL 被 OOM killer 殺掉後等待不存在的結果），結果未寫出。
第一輪本身也受記憶體影響：第一輪期間 OOM killer 殺了約 61 個 REPL（boot -3：33、boot -1 在 07:39 UTC 前：28；
其中一部分屬於被中斷後重跑的 shard_13，因此是上限）。第一輪 723 個系統錯誤中 608 個 TIMEOUT、106 個 JSONDECODE（REPL 異常退出）。

修訂後的重驗：
- 範圍：只重驗第一輪「未解題目」中有 system_errors 的生成（40 題、380 次）。同一題一旦有一次通過，該題其餘重驗略過。
  對 pass@32 是精確的（Lean 判定是確定性的；已正常判定的生成不變；已解題目再多通過不影響 pass@32）。
  pass@1 / pass@8 的重驗後數字因此只能給範圍：下限 = 第一輪；上限另算（假設已解題目的逾時全數通過）。
- 每個證明一個新的 REPL（`scripts/check_one.py` 直接呼叫官方 `initiate_child` 與 `send_command_and_wait(env=0)`，
  前處理同官方 compile.py 的 `handle()`）。env 0 永遠是 import 後的狀態，與官方重用 REPL 語意相同。
- PROOF_TIMEOUT=1200；每個證明 systemd scope `MemoryMax=20G`、`MemorySwapMax=0`；外層 timeout 1500 秒；結果逐筆寫入 JSONL，可續跑。
- 狀態分類：correct / timeout / repl_exited(consistent_with_mem_cap)（EOF 或 JSONDECODE，不直接斷言 OOM）/ lean_error / no_output。
- 驗證：重驗結果代入第一輪後，再跑一次官方 summarize.py 交叉核對 pass@32。
- 測試（正式跑之前）：第一輪通過的 mathd_numbertheory_277_g22 → correct（42.6 秒）；逾時案例在 20G 與 2G 上限下都須在時限內結束、不卡住。

## 後續驗證預先登記（2026-10-15，生成前寫定）
- 假設：repo `dataset/minif2f.jsonl` 與論文用的 `AI-MO/minif2f_test`（rev 5def3183）有 4 題陳述不同，皆為主跑未解題；
  修正版陳述可能可證，可解釋與論文的落差。
- 做法：`followup/minif2f_corrected4.jsonl`（sha256 a7de5534…；formal_statement 取自 Kimina 版、lean4_code = formal_statement.rstrip() + " sorry"，同 repo 慣例），
  官方 inference_seedlog.py、n=32、AUDIT_SEED=2000、其他參數同主跑；Lean 官方 compile.py 300 秒（3 workers，A100 VM 85 GB）；系統錯誤以 1200 秒／20G 重驗。
- 判讀：報「在修正版陳述上解出幾題」。主跑 201 題 + 修正版解出數 = 「以論文資料集版本計」的 pass@32 估計；
  注意這是兩次不同的抽樣（主跑 240 題 + 後續 4 題），不是單次完整重跑。
- 陳述檢查：4 題帶 sorry 皆 pass=True、complete=False、0 error（2026-10-15 00:42 UTC）。
