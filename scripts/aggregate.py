"""彙總主跑結果。判定標準同官方 summarize.py：compilation_result.complete 為真，且程式碼不含 apply? / exact?。
輸出：
  combined_compilation.json / combined_full_records.json：合併後給官方 summarize.py 交叉核對
  audit_summary.json：pass@1/8/32（無偏估計）、解出題數、bootstrap 區間、逾時重驗前後兩種結果
用法：aggregate.py <results/main-bf16> [retry_json]"""
import glob, json, math, os, random, sys

R = sys.argv[1]
retry_path = sys.argv[2] if len(sys.argv) > 2 else None
N_TOTAL = 244


def correct(r):
    return (r["compilation_result"].get("complete") is True
            and "apply?" not in r.get("code", "") and "exact?" not in r.get("code", ""))


comp, full = [], []
for d in sorted(glob.glob(f"{R}/shard_*")):
    if not os.path.exists(f"{d}/code_compilation_repl.json"):
        sys.exit(f"missing compilation for {d}")
    comp += json.load(open(f"{d}/code_compilation_repl.json"))
    full += json.load(open(f"{d}/full_records.json"))
json.dump(comp, open(f"{R}/combined_compilation.json", "w"))
json.dump(full, open(f"{R}/combined_full_records.json", "w"))

origin = {f["problem_id"]: f["origin_problem_id"] for f in full}
retry = {}
if retry_path and os.path.exists(retry_path):
    retry = {r["name"]: r for r in json.load(open(retry_path))}


def table(use_retry):
    by = {}
    for r in comp:
        rr = retry.get(r["name"], r) if use_retry else r
        by.setdefault(origin[r["name"]], []).append(correct(rr))
    return by


def pass_at_k(n, c, k):
    if n < k:  # 生成數不足 k（例如提示過長被官方過濾）：退回「是否至少解出一次」
        return float(c > 0)
    if n - c < k:
        return 1.0
    return 1.0 - math.comb(n - c, k) / math.comb(n, k)


def summarize(by):
    probs = sorted(by)
    out = {"problems_with_outputs": len(probs), "generations": sum(len(v) for v in by.values()),
           "short_problems": {p: len(v) for p, v in by.items() if len(v) != 32}}
    for k in (1, 8, 32):
        out[f"pass@{k}"] = sum(pass_at_k(len(by[p]), sum(by[p]), k) for p in probs) / N_TOTAL
    out["solved_any"] = sum(any(v) for v in by.values())
    rng = random.Random(0)
    boots = []
    for _ in range(2000):  # 每題在自己的 32 次裡有放回重抽，量取樣本身的變異
        boots.append(sum(any(rng.choice(v) for _ in range(len(v))) for v in by.values()) / N_TOTAL)
    boots.sort()
    out["pass@32_bootstrap_95"] = [boots[49], boots[1949]]
    out["unsolved"] = sorted(p for p, v in by.items() if not any(v))
    return out


timeouts = sum(1 for r in comp if r["compilation_result"].get("system_errors"))
summary = {
    "criterion": "complete and no 'apply?'/'exact?' (official summarize.py)",
    "reference": {"paper_pass@32": 0.846, "issue8_pass@32": 180 / 244},
    "round1_timeout_or_system_error": timeouts,
    "official_timeout_300s": summarize(table(False)),
}
if retry:
    summary["retry_timeouts"] = {"retried": len(retry),
                                 "now_correct": sum(correct(r) for r in retry.values()),
                                 "still_system_error": sum(1 for r in retry.values() if r["compilation_result"].get("system_errors"))}
    summary["with_timeout_retry"] = summarize(table(True))
summary["native_decide_in_correct"] = sum(1 for r in comp if correct(r) and "native_decide" in r.get("code", ""))
json.dump(summary, open(f"{R}/audit_summary.json", "w"), indent=2)
print(json.dumps({k: v for k, v in summary.items()}, indent=2)[:3000])
