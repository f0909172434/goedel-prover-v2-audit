# Reproducing Goedel-Prover-V2-8B on miniF2F-test with the official pipeline

**Status:** draft audit report, 2026-10-14. Not peer reviewed. One full run (32 samples × 244 problems).

## Question

The Goedel-Prover-V2 paper (arXiv 2508.03613, Table 4) reports **pass@32 = 84.6%** on miniF2F-test for Goedel-Prover-V2-8B in standard mode (no self-correction).
The Hugging Face model card states 83.0%.
In GitHub issue Goedel-LM/Goedel-Prover-V2#8 (2025-12-12), a user reported reproducing only **180/244 = 73.77%** and asked whether the repository's parameters are the paper's.
The maintainers had not replied when this audit started (checked 2026-10-11).

This audit re-runs the released model through the repository's own inference and Lean-checking code, and records every place where it had to depart from that code.

## Result

| | pass@32 | problems solved |
|---|---|---|
| Paper, Table 4 | 84.6% | ≈ 206 / 244 |
| Model card | 83.0% | ≈ 202–203 / 244 |
| **This audit** | **82.38%** | **201 / 244** |
| Issue #8 report | 73.77% | 180 / 244 |

Other metrics from the same run (official 300 s Lean timeout):

- pass@8 = 78.68%, pass@1 = 60.77% (4,745 of 7,808 attempts verified), using the unbiased pass@k estimator over 32 samples per problem.
- No verified proof uses `native_decide`. The `complete` criterion and the `apply?` / `exact?` exclusion are the same as the official `src/summarize.py`.
- The official `summarize.py`, run on the combined output, gives the same numbers: 201/244 problems and 4,745/7,808 attempts.
- Resampling each problem's 32 attempts with replacement (2,000 bootstrap draws) gives a 95% range of 80.3%–82.4% for pass@32. This range describes sampling variation within this run only, not variation across independent runs.

**Lean timeouts do not explain the gap.**

- In the first verification round, 723 attempts (9.3%) ended in a system error: 617 timeouts and 106 REPL failures.
- Of the 43 unsolved problems, 40 had at least one such attempt.
- All 380 system-error attempts in those 40 problems were re-checked with a 1,200 s timeout and a 20 GB memory cap per proof. **None verified.** The outcomes were:
  - 256 Lean errors: the proof was simply wrong, and took more than 300 s to reject.
  - 97 timeouts, even at 1,200 s.
  - 27 REPL exits, consistent with the memory cap.
- pass@32 with the re-check is therefore still 201/244.
- pass@1 after re-checking can only be given as a range, **60.77%–65.16%**. The 343 system-error attempts in already-solved problems were not re-checked, because they cannot change pass@32. The upper bound assumes all of them would pass.

**Reading.**

- This run lands about 5 problems below the paper's figure and 2 below the model card's.
- It is 21 problems above the issue #8 report.
- With the repository's released code and parameters, the paper's number is approximately but not exactly reproduced.
- The 73.77% in issue #8 is not what the released pipeline produces under these conditions.

The remaining gap is not explained by this audit. Candidates, none tested here:

- Run-to-run sampling variation. The paper reports ±0.6, which suggests averaging over several runs; this is a single run.
- The maximum generation length. The README describes standard mode as "32K", while `scripts/pipeline.sh` and this audit use `max_model_len = 40960`.
- Differences between the paper's miniF2F revision and `dataset/minif2f.jsonl`.
- vLLM, GPU and numerical differences.

## Setup

