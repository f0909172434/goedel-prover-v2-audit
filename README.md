# Goedel-Prover-V2-8B on miniF2F: a reproducibility audit

Does the released pipeline reproduce the paper's **pass@32 = 84.6%** for Goedel-Prover-V2-8B on miniF2F-test?

| | pass@32 |
|---|---|
| Paper (arXiv 2508.03613, Tables 2 and 4) | 84.6% ± 0.6% |
| Model card | 83.0% |
| **This audit, repository dataset** | **82.38% (201/244)** |
| **This audit, paper's statements for 4 differing problems** | **82.79% (202/244)** |
| Goedel-LM/Goedel-Prover-V2#8 | 73.77% (180/244) |

- One full run: 244 problems × 32 attempts on an A100, bf16. It used the repository's own `inference.py` and `compile.py` at commit `2e9036e1`, with the pinned Lean `v4.9.0-rc1` / Mathlib and the pinned vLLM 0.8.5.
- The repository's `dataset/minif2f.jsonl` differs from the paper's `AI-MO/minif2f_test` in four statements, all of them unsolved here. Restoring the paper's statements adds one solved problem.
- Re-checking 380 timed-out attempts at 1,200 s added none.
- About 4 problems of the gap to the paper remain unexplained.

**Read [REPORT.md](REPORT.md)** for the full result, every departure from the official pipeline, side findings, and what is *not* claimed.

## Contents

| Path | What |
|---|---|
| `REPORT.md` | The audit report |
| `PLAN.md` | Pre-registration, written before each run; check the commit times |
| `PILOT_LOG.md`, `STATUS.md` | Running log |
| `scripts/` | Every script that was run, on GCP VMs |
| `pilot/` | L4 and A100 pilots (10 problems × 8), including the "does not fit a 24 GB GPU" log |
| `main/round1/`, `main/retry/` | Summaries, the official `summarize.py` output, and SHA-256 manifests of the raw files |
| `followup/` | Corrected-statement dataset and summary for the 4-problem follow-up |

The raw outputs are attached to the GitHub release, about 0.5 GB uncompressed. They contain the model input, model output and checked Lean code for all 7,808 + 128 attempts, plus per-attempt Lean results. Verify them against the `SHA256SUMS` files in this repository.

## How this was made

The runs, scripts and report were produced with AI coding agents (Claude Code), under my direction and review. AI review is not human review, and the claims are mine.
The report is a draft and has not been peer reviewed.

## 中文摘要

用 Goedel-Prover-V2 官方 repo 的推論與 Lean 檢查程式，重跑 Goedel-Prover-V2-8B 在 miniF2F-test 的 pass@32。

- 用 repo 附的資料檔：201/244 = 82.38%，論文為 84.6%。
- repo 的資料檔與論文所用版本有 4 題陳述不同。改用論文版本後多解出 1 題，為 202/244。
- 1,200 秒重驗逾時的證明，沒有任何一次翻盤。
- 與論文還差約 4 題，原因未明。

詳見 [REPORT.md](REPORT.md)。

## License

MIT for the code and text written for this audit (see [LICENSE](LICENSE)).

- `scripts/check_one.py` reproduces a short `handle()` function from Goedel-Prover-V2 (Apache-2.0).
- miniF2F statements and model outputs in the data files come from their respective sources under their own licenses.
