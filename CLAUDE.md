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
- 選方案 B：Spot A100 配額 us-central1 已核准 1。改為先做 A100 試跑（同 10 題 × 8、官方 inference.py 不改、bf16 KV、40960），
  再加同 80 次的 A100 FP8 KV，隔離 KV dtype 影響。
- 決策規則（試跑前寫定）：A100 實測速度推出的主跑費用（GPU 時數 × Spot 約 US$2.20/h）上限 ≤ US$150，且 Spot 容量拿得到
  → 主跑改 A100 bf16（無偏離 1），L4 結果降為附帶發現。否則退回 L4 FP8 主跑。
- 2026-10-12 決定：A100 bf16 試跑實測 436 tok/s（L4 FP8 為 67），主跑外推約 26 h、約 US$57 → **主跑改 A100 bf16，無偏離 1**。
  A100 不支援 L4 的 FP8 e4m3 KV（triton: fp8e4nv not supported），FP8 對照組取消。
- 主跑在 VM `a100-pilot`（a2-highgpu-1g Spot，us-central1-a，開機磁碟 `a100-boot` 由 prover-pilot 複製）：
  startup-script 開機自動跑 `scripts/run_main.sh bf16`，跳過有 DONE 的分片；跑完一輪自動關機；max-run-duration 40h。
  被搶占後只要 `gcloud compute instances start a100-pilot --zone us-central1-a` 就會續跑。
  進度：VM 上 `~/audit/results/main-bf16/progress.log`；分片清單 `~/audit/shards/manifest.json`（種子 1000+分片號）。
- Lean 檢查不在 A100 VM 上跑（12 核會讓 300 秒逾時變多：A100 試跑 9 次 vs L4 5 次），生成完成後另開 CPU VM 跑，逾時另行重驗。
- 主跑驅動：沿用官方 inference.py，只加記錄種子的修補；244 題切成外部分片 JSONL，跳過已完成的分片。不自寫生成迴圈。
- Lean 300 秒逾時是偏離 2：逾時的另外用更長上限重驗，兩種通過率都報。
- 種子修補（inference_seedlog.py）與分片續跑已完成並用在主跑。

## GCP 規則
- 一律 `export CLOUDSDK_ACTIVE_CONFIG_NAME=prover-audit`；不要動 gcloud 的 default 設定（屬於 Kaggle 專案 `kaggle-2026-compute-zk`）。
- 專案 `prover-audit-2026-zk`，帳單帳戶 [billing account redacted]（TWD，付費帳戶）。
- 抵免額 **2026-11-29 到期，之後直接扣卡**。11/22 收尾，11/29 前刪除所有 VM、磁碟、快照。
- 預算警示 TWD 6,500（約 US$200），排除抵免額計算。
- 開 VM 一律加 `--max-run-duration` 和 `--instance-termination-action=STOP`；不用時立刻停機。
- 配額：GPUS_ALL_REGIONS 1、us-central1 L4 1、Spot A100 1、CPUS_ALL_REGIONS 32。
- L4 VM `prover-pilot` 與其磁碟已於 2026-10-12 依使用者指示刪除。建好的環境（Mathlib、venv、權重）現在只在 `a100-boot` 磁碟上。

## 雲端資源（2026-10-15）
所有 VM、磁碟、快照已刪除（`gcloud compute instances/disks/snapshots/images list` 皆 0）。GCP 專案與預算警示仍在，無運算費用。
所有結果與完整生成紀錄在本機 `main/`、`followup/`（原始檔不進 git，雜湊在各自的 SHA256SUMS）。

## 最終結果（2026-10-15）
- repo 資料集：pass@32 = 201/244 = 82.38%（逾時 1200 秒重驗 380 次 0 翻盤；124 次在 33 題仍未定）
- repo `dataset/minif2f.jsonl` 與論文用的 `AI-MO/minif2f_test` 有 4 題陳述不同（皆為未解題）；修正版後續驗證只有 amc12a_2019_p12 解出（23/32）
  → 以論文陳述計 202/244 = 82.79%（主跑 240 題 + 後續 4 題，兩次抽樣）
- 報告草稿 `REPORT.md`（英文）；尚未對外發布

## 環境要點
- 官方 repo `2e9036e1`、Mathlib fork `xinhjBrant/mathlib4@2f65ba7`、Lean v4.9.0-rc1、模型 HF revision `dfd02e62`。
- `scripts/vm_setup.sh` 已補齊官方 yml 子集漏掉的套件（jload、setuptools、triton、xformers、python3.10-dev）。
- 在 VM 上 `pkill -f` 的樣式不要出現在同一條 ssh 指令字串裡，會把自己的 ssh 殺掉；寫成腳本檔再執行。
- `run_pilot.sh` 用 flock 防止兩個試跑同時佔 GPU。

## 不做
- 不把試跑的 8/10 當成績（種子未記錄、題目非全集）。
- 不對外發布、不在 GitHub issue 留言、不推上公開 repo，除非使用者明確指示。