| Item | Value |
|---|---|
| Repository | `Goedel-LM/Goedel-Prover-V2` @ `2e9036e118464aa96a8bebaf9f5b9d091aa3585c` |
| Mathlib | `xinhjBrant/mathlib4` @ `2f65ba7f1a9144b20c8e7358513548e317d26de1` (submodule), Lean `v4.9.0-rc1` |
| Model | `Goedel-LM/Goedel-Prover-V2-8B`, HF revision `dfd02e6271a58375dfbf3ece0175277cf6b6a89a`, bf16 |
| Data | `dataset/minif2f.jsonl`, 244 problems, sha256 `47ca505c…79eee8f3` |
| Inference | official `src/inference.py`, handler `dpskcot`, temperature 1.0, top_p 0.95, `max_model_len` 40960, `n` 32, correction rounds 0 |
| Software | vllm 0.8.5.post1, torch 2.6.0, transformers 4.51.3, triton 3.2.0, xformers 0.0.29.post2 (pins from `goedelv2.yml`) |
| Generation hardware | 1 × NVIDIA A100-SXM4-40GB (GCP a2-highgpu-1g, Spot), driver 580.178.04 |
| Generation time | 81,894 s (22.7 h) of generation across 16 shards; no preemptions |
| Lean round 1 | official `src/compile.py`, `PROOF_TIMEOUT` 300 s, 22 workers, GCP c3-standard-22 (Xeon Platinum 8481C, 22 vCPU, 88 GB) |
| Lean re-check | `scripts/retry_driver.py`, 1,200 s, 20 GB per proof, 12 workers, GCP n2-highmem-32 (256 GB) |

## Departures from the official pipeline

1. **Seed logging.** The official `inference.py` draws `seed = random.randint(1, 99999)` and does not record it. `inference_seedlog.py` changes only that line: the seed is read from `AUDIT_SEED` and printed. The diff is in `pilot/a100/env/patch_seedlog.diff`.
2. **Sharding.** The 244 problems were shuffled with seed 20261012 into 16 shards of 15–16 problems. Each shard was run as a separate official `inference.py` call with seed 1000 + shard index (`main/round1/shards/manifest.json`). This allows resuming after a Spot preemption. Each attempt's prompt and sampling are unchanged; only the vLLM batch composition and seeds differ from a single 244-problem call.
3. **vLLM shutdown watchdog.** On the A100, vLLM 0.8.5's engine process did not exit after printing `Script finished.` A watchdog ends it 60 s later. All 16 shards wrote complete output before this point (`rc=143 ok=yes` in `progress.log`).
4. **Lean workers: 22, not 32.** The official `pipeline.sh` uses `CPUS=32`. 32-vCPU machines were unavailable, so round 1 ran 22 workers on 22 vCPU.
5. **Memory.** Round 1 ran 22 REPLs in 88 GB. The kernel OOM killer ended about 61 REPL processes during round 1. Some of these were in a partial run of shard 13 that was discarded and re-run, so 61 is an upper bound. The 106 JSONDECODE failures are consistent with these kills. Under a 300 s timeout, some Lean processes reach 17–20 GB resident.
6. **Re-check design.** The first attempt to re-check all 723 system errors with the official `compile.py` hung for about 20 hours. After OOM kills, its scheduler waits for results that never arrive, and it writes nothing until it finishes. The revised re-check was pre-registered in `PLAN.md` before it ran:
   - It covers only system-error attempts in unsolved problems, which is exact for pass@32.
   - Each proof gets a fresh REPL, through the official `initiate_child` and `send_command_and_wait(env=0)`. This is equivalent to the official REPL reuse, because environment 0 is always the post-import state.
   - Each proof runs under a 20 GB cgroup limit, with resumable output.

## Side findings

- **The official configuration does not fit a 24 GB GPU.**
  - On one NVIDIA L4, vLLM refuses to start. A single 40,960-token sequence needs 5.62 GiB of KV cache, but only 2.86 GiB is left after the bf16 weights.
  - Raising `gpu_memory_utilization` from 0.9 to 1.0 adds about 2.2 GiB, which is still short. This was computed, not run.
  - FP8 KV cache (`kv_cache_dtype="fp8"`) starts with 1.11× maximum concurrency. Over 80 generations it averaged 67 output tokens/s, against 436 tokens/s for bf16 on an A100. Mid-run, with a full 512-attempt shard, the A100 reached about 890 tokens/s.
  - The A100 cannot run the L4's FP8 KV format: triton reports "fp8e4nv not supported". The FP8-versus-bf16 comparison was therefore dropped.
