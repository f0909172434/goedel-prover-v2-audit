# Prover Audit

用官方 pipeline 稽核 Goedel-Prover-V2-8B 在 miniF2F-test 的 pass@32 = 84.6%（arXiv 2508.03613 表 4）。
起因：Goedel-LM/Goedel-Prover-V2#8 有人重現只得 73.77%（180/244，2025-12-12），維護者未回覆；HF 卡片寫 83.0%。
定位：使用者作品集「主張附證據、負面結果也公開」路線，延伸 SAIR Proof Press / ProofWeave；目標是求職與留學申請用的可查證成果。

回覆使用者一律用繁體中文。

## 先讀
- `PLAN.md`：已知事實、官方設定、主跑預先登記草案
- `PILOT_LOG.md`：10 題試跑的發現、成本外推
- `pilot/`：試跑原始結果（`pilot_bundle.tgz` + sha256）
- `docs/sessions/`：原始對話匯出（不進 git，含帳號資訊）

## 已做的決定（2026-10-11/12）
- 選這個專案當 GCP 抵免額的唯一 GPU 用途；RuleShift-Web 投 WWW 2027 Demo（11/16 AoE 截止）另外進行，不用 GCP。
- 單張 L4 放不下官方 max_model_len 40960（KV 需 5.62 GiB，可用 2.86 GiB）→ L4 主跑用 FP8 KV（偏離 1）。
- 選方案 B：在 Spot A100 上跑 bf16 KV 對照組（約 30 題 × 32），量化 FP8 的影響。Spot A100 配額 us-central1 已核准 1。
- Lean 300 秒逾時是偏離 2：逾時的另外用更長上限重驗，兩種通過率都報。
- 主跑前必做：記錄 vLLM 種子的修補、分片以便 Spot 搶占後續跑。

## GCP 規則
- 一律 `export CLOUDSDK_ACTIVE_CONFIG_NAME=prover-audit`；不要動 gcloud 的 default 設定（屬於 Kaggle 專案 `kaggle-2026-compute-zk`）。
- 專案 `prover-audit-2026-zk`，帳單帳戶 [billing account redacted]（TWD，付費帳戶）。
- 抵免額 **2026-11-29 到期，之後直接扣卡**。11/22 收尾，11/29 前刪除所有 VM、磁碟、快照。
- 預算警示 TWD 6,500（約 US$200），排除抵免額計算。
- 開 VM 一律加 `--max-run-duration` 和 `--instance-termination-action=STOP`；不用時立刻停機。
- 配額：GPUS_ALL_REGIONS 1、us-central1 L4 1、Spot A100 1、CPUS_ALL_REGIONS 32。
- VM `prover-pilot`（us-central1-a，g2-standard-16）目前停止中，200 GB 開機磁碟保留（約 US$0.66/天），內有建好的 Mathlib（建置 63 分鐘）、venv、模型權重。

## 環境要點
- 官方 repo `2e9036e1`、Mathlib fork `xinhjBrant/mathlib4@2f65ba7`、Lean v4.9.0-rc1、模型 HF revision `dfd02e62`。
- `scripts/vm_setup.sh` 已補齊官方 yml 子集漏掉的套件（jload、setuptools、triton、xformers、python3.10-dev）。
- 在 VM 上 `pkill -f` 的樣式不要出現在同一條 ssh 指令字串裡，會把自己的 ssh 殺掉；寫成腳本檔再執行。
- `run_pilot.sh` 用 flock 防止兩個試跑同時佔 GPU。

## 不做
- 不把試跑的 8/10 當成績（種子未記錄、題目非全集）。
- 不對外發布、不在 GitHub issue 留言、不推上公開 repo，除非使用者明確指示。
