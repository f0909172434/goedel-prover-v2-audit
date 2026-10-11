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