- **Mathlib fork cache.** No Mathlib cache exists for the pinned fork commit, so `lake exe cache get` downloads 0 files. A full build took 63 minutes on 16 vCPU.
- **Environment file.** Installing only the inference and compile subset of `goedelv2.yml` misses `jload`, `setuptools`, `triton` and `xformers`. triton also needs the Python headers (`python3.10-dev`). `scripts/vm_setup.sh` installs all of them.
- **Long outputs.** In the pilot, 1.25% of generations exceeded 30k tokens. In shards 02–03 of the main run, 23 of 1,024 attempts reached the length cap. These dominate generation time.

## Unsolved problems (43)

aime_1984_p7, aime_1995_p7, aime_1999_p11, algebra_abpbcpcageq3_sumaonsqrtapbgeq3onsqrt2, algebra_apbmpcneq0_aeq0anbeq0anceq0, algebra_ineq_nto1onlt2m1on, algebra_sum1onsqrt2to1onsqrt10000lt198, amc12a_2003_p23, amc12a_2008_p25, amc12a_2019_p12, amc12a_2020_p25, amc12a_2020_p4, amc12a_2020_p9, amc12a_2021_p12, amc12a_2021_p14, amc12a_2021_p19, amc12a_2021_p22, amc12a_2021_p25, amc12b_2002_p4, amc12b_2020_p21, amc12b_2021_p13, imo_1965_p2, imo_1968_p5_1, imo_1969_p2, imo_1974_p3, imo_1977_p6, imo_1982_p1, imo_1984_p6, imo_1985_p6, imo_1992_p1, imo_1997_p5, imo_2001_p6, imo_2019_p1, imosl_2007_algebra_p6, induction_pord1p1on2powklt5on2, induction_pprime_pdvdapowpma, mathd_algebra_320, mathd_numbertheory_451, mathd_numbertheory_552, mathd_numbertheory_764, numbertheory_3pow2pownm1mod2pownp3eq2pownp2, numbertheory_exk2powkeqapb2mulbpa2_aeq1, numbertheory_fxeq4powxp6powxp9powx_f2powmdvdf2pown

## What this report does not claim

- That the paper's number is wrong. This is one run, and the gap is within a few problems.
- That any listed cause of the remaining gap is the actual cause.
- That every verified proof is mathematically meaningful beyond passing Lean `v4.9.0-rc1` with this Mathlib, under the official criterion.
- Independent human review. The code, runs and this draft were produced with AI coding agents (Claude Code); the author is responsible for the claims.

## Artifacts

- `main/round1/`:
  - per-shard Lean results, full generation records (model input, model output and checked code for all 7,808 attempts) and inference logs. Raw files are not in git; their hashes are in `SHA256SUMS`.
  - `audit_summary.json`
  - `official_summarize/`
- `main/retry/`:
  - re-check results (`retry_results_t1200_m20G.jsonl`) and driver logs. Hashes are in `SHA256SUMS`.
  - `official_summarize_with_retry/`
- `pilot/`: L4 and A100 pilots (10 problems × 8), including the L4 "does not fit" log.
- `scripts/`: every script used.
- `PLAN.md`: the pre-registration and its revision.
- `PILOT_LOG.md`, `STATUS.md`: the running log.

## Approximate cost

GCP list prices in us-central1. These are estimates, not billing records.

| Item | Cost |
|---|---|
| A100 Spot generation, about 23 h | ≈ US$51 |
| L4 and A100 pilots | ≈ US$5 |
| Lean round 1 and the hung re-check on c3-standard-22, about 36 h | ≈ US$40 |
| Revised re-check on n2-highmem-32, about 4 h | ≈ US$8 |
| Disks and snapshot | a few dollars |

The hung re-check (≈ US$22 of the c3-standard-22 time) is a lesson in itself: write results incrementally, and cap memory per proof.
