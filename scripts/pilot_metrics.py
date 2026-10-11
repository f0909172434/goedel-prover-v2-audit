"""試跑成本指標：每次生成的輸出 token 數、截斷比例、Lean 通過數。用法：pilot_metrics.py <run_dir> <model_dir> <wall_seconds>"""
import json, os, statistics, sys
from transformers import AutoTokenizer

run, model, wall = sys.argv[1], sys.argv[2], float(sys.argv[3])
tok = AutoTokenizer.from_pretrained(model)
codes = json.load(open(os.path.join(run, "to_inference_codes.json")))
lens = [len(tok(c["model_output"], add_special_tokens=False)["input_ids"]) for c in codes]
no_code = sum(c["full_code"] == "None" for c in codes)

out = {"generations": len(lens), "wall_seconds_inference": wall,
       "output_tokens_total": sum(lens), "tokens_per_second": sum(lens) / wall if wall else None,
       "mean": statistics.mean(lens), "median": statistics.median(lens), "max": max(lens),
       "p90": sorted(lens)[int(0.9 * (len(lens) - 1))],
       "frac_over_16k": sum(l > 16384 for l in lens) / len(lens),
       "frac_over_30k": sum(l > 30000 for l in lens) / len(lens),
       "no_code_extracted": no_code, "lengths": lens}

comp = os.path.join(run, "code_compilation_repl.json")
if os.path.exists(comp):
    res = json.load(open(comp))
    ok = {}
    for r in res:
        cr = r.get("compilation_result", {})
        # 與官方 summarize.py 相同：complete，且程式碼不含 apply? / exact?
        good = cr.get("complete") is True and "apply?" not in r.get("code", "") and "exact?" not in r.get("code", "")
        pid = r["name"].rsplit("_g", 1)[0]
        ok[pid] = ok.get(pid, False) or good
    out["lean_pass_any"] = sum(ok.values())
    out["problems"] = len(ok)
print(json.dumps({k: v for k, v in out.items() if k != "lengths"}, indent=2))
json.dump(out, open(os.path.join(run, "pilot_metrics.json"), "w"), indent=2)
